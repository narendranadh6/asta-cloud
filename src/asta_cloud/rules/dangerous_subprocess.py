from __future__ import annotations

from asta_cloud.analyzers.context import ScanContext
from asta_cloud.discovery.parse import iter_functions, source_line
from asta_cloud.models.enums import Confidence, Severity
from asta_cloud.models.finding import Finding
from asta_cloud.models.location import Location
from asta_cloud.rules.base import make_finding
from asta_cloud.rules.dangerous_shell import dangerous_calls_in


class DangerousSubprocessRule:
    id = "ASTA-SEC-007"
    title = "Dangerous subprocess usage"
    severity = Severity.HIGH

    def check(self, ctx: ScanContext) -> list[Finding]:
        findings: list[Finding] = []
        for module in ctx.modules:
            if module.tree is None:
                continue
            for fn in iter_functions(module.tree):
                for call, name in dangerous_calls_in(fn, include_eval=False):
                    findings.append(
                        make_finding(
                            rule_id=self.id,
                            title=self.title,
                            description=(
                                "A function starts a process through the shell or equivalent "
                                "APIs. Command injection is likely if any input reaches this call."
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
                                "Use subprocess with a list of arguments and shell=False. "
                                "Avoid interpolating strings into a shell command."
                            ),
                            owasp=["A03:2021"],
                            call_name=name,
                        )
                    )
        return findings
