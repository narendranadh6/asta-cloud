from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, ValidationError

from asta_cloud.models.finding import Finding

BASELINE_SCHEMA_VERSION = "1.0.0"


class BaselineError(Exception):
    """Invalid or unreadable baseline file (CLI exit 2)."""


class Baseline(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schema_version: str = BASELINE_SCHEMA_VERSION
    findings: list[str] = Field(default_factory=list)

    @property
    def suppressed_ids(self) -> set[str]:
        return set(self.findings)


def resolve_baseline_path(root: Path, configured: str | Path) -> Path:
    path = Path(configured).expanduser()
    if not path.is_absolute():
        path = root / path
    return path.resolve()


def load_baseline(path: Path) -> Baseline:
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise BaselineError(f"Unable to read baseline file: {path}") from exc

    try:
        loaded: Any = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise BaselineError(f"Invalid JSON in baseline file: {path}") from exc

    if not isinstance(loaded, dict):
        raise BaselineError(f"Baseline file must contain a JSON object: {path}")

    try:
        return Baseline.model_validate(loaded)
    except ValidationError as exc:
        raise BaselineError(f"Invalid baseline in {path}: {exc}") from exc


def save_baseline(path: Path, findings: list[Finding]) -> None:
    baseline = Baseline(findings=sorted({item.instance_id for item in findings}))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(baseline.model_dump(), indent=2) + "\n",
        encoding="utf-8",
    )


def apply_baseline(findings: list[Finding], baseline: Baseline) -> tuple[list[Finding], int]:
    suppressed = baseline.suppressed_ids
    if not suppressed:
        return findings, 0
    kept = [item for item in findings if item.instance_id not in suppressed]
    return kept, len(findings) - len(kept)
