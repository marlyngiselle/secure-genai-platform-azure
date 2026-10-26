from __future__ import annotations

import time

from azure.core.credentials import AccessToken

from genai_service.auth import CachedTokenProvider


class FakeCredential:
    def __init__(self, lifetime_seconds: int) -> None:
        self.lifetime = lifetime_seconds
        self.calls: list[tuple[str, ...]] = []

    async def get_token(self, *scopes: str) -> AccessToken:
        self.calls.append(scopes)
        return AccessToken(f"token-{len(self.calls)}", int(time.time()) + self.lifetime)


async def test_token_is_cached_while_fresh() -> None:
    credential = FakeCredential(lifetime_seconds=3600)
    provider = CachedTokenProvider(credential, "api://genai-gateway/.default")

    assert await provider.token() == "token-1"
    assert await provider.token() == "token-1"
    assert credential.calls == [("api://genai-gateway/.default",)]


async def test_token_is_refreshed_inside_margin() -> None:
    credential = FakeCredential(lifetime_seconds=60)
    provider = CachedTokenProvider(credential, "scope", refresh_margin_seconds=300)

    assert await provider.token() == "token-1"
    assert await provider.token() == "token-2"
