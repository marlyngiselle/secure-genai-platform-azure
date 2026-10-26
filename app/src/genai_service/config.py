"""Runtime settings, read from environment variables only."""

from __future__ import annotations

from functools import lru_cache

from pydantic import Field, HttpUrl, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Configuration for the service. Nothing here has a secret default."""

    model_config = SettingsConfigDict(env_prefix="GENAI_", extra="ignore")

    gateway_base_url: HttpUrl = Field(
        description="APIM gateway base URL, for example https://apim-genai-dev.azure-api.net/openai",
    )
    gateway_scope: str = Field(
        default="api://genai-gateway/.default",
        description="Entra ID scope requested for the gateway audience.",
    )
    deployment: str = Field(default="gpt-4o-mini", min_length=1)
    api_version: str = Field(default="2024-10-21")
    subscription_key: SecretStr | None = Field(
        default=None,
        description="APIM subscription key of the team product, injected from Key Vault.",
    )
    request_timeout_seconds: float = Field(default=60.0, gt=0, le=300)
    max_input_chars: int = Field(default=8000, gt=0, le=200_000)
    max_messages: int = Field(default=40, gt=0, le=500)
    applicationinsights_connection_string: SecretStr | None = Field(
        default=None,
        validation_alias="APPLICATIONINSIGHTS_CONNECTION_STRING",
    )
    service_name: str = Field(default="genai-service")


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Return the process wide settings, loaded once."""
    return Settings()
