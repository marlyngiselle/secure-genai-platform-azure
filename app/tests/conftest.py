from __future__ import annotations

import json
from collections.abc import Callable

import httpx
import pytest

from genai_service.config import Settings
from genai_service.gateway import GatewayClient

GATEWAY = "https://apim-example.azure-api.net/openai"


class StaticTokens:
    def __init__(self, value: str = "test-token") -> None:
        self.value = value
        self.calls = 0

    async def token(self) -> str:
        self.calls += 1
        return self.value


def sse_body(*deltas: str) -> bytes:
    lines = []
    for d in deltas:
        event = {"choices": [{"index": 0, "delta": {"content": d}}]}
        lines.append(f"data: {json.dumps(event)}\n\n")
    lines.append("data: [DONE]\n\n")
    return "".join(lines).encode()


@pytest.fixture
def settings() -> Settings:
    return Settings(gateway_base_url=GATEWAY, subscription_key="sub-key-placeholder")


@pytest.fixture
def make_gateway() -> Callable[[Callable[[httpx.Request], httpx.Response]], GatewayClient]:
    def factory(handler: Callable[[httpx.Request], httpx.Response]) -> GatewayClient:
        http = httpx.AsyncClient(base_url=GATEWAY, transport=httpx.MockTransport(handler))
        return GatewayClient(
            http=http,
            tokens=StaticTokens(),
            deployment="gpt-4o-mini",
            api_version="2024-10-21",
            subscription_key="sub-key-placeholder",
        )

    return factory
