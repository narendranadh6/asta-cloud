from __future__ import annotations

import ast

from asta_cloud.analyzers.context import ScanContext
from asta_cloud.analyzers.taint import call_has_tainted_argument, iter_calls_with_taint
from asta_cloud.discovery.parse import (
    const_str,
    iter_functions,
    name_used_in,
    qualified_name,
    source_line,
)
from asta_cloud.models.enums import Confidence, Severity
from asta_cloud.models.finding import Finding
from asta_cloud.models.location import Location
from asta_cloud.rules.base import make_finding

_PATH_CTORS = {"Path", "pathlib.Path"}
_READ_ATTRS = {"read_text", "read_bytes", "open", "write_text", "write_bytes"}
_INFRASTRUCTURE_PATH_MARKERS = (
    "/sandbox/",
    "/sandboxes/",
    "snapshot_defaults",
    "snapshot_",
)


def is_infrastructure_module(relative: str) -> bool:
    normalized = relative.replace("\\", "/").lower()
    return any(marker in normalized for marker in _INFRASTRUCTURE_PATH_MARKERS)


def _broad_path_access_hit(
    call: ast.Call,
    *,
    module_relative: str,
    fn_name: str,
    tool_names: set[str],
) -> bool:
    if not (_is_path_home(call) or _is_root_path(call) or _is_os_walk_root(call)):
        return False
    if is_infrastructure_module(module_relative) and fn_name not in tool_names:
        return False
    return True


def _is_path_home(call: ast.Call) -> bool:
    name = qualified_name(call.func) or ""
    return name.endswith(".home") and name.split(".")[-2:][-2] in {
        "Path",
        "pathlib",
        "home",
    } or name in {"Path.home", "pathlib.Path.home"}


def _is_root_path(call: ast.Call) -> bool:
    name = qualified_name(call.func) or ""
    base = name.split(".")[-1]
    if base not in _PATH_CTORS and name not in _PATH_CTORS:
        return False
    if not call.args:
        return False
    value = const_str(call.args[0])
    return value in {"/", "~"}


def _is_os_walk_root(call: ast.Call) -> bool:
    name = qualified_name(call.func) or ""
    if name not in {"os.walk", "walk"} and not name.endswith(".walk"):
        return False
    if not call.args:
        return False
    return const_str(call.args[0]) == "/"


def _is_unbounded_glob(call: ast.Call) -> bool:
    name = qualified_name(call.func) or ""
    base = name.split(".")[-1]
    if base not in {"glob", "rglob", "iglob"}:
        return False
    for arg in call.args:
        text = const_str(arg)
        if text and "**" in text:
            return True
    return False


def _has_path_guard(fn: ast.AST, params: set[str]) -> bool:
    for node in ast.walk(fn):
        if isinstance(node, ast.Call):
            name = qualified_name(node.func) or ""
            if name.endswith("startswith") or name.endswith("is_relative_to"):
                if name_used_in(node, params):
                    return True
        if isinstance(node, ast.Name) and node.id.lower() in {
            "allowed",
            "allowlist",
            "allowed_roots",
            "allowed_prefixes",
        }:
            return True
    return False


def _reads_tainted_path(call: ast.Call, tainted: set[str]) -> bool:
    name = qualified_name(call.func) or ""
    base = name.split(".")[-1]
    if base == "open" or name in {"open", "builtins.open"}:
        return bool(call.args) and call_has_tainted_argument(call, tainted)
    if base in _READ_ATTRS:
        if isinstance(call.func, ast.Attribute) and call_has_tainted_argument(call, tainted):
            return True
        return bool(call.args) and call_has_tainted_argument(call, tainted)
    if base in _PATH_CTORS:
        return bool(call.args) and call_has_tainted_argument(call, tainted)
    return False


class BroadFilesystemRule:
    id = "ASTA-SEC-008"
    title = "Overly broad filesystem access"
    severity = Severity.MEDIUM

    def check(self, ctx: ScanContext) -> list[Finding]:
        findings: list[Finding] = []
        tool_names = {tool.name for tool in ctx.inventory.tools}
        for module in ctx.modules:
            if module.tree is None:
                continue
            for fn in iter_functions(module.tree):
                is_tool = fn.name in tool_names
                params = {arg.arg for arg in fn.args.args if arg.arg != "self"}
                guarded = _has_path_guard(fn, params) if is_tool and params else True
                for call, tainted in iter_calls_with_taint(fn, params if is_tool else set()):
                    hit = False
                    if _broad_path_access_hit(
                        call,
                        module_relative=module.relative,
                        fn_name=fn.name,
                        tool_names=tool_names,
                    ):
                        hit = True
                    elif _is_unbounded_glob(call):
                        hit = True
                    elif is_tool and params and not guarded and _reads_tainted_path(call, tainted):
                        hit = True
                    if not hit:
                        continue
                    findings.append(
                        make_finding(
                            rule_id=self.id,
                            title=self.title,
                            description=(
                                "Code walks the filesystem from a root path, home directory, "
                                "or an unguarded tool argument. Agent tools should be confined "
                                "to a narrow directory."
                            ),
                            severity=self.severity,
                            confidence=Confidence.MEDIUM,
                            location=Location(
                                path=module.relative,
                                line=call.lineno,
                                end_line=call.end_lineno,
                            ),
                            snippet=source_line(module.source, call.lineno),
                            remediation=(
                                "Restrict file access to an application data directory. "
                                "Reject paths that are not relative to that root."
                            ),
                            owasp=["LLM08:2025"],
                            call_name=qualified_name(call.func),
                        )
                    )
        return findings
