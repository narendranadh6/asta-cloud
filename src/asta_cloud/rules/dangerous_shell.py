from __future__ import annotations

import ast

from asta_cloud.analyzers.context import ScanContext
from asta_cloud.discovery.parse import (
    is_shell_true,
    iter_calls,
    iter_functions,
    qualified_name,
    source_line,
)
from asta_cloud.models.enums import Confidence, Severity
from asta_cloud.models.finding import Finding
from asta_cloud.models.location import Location
from asta_cloud.rules.base import make_finding

_EVAL_EXEC = {"eval", "exec"}
_OS = "os"
_SYS = "system"
_POPEN = "popen"
_ALWAYS_SHELL = {f"{_OS}.{_SYS}", f"{_OS}.{_POPEN}", _SYS, _POPEN}
_SUBPROCESS_NAMES = {
    "subprocess.Popen",
    "subprocess.call",
    "subprocess.run",
    "subprocess.check_output",
    "subprocess.check_call",
    "Popen",
    "call",
    "run",
    "check_output",
    "check_call",
}


def is_dangerous_shell_call(call: ast.Call, *, include_eval: bool) -> str | None:
    name = qualified_name(call.func)
    if not name:
        return None
    base = name.split(".")[-1]
    if include_eval and base in _EVAL_EXEC:
        return name
    if name in _ALWAYS_SHELL or (base in {_SYS, _POPEN} and "Path" not in name):
        return name
    if name in _SUBPROCESS_NAMES or base in _SUBPROCESS_NAMES:
        if is_shell_true(call):
            return name
    return None


def dangerous_calls_in(node: ast.AST, *, include_eval: bool) -> list[tuple[ast.Call, str]]:
    found: list[tuple[ast.Call, str]] = []
    for call in iter_calls(node):
        name = is_dangerous_shell_call(call, include_eval=include_eval)
        if name:
            found.append((call, name))
    return found


def functions_by_name(tree: ast.AST) -> dict[str, ast.FunctionDef | ast.AsyncFunctionDef]:
    return {fn.name: fn for fn in iter_functions(tree)}


class DangerousShellInToolsRule:
    id = "ASTA-SEC-002"
    title = "Agent tools containing dangerous shell execution"
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
                for call, name in dangerous_calls_in(fn, include_eval=True):
                    findings.append(
                        make_finding(
                            rule_id=self.id,
                            title=self.title,
                            description=(
                                "An agent tool invokes a shell, a subprocess with shell=True, "
                                "or eval/exec. This grants the model a path to arbitrary "
                                "command execution."
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
                                "Remove shell execution from tools. If a command must run, "
                                "use a fixed allowlist of binaries and pass arguments as a "
                                "list with shell=False."
                            ),
                            owasp=["LLM08:2025"],
                            call_name=name,
                        )
                    )
        return findings
