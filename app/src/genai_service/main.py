"""FastAPI entry point. Run with: uvicorn --factory genai_service.main:create_app"""

from __future__ import annotations

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Literal

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, Field

from . import __version__
from .auth import default_token_provider
from .config import Settings, get_settings
from .gateway import ChatMessage, GatewayClient, GatewayError, GatewayThrottledError
from .guards import PromptGuard, PromptRejectedError
from .redaction import Redactor, RegexPiiRedactor
from .request_context import RequestIdMiddleware, current_request_id
from .telemetry import configure_telemetry

logger = logging.getLogger("genai_service")


class Message(BaseModel):
    role: Literal["system", "user", "assistant"]
    content: str = Field(min_length=1)


class ChatRequest(BaseModel):
    messages: list[Message] = Field(min_length=1)
    stream: bool = False


class ChatResponse(BaseModel):
    content: str
    request_id: str


def create_app(
    settings: Settings | None = None,
    gateway: GatewayClient | None = None,
    guard: PromptGuard | None = None,
    redactor: Redactor | None = None,
) -> FastAPI:
    """Build the application. Every collaborator can be injected for tests."""
    settings = settings or get_settings()
    guard = guard or PromptGuard(
        max_input_chars=settings.max_input_chars,
        max_messages=settings.max_messages,
    )
    redactor = redactor or RegexPiiRedactor()

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        if gateway is not None:
            app.state.gateway = gateway
            yield
            return
        async with httpx.AsyncClient(
            base_url=str(settings.gateway_base_url).rstrip("/"),
            timeout=httpx.Timeout(settings.request_timeout_seconds, connect=5.0),
        ) as http:
            key = settings.subscription_key
            app.state.gateway = GatewayClient(
                http=http,
                tokens=default_token_provider(settings.gateway_scope),
                deployment=settings.deployment,
                api_version=settings.api_version,
                subscription_key=key.get_secret_value() if key else None,
            )
            yield

    app = FastAPI(title="genai-service", version=__version__, lifespan=lifespan)
    app.add_middleware(RequestIdMiddleware)
    configure_telemetry(app, settings)

    @app.exception_handler(PromptRejectedError)
    async def _rejected(_: Request, exc: PromptRejectedError) -> JSONResponse:
        logger.warning("prompt rejected: %s", exc.reason)
        return _error(400, "prompt_rejected", exc.reason)

    @app.exception_handler(GatewayThrottledError)
    async def _throttled(_: Request, exc: GatewayThrottledError) -> JSONResponse:
        response = _error(429, "token_limit_reached", str(exc))
        if exc.retry_after_seconds is not None:
            response.headers["retry-after"] = str(exc.retry_after_seconds)
        return response

    @app.exception_handler(GatewayError)
    async def _gateway_error(_: Request, exc: GatewayError) -> JSONResponse:
        logger.error("gateway error: %s", exc)
        return _error(502, "gateway_error", str(exc))

    @app.get("/healthz")
    async def healthz() -> dict[str, str]:
        return {"status": "ok"}

    @app.post("/v1/chat", response_model=ChatResponse)
    async def chat(body: ChatRequest, request: Request) -> ChatResponse | StreamingResponse:
        guard.check(m.content for m in body.messages)
        messages = [ChatMessage(m.role, redactor.redact(m.content)) for m in body.messages]
        client: GatewayClient = request.app.state.gateway

        if not body.stream:
            content = await client.complete(messages)
            return ChatResponse(content=content, request_id=current_request_id())

        stream = client.stream(messages)
        try:
            first = await anext(stream)
        except StopAsyncIteration:
            first = ""
        except GatewayError:
            await stream.aclose()
            raise

        async def events() -> AsyncIterator[str]:
            if first:
                yield _sse(first)
            try:
                async for delta in stream:
                    yield _sse(delta)
            except GatewayError as exc:
                logger.error("stream interrupted: %s", exc)
                yield "event: error\ndata: upstream interrupted\n\n"
            yield "data: [DONE]\n\n"

        return StreamingResponse(events(), media_type="text/event-stream")

    return app


def _sse(delta: str) -> str:
    escaped = delta.replace("\n", "\\n")
    return f"data: {escaped}\n\n"


def _error(status: int, code: str, message: str) -> JSONResponse:
    return JSONResponse(
        status_code=status,
        content={"error": {"code": code, "message": message, "request_id": current_request_id()}},
    )
