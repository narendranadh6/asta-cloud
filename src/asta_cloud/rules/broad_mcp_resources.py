from __future__ import annotations

from asta_cloud.analyzers.context import ScanContext
from asta_cloud.discovery.mcp import is_broad_mcp_resource_uri
from asta_cloud.discovery.parse import source_line
from asta_cloud.models.enums import Confidence, Severity
from asta_cloud.models.finding import Finding
from asta_cloud.models.location import Location
from asta_cloud.rules.base import make_finding


class BroadMcpResourcesRule:
    id = "ASTA-SEC-009"
    title = "Overly broad MCP resource URI templates"
    severity = Severity.MEDIUM

    def check(self, ctx: ScanContext) -> list[Finding]:
        findings: list[Finding] = []
        for resource in ctx.inventory.mcp_resources:
            if not is_broad_mcp_resource_uri(resource.uri_template):
                continue
            module = next(
                (item for item in ctx.modules if item.relative == resource.location.path),
                None,
            )
            snippet = (
                source_line(module.source, resource.location.line)
                if module is not None
                else resource.uri_template
            )
            findings.append(
                make_finding(
                    rule_id=self.id,
                    title=self.title,
                    description=(
                        "An MCP resource URI template exposes a parameterized or "
                        "unbounded filesystem path. Clients may use this to read "
                        "arbitrary files through the MCP server."
                    ),
                    severity=self.severity,
                    confidence=Confidence.HIGH,
                    location=Location(
                        path=resource.location.path,
                        line=resource.location.line,
                        end_line=resource.location.end_line,
                    ),
                    snippet=snippet,
                    remediation=(
                        "Constrain MCP resource URIs to explicit, reviewed paths. "
                        "Avoid {path} or ** templates unless paired with strict "
                        "server-side validation."
                    ),
                    owasp=["LLM08:2025"],
                    call_name=resource.uri_template,
                )
            )
        return findings
