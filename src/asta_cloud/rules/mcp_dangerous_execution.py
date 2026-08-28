from __future__ import annotations

from asta_cloud.analyzers.context import ScanContext
from asta_cloud.discovery.parse import source_line
from asta_cloud.models.enums import Confidence, Severity
from asta_cloud.models.finding import Finding
from asta_cloud.models.location import Location
from asta_cloud.rules.base import make_finding
from asta_cloud.rules.dangerous_shell import dangerous_calls_in, functions_by_name


class McpDangerousExecutionRule:
    id = "ASTA-SEC-011"
    title = "Dangerous execution in MCP tools"
    severity = Severity.HIGH

    def check(self, ctx: ScanContext) -> list[Finding]:
        findings: list[Finding] = []
        for module in ctx.modules:
            if module.tree is None:
                continue
            fns = functions_by_name(module.tree)
            for tool in ctx.inventory.tools:
                if tool.framework != "mcp" or tool.location.path != module.relative:
                    continue
                fn = fns.get(tool.name)
                if fn is None:
                    continue
                for call, name in dangerous_calls_in(fn, include_eval=True):
                    findings.append(
                        make_finding(
                            rule_id=self.id,
                            title=self.title,
                            description=(
                                "An MCP tool invokes a shell, a subprocess with "
                                "shell=True, or eval/exec. This grants MCP clients a "
                                "path to arbitrary command execution."
                            ),
                            severity=self.severity,
                            confidence=Confidence.HIGH,
                            location=Location(
                                path=module.relative,
                                line=call.lineno,
                                end_line=call.end_lineno,
                            ),
                            snippet=source_line(module.source, call.lineno),
                            remediation=(
                                "Remove shell execution from MCP tools. Use fixed "
                                "allowlists and pass arguments as a list with "
                                "shell=False."
                            ),
                            owasp=["LLM08:2025", "LLM01:2025"],
                            call_name=name,
                        )
                    )
        return findings
