"""Application settings loaded from the environment (never from source control)."""

from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Track metadata is cached at most this long before it is refreshed from its source.
CATALOG_MAX_CACHE_SECONDS = 30 * 24 * 60 * 60


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="HALO_", env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )

    environment: Literal["development", "test", "production"] = "development"
    debug: bool = False
    api_title: str = "Halo API"

    database_url: str = "postgresql+asyncpg://halo:halo@localhost:5432/halo"
    redis_url: str | None = "redis://localhost:6379/0"

    # Auth: HS256 signing secret for device tokens. Must be set in production.
    jwt_secret: SecretStr = SecretStr("dev-only-insecure-secret-change-me-0123456789")
    jwt_issuer: str = "halo-api"
    access_token_ttl_days: int = Field(default=30, ge=1, le=365)

    # Playable catalog. Audio streams from the source straight to the listener's device.
    # Audius: free full tracks, no key needed (a key only raises rate limits).
    audius_enabled: bool = True
    audius_api_key: SecretStr | None = None
    audius_base_url: str = "https://api.audius.co/v1"
    # Jamendo: free full Creative Commons tracks; needs a free client id (devportal.jamendo.com).
    jamendo_client_id: SecretStr | None = None
    # iTunes Search API: 30-second previews, labelled as previews and linked to Apple Music.
    itunes_previews_enabled: bool = True
    itunes_country: str = "IN"
    catalog_search_ttl_seconds: int = 6 * 60 * 60
    catalog_track_ttl_seconds: int = 24 * 60 * 60

    # Open music data (optional). Similar artists improve candidate generation.
    lastfm_api_key: SecretStr | None = None
    deezer_enabled: bool = True
    radio_browser_base_url: str = "https://de1.api.radio-browser.info"
    # MusicBrainz (canonical metadata) and ListenBrainz (discovery). Both are open data.
    musicbrainz_enabled: bool = True
    musicbrainz_contact: str = "https://github.com/narendranadh6/asta-cloud"
    listenbrainz_enabled: bool = True
    listenbrainz_token: SecretStr | None = None
    # Catalog lookups per request for ListenBrainz track picks.
    listenbrainz_track_lookups: int = Field(default=4, ge=0, le=10)
    # Home feed: section type -> base score. Higher ranks earlier; 0 or less removes the
    # section. JSON in the environment, e.g. HALO_HOME_SECTION_WEIGHTS='{"trending": 0}'.
    # Merged over the defaults in app/services/feed/builder.py.
    home_section_weights: dict[str, float] = Field(default_factory=dict)

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
            raise ValueError("HALO_JWT_SECRET must not be empty (unset it to use the dev default)")
        return value

    @field_validator("catalog_search_ttl_seconds", "catalog_track_ttl_seconds")
    @classmethod
    def _clamp_retention(cls, value: int) -> int:
        return max(0, min(value, CATALOG_MAX_CACHE_SECONDS))

    def validate_for_production(self) -> None:
        if self.environment != "production":
            return
        problems: list[str] = []
        if self.jwt_secret.get_secret_value().startswith("dev-only"):
            problems.append("HALO_JWT_SECRET must be set")
        if len(self.jwt_secret.get_secret_value()) < 32:
            problems.append("HALO_JWT_SECRET must be at least 32 characters")
        jamendo = self.jamendo_client_id.get_secret_value() if self.jamendo_client_id else ""
        if not (self.audius_enabled or jamendo.strip() or self.itunes_previews_enabled):
            problems.append("enable at least one music source (Audius, Jamendo or iTunes)")
        if self.debug:
            problems.append("HALO_DEBUG must be false")
        if problems:
            raise RuntimeError("Invalid production configuration: " + "; ".join(problems))


@lru_cache
def get_settings() -> Settings:
    return Settings()
