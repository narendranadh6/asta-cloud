from asta_cloud.analyzers.context import ScanContext
from asta_cloud.models.enums import Confidence, Severity
from asta_cloud.models.finding import Finding
from asta_cloud.rules.base import make_finding


class MissingAllowlistRule:
    id = "ASTA-SEC-005"
    title = "Missing tool allowlists"
    severity = Severity.MEDIUM

    def check(self, ctx: ScanContext) -> list[Finding]:
        findings: list[Finding] = []
        for agent in ctx.inventory.agents:
            if not agent.tool_names or agent.allowlist_present:
                continue
            findings.append(
                make_finding(
                    rule_id=self.id,
                    title=self.title,
                    description=(
                        "An agent is constructed with tools but no allowlist, tool_choice, "
                        "or permit constraint. The model may invoke every attached tool."
                    ),
                    severity=self.severity,
                    confidence=Confidence.MEDIUM,
                    location=agent.location,
                    snippet=f"agent {agent.name or 'Agent'} tools={agent.tool_names}",
                    remediation=(
                        "Pass an explicit allowlist (for example allowed_tools or tool_choice) "
                        "so only intended tools can be called."
                    ),
                    owasp=["LLM08:2025"],
                )
            )
        return findings
