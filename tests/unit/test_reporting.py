from datetime import UTC, datetime

from asta_cloud.models.enums import Confidence, Severity, ValidationStatus
from asta_cloud.models.finding import Evidence, Finding
from asta_cloud.models.inventory import Inventory
from asta_cloud.models.location import Location
from asta_cloud.models.report import ScanReport, Summary
from asta_cloud.reporting import render_report
from asta_cloud.reporting.json_report import render_json
from asta_cloud.reporting.sarif_report import SARIF_VERSION, build_sarif
from asta_cloud.security.redact import redact_report


def test_json_report_redacts_secrets_and_includes_required_fields() -> None:
    secret = "sk-astaCloudFixtureKeyDoNotUse0001"
    report = ScanReport(
        schema_version="1.0.0",
        product="asta-cloud",
        scanned_at=datetime.now(UTC),
        target="/tmp/example",
        config_path=None,
        validation_performed=False,
        notes=["No runtime validation was performed and target code was not executed."],
        inventory=Inventory(target="/tmp/example", python_files=["app.py"]),
        findings=[
            Finding(
                instance_id="ASTA-SEC-001:app.py:1",
                rule_id="ASTA-SEC-001",
                title="Hard-coded secrets or API keys",
                description="secret",
                severity=Severity.HIGH,
                confidence=Confidence.HIGH,
                location=Location(path="app.py", line=1),
                evidence=Evidence(snippet=f"OPENAI_API_KEY = '{secret}'"),
                remediation="use env",
                validation_status=ValidationStatus.SUSPECTED,
                owasp=["LLM06:2025"],
            )
        ],
        summary=Summary(
            files_scanned=1,
            findings_by_severity={"high": 1},
            high_or_above=1,
        ),
    )
    text = render_json(redact_report(report))
    assert secret not in text
    assert '"rule_id": "ASTA-SEC-001"' in text
    assert '"validation_performed": false' in text
    assert '"validation_status": "suspected"' in text


def test_sarif_report_contains_rule_ids_and_no_secrets() -> None:
    secret = "sk-astaCloudFixtureKeyDoNotUse0001"
    report = _sample_report(secret)
    sarif = build_sarif(redact_report(report))
    assert sarif["version"] == SARIF_VERSION
    run = sarif["runs"][0]
    rule_ids = {rule["id"] for rule in run["tool"]["driver"]["rules"]}
    result_ids = {result["ruleId"] for result in run["results"]}
    assert "ASTA-SEC-001" in rule_ids
    assert "ASTA-SEC-001" in result_ids
    rendered = render_report(redact_report(report), "sarif")
    assert secret not in rendered
    assert run["invocations"][0]["executionSuccessful"] is True


def test_text_report_contains_validation_and_summary() -> None:
    report = _sample_report("sk-ignored")
    text = render_report(redact_report(report), "text")
    assert "ASTA Cloud" in text
    assert "validation: suspected" in text
    assert "summary: files=" in text
    assert "ASTA-SEC-001" in text


def _sample_report(secret: str) -> ScanReport:
    return ScanReport(
        schema_version="1.0.0",
        product="asta-cloud",
        scanned_at=datetime.now(UTC),
        target="/tmp/example",
        config_path=None,
        validation_performed=False,
        notes=["No runtime validation was performed and target code was not executed."],
        inventory=Inventory(target="/tmp/example", python_files=["app.py"]),
        findings=[
            Finding(
                instance_id="ASTA-SEC-001:app.py:1",
                rule_id="ASTA-SEC-001",
                title="Hard-coded secrets or API keys",
                description="secret",
                severity=Severity.HIGH,
                confidence=Confidence.HIGH,
                location=Location(path="app.py", line=1),
                evidence=Evidence(snippet=f"OPENAI_API_KEY = '{secret}'"),
                remediation="use env",
                validation_status=ValidationStatus.SUSPECTED,
                owasp=["LLM06:2025"],
            )
        ],
        summary=Summary(
            files_scanned=1,
            findings_by_severity={"high": 1},
            high_or_above=1,
        ),
    )
