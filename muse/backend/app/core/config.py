"""Application settings loaded from the environment (never from source control)."""

from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# YouTube API Services Developer Policies limit storage of non-authorized API data to
# 30 days before it must be refreshed or deleted. Cache TTLs are clamped to this.
YOUTUBE_MAX_RETENTION_SECONDS = 30 * 24 * 60 * 60


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="MUSE_", env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )

    environment: Literal["development", "test", "production"] = "development"
    debug: bool = False
    api_title: str = "MUSE API"

    database_url: str = "postgresql+asyncpg://muse:muse@localhost:5432/muse"
    redis_url: str | None = "redis://localhost:6379/0"

    # Auth: HS256 signing secret for device tokens. Must be set in production.
    jwt_secret: SecretStr = SecretStr("dev-only-insecure-secret-change-me-0123456789")
    jwt_issuer: str = "muse-api"
    access_token_ttl_days: int = Field(default=30, ge=1, le=365)

    # YouTube Data API v3
    youtube_provider: Literal["youtube", "mock"] = "mock"
    youtube_api_key: SecretStr | None = None
    youtube_api_base_url: str = "https://www.googleapis.com/youtube/v3"
    youtube_region_code: str = "US"
    youtube_timeout_seconds: float = 8.0
    youtube_search_cache_ttl_seconds: int = 6 * 60 * 60
    youtube_video_cache_ttl_seconds: int = 24 * 60 * 60

    # LLM planner
    llm_provider: Literal["none", "anthropic", "openai"] = "none"
    llm_api_key: SecretStr | None = None
    llm_model: str = "claude-sonnet-5-5"
    llm_base_url: str | None = None
    llm_timeout_seconds: float = 20.0

    # Rate limits (requests per minute per user, or per IP when unauthenticated)
    rate_limit_search_per_minute: int = 30
    rate_limit_ai_per_minute: int = 6
    rate_limit_default_per_minute: int = 120
    rate_limit_auth_per_minute: int = 10

    cors_origins: list[str] = Field(default_factory=list)

    @field_validator("jwt_secret")
    @classmethod
    def _non_empty_secret(cls, value: SecretStr) -> SecretStr:
        if not value.get_secret_value().strip():
            raise ValueError("MUSE_JWT_SECRET must not be empty (unset it to use the dev default)")
        return value

    @field_validator("youtube_search_cache_ttl_seconds", "youtube_video_cache_ttl_seconds")
    @classmethod
    def _clamp_retention(cls, value: int) -> int:
        return max(0, min(value, YOUTUBE_MAX_RETENTION_SECONDS))

    def validate_for_production(self) -> None:
        if self.environment != "production":
            return
        problems: list[str] = []
        if self.jwt_secret.get_secret_value().startswith("dev-only"):
            problems.append("MUSE_JWT_SECRET must be set")
        if len(self.jwt_secret.get_secret_value()) < 32:
            problems.append("MUSE_JWT_SECRET must be at least 32 characters")
        if self.youtube_provider == "youtube" and not self.youtube_api_key:
            problems.append("MUSE_YOUTUBE_API_KEY is required when MUSE_YOUTUBE_PROVIDER=youtube")
        if self.debug:
            problems.append("MUSE_DEBUG must be false")
        if problems:
            raise RuntimeError("Invalid production configuration: " + "; ".join(problems))


@lru_cache
def get_settings() -> Settings:
    return Settings()
