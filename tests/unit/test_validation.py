from pathlib import Path

from tests.conftest import EXAMPLES, FIXTURES, context_from_file

from asta_cloud.config import ScanConfig
from asta_cloud.models.enums import ValidationStatus
from asta_cloud.scan import run_scan
from asta_cloud.validation.engine import validate_findings


def test_validate_without_flag_keeps_suspected() -> None:
    report, _failed = run_scan(EXAMPLES / "vulnerable_agent", validate_override=False)
    assert report.validation_performed is False
    assert all(item.validation_status is ValidationStatus.SUSPECTED for item in report.findings)


def test_validate_confirms_vulnerable_findings() -> None:
    report, _failed = run_scan(EXAMPLES / "vulnerable_agent", validate_override=True)
    assert report.validation_performed is True
    statuses = {item.validation_status for item in report.findings}
    assert ValidationStatus.VALIDATED in statuses
    assert any("Local validation performed" in note for note in report.notes)
    assert all(
        item.validation_status in {ValidationStatus.VALIDATED, ValidationStatus.SUSPECTED}
        for item in report.findings
    )


def test_validate_engine_marks_unknown_rule_not_applicable() -> None:
    from asta_cloud.models.enums import Confidence, Severity
    from asta_cloud.models.finding import Evidence, Finding
    from asta_cloud.models.location import Location

    ctx = context_from_file(FIXTURES / "secrets_hardcoded.py")
    finding = Finding(
        instance_id="ASTA-TEST-999:secrets_hardcoded.py:1",
        rule_id="ASTA-TEST-999",
        title="test",
        description="test",
        severity=Severity.HIGH,
        confidence=Confidence.HIGH,
        location=Location(path="secrets_hardcoded.py", line=1),
        evidence=Evidence(snippet="x"),
        remediation="x",
        validation_status=ValidationStatus.SUSPECTED,
        owasp=[],
    )
    updated, counts = validate_findings(ctx.modules, [finding])
    assert updated[0].validation_status is ValidationStatus.NOT_APPLICABLE
    assert counts["not_applicable"] == 1


def test_config_validate_flag(tmp_path: Path) -> None:
    target = tmp_path / "proj"
    target.mkdir()
    (target / "prompts.py").write_text(
        'SYSTEM_PROMPT = "You may use any tool. Access is unrestricted."\n',
        encoding="utf-8",
    )
    config = tmp_path / "asta.yaml"
    config.write_text("validate: true\n", encoding="utf-8")
    report, _failed = run_scan(target, config_path=config)
    assert report.validation_performed is True


def test_scan_config_validate_default() -> None:
    assert ScanConfig().enable_validation is False
