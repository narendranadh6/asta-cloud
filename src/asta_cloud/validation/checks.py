from __future__ import annotations

import ast
from collections.abc import Callable

from asta_cloud.analyzers.taint import call_has_tainted_argument, iter_calls_with_taint
from asta_cloud.discovery.inventory import is_agent_construction_call
from asta_cloud.discovery.mcp import is_broad_mcp_resource_uri, module_has_network_transport
from asta_cloud.discovery.parse import (
    const_str,
    iter_functions,
    qualified_name,
)
from asta_cloud.discovery.rag import (
    is_broad_loader_call,
    is_risky_rag_prompt_template,
    is_web_loader,
    iter_rag_prompt_templates,
    module_has_retriever,
    web_loader_has_tainted_target,
)
from asta_cloud.discovery.workflow import (
    agent_call_has_unscoped_memory,
    call_has_handoff_allowlist,
    call_has_scope_hints,
    function_has_permission_check,
    function_has_privileged_operation,
    is_handoff_call,
    is_memory_store_call,
)
from asta_cloud.rules.dangerous_shell import dangerous_calls_in, is_dangerous_shell_call
from asta_cloud.rules.secrets import _secret_pairs
from asta_cloud.rules.user_controlled_commands import _command_sink
from asta_cloud.validation.helpers import calls_on_line, nodes_on_line

_PHRASES = (
    "use any tool",
    "all tools",
    "unrestricted",
    "do not ask for confirmation",
    "don't ask for confirmation",
    "ignore safety",
)

_SENSITIVE = (
    ".env",
    ".ssh",
    "id_rsa",
    "/etc/passwd",
    "/etc/shadow",
    "credentials",
    "secrets.json",
)

_ALLOWLIST_KEYWORDS = {
    "allowed_tools",
    "tool_choice",
    "permit",
    "allowed_tool_names",
    "tool_allowlist",
}
_PROMPT_NAMES = {"system_prompt", "instructions", "prompt", "system"}


def check_secrets(module_tree: ast.AST, line: int | None) -> bool:
    for node in nodes_on_line(module_tree, line):
        for name, value, _target in _secret_pairs(node):
            if name and value:
                return True
    return False


def check_dangerous_shell_tool(module_tree: ast.AST, line: int | None) -> bool:
    if line is None:
        return False
    for call in calls_on_line(module_tree, line):
        if is_dangerous_shell_call(call, include_eval=True):
            return True
    for fn in iter_functions(module_tree):
        for call, _name in dangerous_calls_in(fn, include_eval=True):
            if call.lineno == line:
                return True
    return False


def check_user_controlled_commands(module_tree: ast.AST, line: int | None) -> bool:
    for fn in iter_functions(module_tree):
        params = {arg.arg for arg in fn.args.args if arg.arg != "self"}
        if not params:
            continue
        for call, tainted in iter_calls_with_taint(fn, params):
            if call.lineno != line:
                continue
            name = qualified_name(call.func)
            if _command_sink(name) and call_has_tainted_argument(call, tainted):
                return True
    return False


def check_unrestricted_prompt(module_tree: ast.AST, line: int | None) -> bool:
    for node in nodes_on_line(module_tree, line):
        text = None
        if isinstance(node, ast.Assign):
            text = const_str(node.value)
        elif isinstance(node, ast.AnnAssign) and node.value is not None:
            text = const_str(node.value)
        elif isinstance(node, ast.Call):
            for keyword in node.keywords:
                if keyword.arg and keyword.arg.lower() in _PROMPT_NAMES:
                    text = const_str(keyword.value) or keyword.arg
        if text and any(phrase in text.lower() for phrase in _PHRASES):
            return True
    return False


def check_missing_allowlist(module_tree: ast.AST, line: int | None) -> bool:
    for node in nodes_on_line(module_tree, line):
        if isinstance(node, ast.Call) and is_agent_construction_call(node):
            allowlist = any(
                kw.arg is not None and kw.arg.lower() in _ALLOWLIST_KEYWORDS for kw in node.keywords
            )
            if not allowlist:
                return True
    return False


def check_sensitive_file_access(module_tree: ast.AST, line: int | None) -> bool:
    for call in calls_on_line(module_tree, line):
        name = qualified_name(call.func) or ""
        base = name.split(".")[-1]
        literals: list[str] = []
        for arg in call.args:
            text = const_str(arg)
            if text:
                literals.append(text)
        for keyword in call.keywords:
            text = const_str(keyword.value)
            if text:
                literals.append(text)
        if base in {"open", "read_text", "read_bytes"} or name in {"open", "builtins.open"}:
            if any(fragment in value.lower() for value in literals for fragment in _SENSITIVE):
                return True
    return False


def check_dangerous_subprocess(module_tree: ast.AST, line: int | None) -> bool:
    for fn in iter_functions(module_tree):
        for call, _name in dangerous_calls_in(fn, include_eval=False):
            if call.lineno == line:
                return True
    return any(
        is_dangerous_shell_call(call, include_eval=False)
        for call in calls_on_line(module_tree, line)
    )


