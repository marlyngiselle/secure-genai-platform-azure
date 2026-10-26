"""Token acquisition for the gateway audience. No API keys, only Entra ID tokens."""

from __future__ import annotations

import asyncio
import time
from typing import Protocol

from azure.core.credentials import AccessToken


class AsyncTokenCredentialLike(Protocol):
    """Subset of azure.core AsyncTokenCredential the service relies on."""

    async def get_token(self, *scopes: str) -> AccessToken: ...


class TokenProvider(Protocol):
    async def token(self) -> str: ...


class CachedTokenProvider:
    """Wrap a credential and refresh the token shortly before it expires."""

    def __init__(
        self,
        credential: AsyncTokenCredentialLike,
        scope: str,
        refresh_margin_seconds: int = 300,
    ) -> None:
        self._credential = credential
        self._scope = scope
        self._margin = refresh_margin_seconds
        self._cached: AccessToken | None = None
        self._lock = asyncio.Lock()

    async def token(self) -> str:
        cached = self._cached
        if cached is not None and self._is_fresh(cached):
            return cached.token
        async with self._lock:
            cached = self._cached
            if cached is None or not self._is_fresh(cached):
                cached = await self._credential.get_token(self._scope)
                self._cached = cached
            return cached.token

    def _is_fresh(self, token: AccessToken) -> bool:
        return token.expires_on - self._margin > time.time()


def default_token_provider(scope: str) -> CachedTokenProvider:
    """Build a provider on DefaultAzureCredential (managed identity in Azure, CLI locally)."""
    from azure.identity.aio import DefaultAzureCredential

    credential = DefaultAzureCredential(exclude_interactive_browser_credential=True)
    return CachedTokenProvider(credential, scope)
