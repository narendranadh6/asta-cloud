from __future__ import annotations

import ast

from asta_cloud.analyzers.context import ScanContext
from asta_cloud.discovery.parse import (
    const_str,
    iter_calls,
    iter_functions,
    qualified_name,
    source_line,
)
from asta_cloud.models.enums import Confidence, Severity
from asta_cloud.models.finding import Finding
from asta_cloud.models.location import Location
from asta_cloud.rules.base import make_finding

_SENSITIVE = (
    ".env",
    ".ssh",
    "id_rsa",
    "/etc/passwd",
    "/etc/shadow",
    "credentials",
    "secrets.json",
)
_READ_ATTRS = {"read_text", "read_bytes", "open"}


def _is_sensitive(value: str) -> bool:
    lowered = value.lower()
    return any(fragment in lowered for fragment in _SENSITIVE)


def _string_args_and_kwargs(call: ast.Call) -> list[str]:
    values: list[str] = []
    for arg in call.args:
        text = const_str(arg)
        if text:
            values.append(text)
    for keyword in call.keywords:
        text = const_str(keyword.value)
        if text:
            values.append(text)
    return values


def _path_literal_from_receiver(func: ast.AST) -> str | None:
    """Path('literal').read_text() → literal."""
    if not isinstance(func, ast.Attribute):
        return None
    if not isinstance(func.value, ast.Call):
        return None
    receiver = qualified_name(func.value.func)
    if receiver is None or receiver.split(".")[-1] != "Path":
        return None
    if func.value.args:
        return const_str(func.value.args[0])
    return None


class SensitiveFileAccessRule:
    id = "ASTA-SEC-006"
    title = "Sensitive file access through agent tools"
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
                for call in iter_calls(fn):
                    name = qualified_name(call.func) or ""
                    base = name.split(".")[-1]
                    candidates = _string_args_and_kwargs(call)
                    nested = _path_literal_from_receiver(call.func)
                    if nested:
                        candidates.append(nested)
                    if base not in {"open", *_READ_ATTRS} and name not in {"open", "builtins.open"}:
                        if not any(_is_sensitive(value) for value in candidates):
                            continue
                        if base not in _READ_ATTRS and name.split(".")[-1] != "Path":
                            continue
                    if not any(_is_sensitive(value) for value in candidates):
                        continue
                    findings.append(
                        make_finding(
                            rule_id=self.id,
                            title=self.title,
                            description=(
                                "An agent tool reads a sensitive path (credentials, SSH keys, "
                                "or system password files)."
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
                                "Do not give tools access to secret files. Read only from an "
                                "application-specific data directory with an allowlist."
                            ),
                            owasp=["LLM06:2025"],
                            call_name=name or "open",
                        )
                    )
        return findings
