from __future__ import annotations

from asta_cloud.analyzers.context import ScanContext
from asta_cloud.discovery.mcp import module_has_network_transport
from asta_cloud.discovery.parse import source_line
from asta_cloud.models.enums import Confidence, Severity
from asta_cloud.models.finding import Finding
from asta_cloud.models.location import Location
from asta_cloud.rules.base import make_finding


class McpNetworkAuthRule:
    id = "ASTA-SEC-010"
    title = "MCP network transport without visible authentication"
    severity = Severity.HIGH

    def check(self, ctx: ScanContext) -> list[Finding]:
        findings: list[Finding] = []
        for server in ctx.inventory.mcp_servers:
            if server.transport not in {"sse", "http"}:
                continue
            if server.auth_present:
                continue
            module = next(
                (item for item in ctx.modules if item.relative == server.location.path),
                None,
            )
            if module is None or not module_has_network_transport(module.tree):
                continue
            findings.append(
                make_finding(
                    rule_id=self.id,
                    title=self.title,
                    description=(
                        "An MCP server exposes SSE or HTTP transport without any "
                        "visible authentication controls in the same module. Remote "
                        "clients may reach tools and resources without authorization."
                    ),
                    severity=self.severity,
                    confidence=Confidence.MEDIUM,
                    location=Location(
                        path=server.location.path,
                        line=server.location.line,
                        end_line=server.location.end_line,
                    ),
                    snippet=source_line(module.source, server.location.line),
                    remediation=(
                        "Bind MCP network transports to localhost or place them "
                        "behind authentication (API key, OAuth, mTLS). Never expose "
                        "0.0.0.0 without access controls."
                    ),
                    owasp=["LLM06:2025", "LLM08:2025"],
                )
            )
        return findings
