from __future__ import annotations

from asta_cloud.analyzers.context import ScanContext
from asta_cloud.analyzers.taint import call_has_tainted_argument, iter_calls_with_taint
from asta_cloud.discovery.parse import iter_functions, qualified_name, source_line
from asta_cloud.models.enums import Confidence, Severity
from asta_cloud.models.finding import Finding
from asta_cloud.models.location import Location
from asta_cloud.rules.base import make_finding

_OS = "os"
_SYS = "system"
_POPEN = "popen"
_SINKS = {
    f"{_OS}.{_SYS}",
    f"{_OS}.{_POPEN}",
    "subprocess.Popen",
    "subprocess.call",
    "subprocess.run",
    "subprocess.check_output",
    "subprocess.check_call",
    _SYS,
    _POPEN,
    "Popen",
    "call",
    "run",
    "check_output",
    "check_call",
}


def _command_sink(name: str | None) -> bool:
    if not name:
        return False
    base = name.split(".")[-1]
    return name in _SINKS or base in _SINKS


class UserControlledCommandsRule:
    id = "ASTA-SEC-003"
    title = "Tools executing user-controlled commands"
    severity = Severity.HIGH

    def check(self, ctx: ScanContext) -> list[Finding]:
        findings: list[Finding] = []
        for module in ctx.modules:
            if module.tree is None:
                continue
            fns = {fn.name: fn for fn in iter_functions(module.tree)}
            for tool in ctx.inventory.tools:
                if tool.location.path != module.relative:
                    continue
                fn = fns.get(tool.name)
                if fn is None:
                    continue
                params = set(tool.param_names) | {
                    arg.arg for arg in fn.args.args if arg.arg != "self"
                }
                if not params:
                    continue
                for call, tainted in iter_calls_with_taint(fn, params):
                    name = qualified_name(call.func)
                    if not _command_sink(name):
                        continue
                    if not call_has_tainted_argument(call, tainted):
                        continue
                    findings.append(
                        make_finding(
                            rule_id=self.id,
                            title=self.title,
                            description=(
                                "A tool parameter is passed to a process or shell API, "
                                "including via local assignments or string formatting. "
                                "Model- or user-controlled command strings can become RCE."
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
                                "Do not interpolate tool arguments into a shell. Map the "
                                "parameter to a fixed operation, or pass a literal argv list "
                                "after strict validation."
                            ),
                            owasp=["LLM01:2025", "LLM08:2025"],
                            call_name=name,
                        )
                    )
        return findings