def check_broad_filesystem(module_tree: ast.AST, line: int | None) -> bool:
    from asta_cloud.rules.broad_filesystem import (
        _is_os_walk_root,
        _is_path_home,
        _is_root_path,
        _is_unbounded_glob,
        _reads_tainted_path,
    )

    for fn in iter_functions(module_tree):
        params = {arg.arg for arg in fn.args.args if arg.arg != "self"}
        for call, tainted in iter_calls_with_taint(fn, params):
            if call.lineno != line:
                continue
            if (
                _is_path_home(call)
                or _is_root_path(call)
                or _is_os_walk_root(call)
                or _is_unbounded_glob(call)
                or (params and _reads_tainted_path(call, tainted))
            ):
                return True
    for call in calls_on_line(module_tree, line):
        if _is_path_home(call) or _is_root_path(call) or _is_os_walk_root(call):
            return True
    return False


def check_broad_mcp_resource(module_tree: ast.AST, line: int | None) -> bool:
    for fn in iter_functions(module_tree):
        for decorator in fn.decorator_list:
            if line is not None and getattr(decorator, "lineno", None) != line:
                continue
            target = decorator.func if isinstance(decorator, ast.Call) else decorator
            qualified = qualified_name(target) or ""
            if qualified.split(".")[-1].lower() != "resource":
                continue
            if isinstance(decorator, ast.Call) and decorator.args:
                uri = const_str(decorator.args[0])
                if uri and is_broad_mcp_resource_uri(uri):
                    return True
    return False


def check_mcp_network_auth(module_tree: ast.AST, line: int | None) -> bool:
    from asta_cloud.discovery.mcp import module_has_auth_hint

    if not module_has_network_transport(module_tree) or module_has_auth_hint(module_tree):
        return False
    for node in nodes_on_line(module_tree, line):
        if isinstance(node, ast.Call):
            call_name = qualified_name(node.func) or ""
            if call_name.split(".")[-1] in {"FastMCP", "Server"}:
                return True
    return False


def check_mcp_dangerous_execution(module_tree: ast.AST, line: int | None) -> bool:
    return check_dangerous_shell_tool(module_tree, line)


def check_broad_document_loader(module_tree: ast.AST, line: int | None) -> bool:
    for node in nodes_on_line(module_tree, line):
        if isinstance(node, ast.Call) and is_broad_loader_call(node):
            return True
    return False


def check_rag_user_url_loader(module_tree: ast.AST, line: int | None) -> bool:
    for fn in iter_functions(module_tree):
        params = {arg.arg for arg in fn.args.args if arg.arg != "self"}
        if not params:
            continue
        for call, tainted in iter_calls_with_taint(fn, params):
            if call.lineno != line:
                continue
            call_name = qualified_name(call.func) or ""
            if is_web_loader(call_name.split(".")[-1]) and web_loader_has_tainted_target(
                call, tainted
            ):
                return True
    return False


def check_rag_prompt_injection(module_tree: ast.AST, line: int | None) -> bool:
    if not module_has_retriever(module_tree):
        return False
    for node, template in iter_rag_prompt_templates(module_tree):
        if getattr(node, "lineno", None) != line:
            continue
        if is_risky_rag_prompt_template(template):
            return True
    return False


def check_unscoped_agent_memory(module_tree: ast.AST, line: int | None) -> bool:
    for node in nodes_on_line(module_tree, line):
        if isinstance(node, ast.Call) and is_memory_store_call(node):
            return not call_has_scope_hints(node)
    for node in nodes_on_line(module_tree, line):
        if isinstance(node, ast.Call) and agent_call_has_unscoped_memory(node):
            return True
    return False


def check_tool_missing_permission(module_tree: ast.AST, line: int | None) -> bool:
    for fn in iter_functions(module_tree):
        if fn.lineno != line:
            continue
        if function_has_privileged_operation(fn) and not function_has_permission_check(fn):
            return True
    return False


def check_unrestricted_handoff(module_tree: ast.AST, line: int | None) -> bool:
    for node in nodes_on_line(module_tree, line):
        if isinstance(node, ast.Call) and is_handoff_call(node):
            return not call_has_handoff_allowlist(node)
    return False


RULE_CHECKERS: dict[str, Callable[[ast.AST, int | None], bool]] = {
    "ASTA-SEC-001": check_secrets,
    "ASTA-SEC-002": check_dangerous_shell_tool,
    "ASTA-SEC-003": check_user_controlled_commands,
    "ASTA-SEC-004": check_unrestricted_prompt,
    "ASTA-SEC-005": check_missing_allowlist,
    "ASTA-SEC-006": check_sensitive_file_access,
    "ASTA-SEC-007": check_dangerous_subprocess,
    "ASTA-SEC-008": check_broad_filesystem,
    "ASTA-SEC-009": check_broad_mcp_resource,
    "ASTA-SEC-010": check_mcp_network_auth,
    "ASTA-SEC-011": check_mcp_dangerous_execution,
    "ASTA-SEC-012": check_broad_document_loader,
    "ASTA-SEC-013": check_rag_user_url_loader,
    "ASTA-SEC-014": check_rag_prompt_injection,
    "ASTA-SEC-015": check_unscoped_agent_memory,
    "ASTA-SEC-016": check_tool_missing_permission,
    "ASTA-SEC-017": check_unrestricted_handoff,
}
