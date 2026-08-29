from pathlib import Path
from typing import Any, Self

import yaml
from pydantic import AliasChoices, BaseModel, ConfigDict, Field, ValidationError, model_validator

from asta_cloud.models.enums import Severity

DEFAULT_EXCLUDE: tuple[str, ...] = (
    ".git",
    ".venv",
    "venv",
    "__pycache__",
    ".mypy_cache",
    ".ruff_cache",
    "dist",
    "build",
    "node_modules",
    "tests",
    "unit_tests",
    "integration_tests",
)

DEFAULT_MAX_FILE_BYTES = 1_048_576


class ConfigError(Exception):
    """Invalid or missing scanner configuration (CLI exit 2)."""


class ScanConfig(BaseModel):
    model_config = ConfigDict(extra="forbid")

    exclude: list[str] = Field(default_factory=lambda: list(DEFAULT_EXCLUDE))
    fail_on: Severity = Severity.HIGH
    enabled_rules: list[str] | None = None
    max_file_bytes: int = Field(default=DEFAULT_MAX_FILE_BYTES, ge=1)
    severity: dict[str, Severity] = Field(default_factory=dict)
    enable_validation: bool = Field(
        default=False,
        validation_alias=AliasChoices("validate", "enable_validation"),
    )
    baseline: str | None = None

    @model_validator(mode="after")
    def validate_severity_keys(self) -> Self:
        if not self.severity:
            return self
        from asta_cloud.rules.registry import known_rule_ids

        known = known_rule_ids()
        unknown = [rule_id for rule_id in self.severity if rule_id not in known]
        if unknown:
            raise ValueError(f"Unknown rule id(s): {', '.join(unknown)}")
        return self


def load_config(explicit: Path | None, root: Path) -> tuple[ScanConfig, Path | None]:
    """Load YAML config from --config, else TARGET/asta.yaml, else defaults."""
    if explicit is not None:
        path = explicit.expanduser()
        if not path.is_file():
            raise ConfigError(f"Config file not found: {path}")
        return _parse_config_file(path), path.resolve()

    default = root / "asta.yaml"
    if default.is_file():
        return _parse_config_file(default), default.resolve()
    return ScanConfig(), None


def _parse_config_file(path: Path) -> ScanConfig:
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise ConfigError(f"Unable to read config file: {path}") from exc

    try:
        loaded: Any = yaml.safe_load(raw)
    except yaml.YAMLError as exc:
        raise ConfigError(f"Invalid YAML in config file: {path}") from exc

    if loaded is None:
        data: dict[str, Any] = {}
    elif isinstance(loaded, dict):
        data = dict(loaded)
    else:
        raise ConfigError(f"Config file must contain a mapping: {path}")

    if "enabled_rules" in data and data["enabled_rules"] == "all":
        data["enabled_rules"] = None

    try:
        return ScanConfig.model_validate(data)
    except ValidationError as exc:
        raise ConfigError(f"Invalid config in {path}: {exc}") from exc
