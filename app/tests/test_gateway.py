from __future__ import annotations

import json
from collections.abc import Callable

import httpx
import pytest

from genai_service.gateway import (
    ChatMessage,
    GatewayClient,
    GatewayError,
    GatewayThrottledError,
    parse_sse_line,
)

from .conftest import sse_body

MakeGateway = Callable[[Callable[[httpx.Request], httpx.Response]], GatewayClient]
MESSAGES = [ChatMessage("user", "hello")]


async def test_complete_sends_identity_key_and_request_id(make_gateway: MakeGateway) -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={"choices": [{"message": {"content": "hi there"}}]})

    result = await make_gateway(handler).complete(MESSAGES)

    assert result == "hi there"
    request = seen[0]
    assert request.url.path == "/openai/deployments/gpt-4o-mini/chat/completions"
    assert request.url.params["api-version"] == "2024-10-21"
    assert request.headers["authorization"] == "Bearer test-token"
    assert request.headers["ocp-apim-subscription-key"] == "sub-key-placeholder"
    assert len(request.headers["x-request-id"]) >= 8
    assert "api-key" not in request.headers
    assert json.loads(request.content)["stream"] is False


async def test_throttling_maps_retry_after(make_gateway: MakeGateway) -> None:
    gateway = make_gateway(lambda _: httpx.Response(429, headers={"retry-after": "12"}))

    with pytest.raises(GatewayThrottledError) as info:
        await gateway.complete(MESSAGES)

    assert info.value.retry_after_seconds == 12


@pytest.mark.parametrize("status", [401, 403, 500, 503])
async def test_errors_are_mapped_to_502(make_gateway: MakeGateway, status: int) -> None:
    gateway = make_gateway(lambda _: httpx.Response(status, json={"error": "boom"}))

    with pytest.raises(GatewayError) as info:
        await gateway.complete(MESSAGES)

    assert info.value.status_code == 502


async def test_unexpected_shape_is_an_error(make_gateway: MakeGateway) -> None:
    gateway = make_gateway(lambda _: httpx.Response(200, json={"choices": []}))

    with pytest.raises(GatewayError, match="unexpected response shape"):
        await gateway.complete(MESSAGES)


async def test_stream_yields_deltas_in_order(make_gateway: MakeGateway) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        assert json.loads(request.content)["stream"] is True
        return httpx.Response(
            200,
            headers={"content-type": "text/event-stream"},
            content=sse_body("Hel", "lo", " world"),
        )

    chunks = [c async for c in make_gateway(handler).stream(MESSAGES)]

    assert chunks == ["Hel", "lo", " world"]


async def test_stream_raises_before_first_chunk_on_throttle(make_gateway: MakeGateway) -> None:
    gateway = make_gateway(lambda _: httpx.Response(429))

    with pytest.raises(GatewayThrottledError):
        _ = [c async for c in gateway.stream(MESSAGES)]


@pytest.mark.parametrize(
    ("line", "expected"),
    [
        ("", None),
        (": keep-alive", None),
        ("data: not-json", None),
        ('data: {"choices": []}', None),
        ('data: {"choices": [{"delta": {"role": "assistant"}}]}', None),
        ('data: {"choices": [{"delta": {"content": "x"}}]}', "x"),
    ],
)
def test_parse_sse_line(line: str, expected: str | None) -> None:
    assert parse_sse_line(line) == expected
