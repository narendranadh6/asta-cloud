from pathlib import Path

import pytest

from asta_cloud.baseline import (
    Baseline,
    BaselineError,
    apply_baseline,
    load_baseline,
    resolve_baseline_path,
    save_baseline,
)
from asta_cloud.models.enums import Confidence, Severity, ValidationStatus
from asta_cloud.models.finding import Evidence, Finding
from asta_cloud.models.location import Location


def _finding(instance_id: str) -> Finding:
    return Finding(
        instance_id=instance_id,
        rule_id=instance_id.split(":")[0],
        title="Test",
        description="Test",
        severity=Severity.HIGH,
        confidence=Confidence.MEDIUM,
        location=Location(path="app.py", line=1),
        evidence=Evidence(snippet="x = 1"),
        remediation="Fix it",
        validation_status=ValidationStatus.SUSPECTED,
    )


def test_resolve_baseline_path_relative_to_target(tmp_path: Path) -> None:
    path = resolve_baseline_path(tmp_path, "asta-baseline.json")
    assert path == (tmp_path / "asta-baseline.json").resolve()


def test_save_and_load_baseline(tmp_path: Path) -> None:
    path = tmp_path / "asta-baseline.json"
    findings = [_finding("ASTA-SEC-001:app.py:1"), _finding("ASTA-SEC-002:app.py:2")]
    save_baseline(path, findings)

    loaded = load_baseline(path)
    assert loaded.findings == [
        "ASTA-SEC-001:app.py:1",
        "ASTA-SEC-002:app.py:2",
    ]


def test_apply_baseline_filters_matching_findings() -> None:
    findings = [
        _finding("ASTA-SEC-001:app.py:1"),
        _finding("ASTA-SEC-002:app.py:2"),
    ]
    baseline = Baseline(findings=["ASTA-SEC-001:app.py:1"])

    kept, suppressed = apply_baseline(findings, baseline)
    assert [item.instance_id for item in kept] == ["ASTA-SEC-002:app.py:2"]
    assert suppressed == 1


def test_load_baseline_rejects_invalid_json(tmp_path: Path) -> None:
    path = tmp_path / "asta-baseline.json"
    path.write_text("{not json", encoding="utf-8")
    with pytest.raises(BaselineError, match="Invalid JSON"):
        load_baseline(path)


def test_load_baseline_rejects_unknown_fields(tmp_path: Path) -> None:
    path = tmp_path / "asta-baseline.json"
    path.write_text('{"schema_version": "1.0.0", "extra": true}\n', encoding="utf-8")
    with pytest.raises(BaselineError, match="Invalid baseline"):
        load_baseline(path)
