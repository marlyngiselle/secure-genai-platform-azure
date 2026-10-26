"""Request ID propagation from the inbound call to the gateway and the logs."""

from __future__ import annotations

import re
import uuid
from collections.abc import Awaitable, Callable
from contextvars import ContextVar

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

REQUEST_ID_HEADER = "x-request-id"
_SAFE_ID = re.compile(r"^[A-Za-z0-9._-]{8,128}$")

_request_id: ContextVar[str | None] = ContextVar("request_id", default=None)


def current_request_id() -> str:
    """Return the request ID bound to the current context, creating one if needed."""
    value = _request_id.get()
    if value is None:
        value = new_request_id()
        _request_id.set(value)
    return value


def new_request_id() -> str:
    return uuid.uuid4().hex


def sanitize_request_id(candidate: str | None) -> str:
    """Accept a caller supplied ID only if it is safe to log and forward."""
    if candidate and _SAFE_ID.match(candidate):
        return candidate
    return new_request_id()


class RequestIdMiddleware(BaseHTTPMiddleware):
    """Bind a request ID to the context and echo it on the response."""

    async def dispatch(
        self,
        request: Request,
        call_next: Callable[[Request], Awaitable[Response]],
    ) -> Response:
        request_id = sanitize_request_id(request.headers.get(REQUEST_ID_HEADER))
        token = _request_id.set(request_id)
        try:
            response = await call_next(request)
        finally:
            _request_id.reset(token)
        response.headers[REQUEST_ID_HEADER] = request_id
        return response
