from typing import Protocol

from asta_cloud.analyzers.context import ScanContext
from asta_cloud.models.enums import Confidence, Severity, ValidationStatus
from asta_cloud.models.finding import Evidence, Finding
from asta_cloud.models.location import Location
from asta_cloud.security.redact import redact_text


class Rule(Protocol):
    id: str
    title: str
    severity: Severity

    def check(self, ctx: ScanContext) -> list[Finding]: ...


def make_finding(
    *,
    rule_id: str,
    title: str,
    description: str,
    severity: Severity,
    confidence: Confidence,
    location: Location,
    snippet: str,
    remediation: str,
    owasp: list[str],
    call_name: str | None = None,
) -> Finding:
    return Finding(
        instance_id=f"{rule_id}:{location.path}:{location.line or 0}",
        rule_id=rule_id,
        title=title,
        description=description,
        severity=severity,
        confidence=confidence,
        location=location,
        evidence=Evidence(snippet=redact_text(snippet), call_name=call_name),
        remediation=remediation,
        validation_status=ValidationStatus.SUSPECTED,
        owasp=owasp,
    )
