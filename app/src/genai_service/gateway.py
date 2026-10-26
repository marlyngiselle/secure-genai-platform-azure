"""Client for the APIM AI gateway. Speaks the Azure OpenAI chat completions contract."""

from __future__ import annotations

import json
from collections.abc import AsyncGenerator, Sequence
from dataclasses import dataclass
from typing import Any

import httpx

from .auth import TokenProvider
from .request_context import REQUEST_ID_HEADER, current_request_id


class GatewayError(Exception):
    """The gateway returned an error the caller should see as a 502."""

    def __init__(self, status_code: int, message: str) -> None:
        super().__init__(message)
        self.status_code = status_code


class GatewayThrottledError(GatewayError):
    """Token limit reached for this team. Carries the gateway retry hint."""

    def __init__(self, retry_after_seconds: int | None) -> None:
        super().__init__(429, "token limit reached for this subscription")
        self.retry_after_seconds = retry_after_seconds


@dataclass(frozen=True)
class ChatMessage:
    role: str
    content: str

    def as_dict(self) -> dict[str, str]:
        return {"role": self.role, "content": self.content}


class GatewayClient:
    """Async client. One instance per process, sharing the HTTP connection pool."""

    def __init__(
        self,
        http: httpx.AsyncClient,
        tokens: TokenProvider,
        deployment: str,
        api_version: str,
        subscription_key: str | None = None,
    ) -> None:
        self._http = http
        self._tokens = tokens
        self._deployment = deployment
        self._api_version = api_version
        self._subscription_key = subscription_key

    @property
    def _path(self) -> str:
        return f"/deployments/{self._deployment}/chat/completions"

    async def _headers(self) -> dict[str, str]:
        headers = {
            "Authorization": f"Bearer {await self._tokens.token()}",
            "Content-Type": "application/json",
            REQUEST_ID_HEADER: current_request_id(),
        }
        if self._subscription_key:
            headers["Ocp-Apim-Subscription-Key"] = self._subscription_key
        return headers

    def _payload(self, messages: Sequence[ChatMessage], stream: bool) -> dict[str, Any]:
        return {"messages": [m.as_dict() for m in messages], "stream": stream}

    async def complete(self, messages: Sequence[ChatMessage]) -> str:
        response = await self._http.post(
            self._path,
            params={"api-version": self._api_version},
            headers=await self._headers(),
            json=self._payload(messages, stream=False),
        )
        _raise_for_gateway(response)
        body = response.json()
        try:
            return str(body["choices"][0]["message"]["content"] or "")
        except (KeyError, IndexError, TypeError) as exc:
            raise GatewayError(502, "unexpected response shape from gateway") from exc

    async def stream(self, messages: Sequence[ChatMessage]) -> AsyncGenerator[str, None]:
        """Yield content deltas as they arrive (server sent events)."""
        request = self._http.build_request(
            "POST",
            self._path,
            params={"api-version": self._api_version},
            headers=await self._headers(),
            json=self._payload(messages, stream=True),
        )
        response = await self._http.send(request, stream=True)
        try:
            if response.status_code >= 400:
                await response.aread()
                _raise_for_gateway(response)
            async for line in response.aiter_lines():
                delta = parse_sse_line(line)
                if delta is None:
                    continue
                if delta == _DONE:
                    break
                yield delta
        finally:
            await response.aclose()


_DONE = "\x00done"


def parse_sse_line(line: str) -> str | None:
    """Return the content delta of one SSE line, _DONE at the end, or None to skip."""
    if not line.startswith("data:"):
        return None
    data = line[len("data:") :].strip()
    if data == "[DONE]":
        return _DONE
    try:
        event = json.loads(data)
    except json.JSONDecodeError:
        return None
    choices = event.get("choices") or []
    if not choices:
        return None
    content = (choices[0].get("delta") or {}).get("content")
    return content if isinstance(content, str) and content else None


def _raise_for_gateway(response: httpx.Response) -> None:
    if response.status_code < 400:
        return
    if response.status_code == 429:
        retry_after = response.headers.get("retry-after")
        raise GatewayThrottledError(
            int(retry_after) if retry_after and retry_after.isdigit() else None
        )
    if response.status_code in (401, 403):
        raise GatewayError(502, "gateway rejected the service identity")
    raise GatewayError(502, f"gateway returned HTTP {response.status_code}")
