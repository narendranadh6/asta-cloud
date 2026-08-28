from __future__ import annotations

from asta_cloud.analyzers.context import ScanContext
from asta_cloud.discovery.parse import source_line
from asta_cloud.discovery.workflow import (
    function_has_permission_check,
    function_has_privileged_operation,
)
from asta_cloud.models.enums import Confidence, Severity
from asta_cloud.models.finding import Finding
from asta_cloud.models.location import Location
from asta_cloud.rules.base import make_finding
from asta_cloud.rules.dangerous_shell import functions_by_name


class ToolMissingPermissionRule:
    id = "ASTA-SEC-016"
    title = "Privileged agent tool missing permission check"
    severity = Severity.HIGH

    def check(self, ctx: ScanContext) -> list[Finding]:
        findings: list[Finding] = []
        for module in ctx.modules:
            if module.tree is None:
                continue
            fns = functions_by_name(module.tree)
            for tool in ctx.inventory.tools:
                if tool.location.path != module.relative:
                    continue
                fn = fns.get(tool.name)
                if fn is None:
                    continue
                if not function_has_privileged_operation(fn):
                    continue
                if function_has_permission_check(fn):
                    continue
                findings.append(
                    make_finding(
                        rule_id=self.id,
                        title=self.title,
                        description=(
                            "An agent tool performs a privileged operation such as "
                            "writing files or making network requests without an "
                            "authorization or permission check in the same function."
                        ),
                        severity=self.severity,
                        confidence=Confidence.MEDIUM,
                        location=Location(
                            path=module.relative,
                            line=fn.lineno,
                            end_line=fn.end_lineno,
                        ),
                        snippet=source_line(module.source, fn.lineno),
                        remediation=(
                            "Enforce permissions or scopes before privileged tool "
                            "actions. Reject calls when the caller lacks required roles."
                        ),
                        owasp=["LLM08:2025", "LLM06:2025"],
                        call_name=tool.name,
                    )
                )
        return findings
