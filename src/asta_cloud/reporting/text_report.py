from __future__ import annotations

from asta_cloud import __version__
from asta_cloud.models.enums import Severity
from asta_cloud.models.report import ScanReport


def render_text(report: ScanReport) -> str:
    lines: list[str] = [
        f"ASTA Cloud {__version__}",
        f"target: {report.target}",
        f"validation_performed: {str(report.validation_performed).lower()}",
        "",
    ]

    for finding in report.findings:
        line_no = finding.location.line if finding.location.line is not None else 0
        lines.append(
            f"{finding.location.path}:{line_no}: "
            f"{finding.severity.value} {finding.rule_id} {finding.title}"
        )
        lines.append(f"  description: {finding.description}")
        if finding.evidence.snippet:
            lines.append(f"  evidence: {finding.evidence.snippet}")
        if finding.evidence.call_name:
            lines.append(f"  call: {finding.evidence.call_name}")
        lines.append(f"  remediation: {finding.remediation}")
        if finding.owasp:
            lines.append(f"  owasp: {', '.join(finding.owasp)}")
        lines.append(f"  validation: {finding.validation_status.value}")
        lines.append("")

    counts = report.summary.findings_by_severity
    lines.append(
        "summary: "
        f"files={report.summary.files_scanned} "
        f"critical={counts.get(Severity.CRITICAL.value, 0)} "
        f"high={counts.get(Severity.HIGH.value, 0)} "
        f"medium={counts.get(Severity.MEDIUM.value, 0)} "
        f"low={counts.get(Severity.LOW.value, 0)} "
        f"info={counts.get(Severity.INFO.value, 0)}"
    )
    return "\n".join(lines) + "\n"
