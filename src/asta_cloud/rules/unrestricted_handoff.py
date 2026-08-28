from __future__ import annotations

from asta_cloud.analyzers.context import ScanContext
from asta_cloud.discovery.parse import source_line
from asta_cloud.discovery.workflow import is_unrestricted_handoff
from asta_cloud.models.enums import Confidence, Severity
from asta_cloud.models.finding import Finding
from asta_cloud.rules.base import make_finding


class UnrestrictedHandoffRule:
    id = "ASTA-SEC-017"
    title = "Unrestricted multi-agent handoff"
    severity = Severity.MEDIUM

    def check(self, ctx: ScanContext) -> list[Finding]:
        findings: list[Finding] = []
        for handoff in ctx.inventory.agent_handoffs:
            if not is_unrestricted_handoff(handoff):
                continue
            module = next(
                (item for item in ctx.modules if item.relative == handoff.location.path),
                None,
            )
            snippet = (
                source_line(module.source, handoff.location.line)
                if module is not None
                else handoff.name or "handoff"
            )
            findings.append(
                make_finding(
                    rule_id=self.id,
                    title=self.title,
                    description=(
                        "A multi-agent handoff or delegation is configured without an "
                        "explicit target allowlist. Workflows may route to unintended agents."
                    ),
                    severity=self.severity,
                    confidence=Confidence.MEDIUM,
                    location=handoff.location,
                    snippet=snippet,
                    remediation=(
                        "Restrict handoffs to an explicit allowlist of destination agents. "
                        "Validate routing decisions before transfer."
                    ),
                    owasp=["LLM08:2025", "LLM01:2025"],
                    call_name=handoff.target_hint,
                )
            )
        return findings
