from __future__ import annotations

import json
from typing import Any

from asta_cloud import __version__
from asta_cloud.models.enums import Severity
from asta_cloud.models.finding import Finding
from asta_cloud.models.report import ScanReport

SARIF_SCHEMA = "https://json.schemastore.org/sarif-2.1.0.json"
SARIF_VERSION = "2.1.0"

_LEVEL_MAP = {
    Severity.CRITICAL: "error",
    Severity.HIGH: "error",
    Severity.MEDIUM: "warning",
    Severity.LOW: "note",
    Severity.INFO: "note",
}


def render_sarif(report: ScanReport) -> str:
    payload = build_sarif(report)
    return json.dumps(payload, indent=2) + "\n"


def build_sarif(report: ScanReport) -> dict[str, Any]:
    rules_by_id = _build_rules(report.findings)
    return {
        "$schema": SARIF_SCHEMA,
        "version": SARIF_VERSION,
        "runs": [
            {
                "tool": {
                    "driver": {
                        "name": "ASTA Cloud",
                        "semanticVersion": __version__,
                        "informationUri": "https://github.com/asta-cloud/asta-cloud",
                        "rules": list(rules_by_id.values()),
                    }
                },
                "invocations": [{"executionSuccessful": True}],
                "results": [_build_result(finding) for finding in report.findings],
            }
        ],
    }


def _build_rules(findings: list[Finding]) -> dict[str, dict[str, Any]]:
    rules: dict[str, dict[str, Any]] = {}
    for finding in findings:
        if finding.rule_id in rules:
            continue
        rules[finding.rule_id] = {
            "id": finding.rule_id,
            "shortDescription": {"text": finding.title},
            "fullDescription": {"text": finding.description},
            "help": {"text": finding.remediation},
            "properties": {"owasp": finding.owasp},
        }
    return rules


def _build_result(finding: Finding) -> dict[str, Any]:
    location: dict[str, Any] = {
        "physicalLocation": {
            "artifactLocation": {"uri": finding.location.path},
        }
    }
    if finding.location.line is not None:
        region: dict[str, int] = {"startLine": finding.location.line}
        if finding.location.end_line is not None:
            region["endLine"] = finding.location.end_line
        location["physicalLocation"]["region"] = region

    message = f"{finding.title}: {finding.description}"
    if finding.evidence.snippet:
        message = f"{message} Evidence: {finding.evidence.snippet}"

    result: dict[str, Any] = {
        "ruleId": finding.rule_id,
        "level": _LEVEL_MAP[finding.severity],
        "message": {"text": message},
        "locations": [location],
        "partialFingerprints": {"instanceId": finding.instance_id},
        "properties": {
            "confidence": finding.confidence.value,
            "validationStatus": finding.validation_status.value,
            "owasp": finding.owasp,
            "remediation": finding.remediation,
        },
    }
    if finding.evidence.call_name:
        result["properties"]["callName"] = finding.evidence.call_name
    return result
