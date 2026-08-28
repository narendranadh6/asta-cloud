from __future__ import annotations

import ast

from asta_cloud.discovery.parse import (
    ParsedModule,
    assignment_name,
    const_str,
    qualified_name,
)
from asta_cloud.models.inventory import AgentHandoffComponent, MemoryStoreComponent
from asta_cloud.models.location import Location

_MEMORY_STORE_CALLS = {
    "conversationbuffermemory",
    "conversationsummarymemory",
    "conversationtokenbuffermemory",
    "conversationbufferwindowmemory",
    "redischatmessagehistory",
    "filechatmessagehistory",
    "postgreschatmessagehistory",
    "sqlitemessagehistory",
    "inmemorystore",
    "sqliteentitystore",
    "chatmessagehistory",
    "zepmemory",
    "mem0memory",
}

_SCOPE_KEYWORDS = {
    "session_id",
    "user_id",
    "tenant_id",
    "namespace",
    "partition",
    "owner_id",
    "conversation_id",
    "scoped",
    "per_user",
    "per_session",
    "memory_key",
}

_PERMISSION_KEYWORDS = {
    "permission",
    "permissions",
    "scope",
    "scopes",
    "allowed_roles",
    "role",
    "requires_auth",
    "authorize",
    "authorization",
    "acl",
    "rbac",
    "is_allowed",
    "check_permission",
}

_HANDOFF_CALLS = {"handoff", "transfer", "delegate", "route_to", "transfer_to_agent"}
_HANDOFF_ALLOWLIST_KEYWORDS = {
    "allowed_agents",
    "handoff_targets",
    "routes",
    "destinations",
    "handoffs",
}

_PRIVILEGED_OPEN_MODES = {"w", "wb", "a", "ab", "x", "xb"}


def _loc(relative: str, node: ast.AST) -> Location:
    lineno = getattr(node, "lineno", None)
    end = getattr(node, "end_lineno", None)
    return Location(path=relative, line=lineno, end_line=end)


def call_has_scope_hints(call: ast.Call) -> bool:
    for keyword in call.keywords:
        if keyword.arg and keyword.arg.lower() in _SCOPE_KEYWORDS:
            return True
    return False


def call_has_handoff_allowlist(call: ast.Call) -> bool:
    for keyword in call.keywords:
        if keyword.arg and keyword.arg.lower() in _HANDOFF_ALLOWLIST_KEYWORDS:
            return True
    return False


def function_has_permission_check(fn: ast.FunctionDef | ast.AsyncFunctionDef) -> bool:
    for node in ast.walk(fn):
        if isinstance(node, ast.Name):
            lowered = node.id.lower()
            if lowered in _PERMISSION_KEYWORDS or any(
                keyword in lowered for keyword in _PERMISSION_KEYWORDS
            ):
                return True
        if isinstance(node, ast.Attribute) and node.attr.lower() in _PERMISSION_KEYWORDS:
            return True
        if isinstance(node, ast.Call):
            call_name = (qualified_name(node.func) or "").lower()
            if any(keyword in call_name for keyword in _PERMISSION_KEYWORDS):
                return True
            for keyword in node.keywords:
                if keyword.arg and keyword.arg.lower() in _PERMISSION_KEYWORDS:
                    return True
    return False


def function_has_privileged_operation(fn: ast.FunctionDef | ast.AsyncFunctionDef) -> bool:
    for node in ast.walk(fn):
        if not isinstance(node, ast.Call):
            continue
        call_name = qualified_name(node.func) or ""
        base = call_name.split(".")[-1].lower()
        if base in {"remove", "unlink", "rmtree", "delete"}:
            return True
        if base in {"get", "post", "put", "patch", "delete", "request"} and (
            "requests" in call_name.lower() or "httpx" in call_name.lower()
        ):
            return True
        if base == "open" or call_name.endswith(".open"):
            mode = _open_mode(node)
            if mode in _PRIVILEGED_OPEN_MODES:
                return True
    return False


def extract_memory_stores(module: ParsedModule) -> list[MemoryStoreComponent]:
    if module.tree is None:
        return []
    stores: list[MemoryStoreComponent] = []
    for node in ast.walk(module.tree):
        if not isinstance(node, ast.Call):
            continue
        call_name = qualified_name(node.func) or ""
        base = call_name.split(".")[-1]
        if base.lower() not in _MEMORY_STORE_CALLS and "memory" not in base.lower():
            continue
        if "prompt" in base.lower():
            continue
        stores.append(
            MemoryStoreComponent(
                name=_enclosing_assign_name(module.tree, node) or base,
                location=_loc(module.relative, node),
                store_kind=base,
                scope_present=call_has_scope_hints(node),
            )
        )
    return stores


def extract_agent_handoffs(module: ParsedModule) -> list[AgentHandoffComponent]:
    if module.tree is None:
        return []
    handoffs: list[AgentHandoffComponent] = []
    for node in ast.walk(module.tree):
        if not isinstance(node, ast.Call):
            continue
        call_name = qualified_name(node.func) or ""
        base = call_name.split(".")[-1].lower()
        if base not in _HANDOFF_CALLS:
            continue
        target = _handoff_target(node)
        handoffs.append(
            AgentHandoffComponent(
                name=_enclosing_assign_name(module.tree, node) or base,
                location=_loc(module.relative, node),
                target_hint=target,
                allowlist_present=call_has_handoff_allowlist(node),
            )
        )
    return handoffs


def is_memory_store_call(call: ast.Call) -> bool:
    call_name = qualified_name(call.func) or ""
    base = call_name.split(".")[-1]
    lowered = base.lower()
    if "prompt" in lowered:
        return False
    return lowered in _MEMORY_STORE_CALLS or "memory" in lowered


def is_handoff_call(call: ast.Call) -> bool:
    call_name = qualified_name(call.func) or ""
    return call_name.split(".")[-1].lower() in _HANDOFF_CALLS


def agent_call_has_unscoped_memory(call: ast.Call) -> bool:
    if not any(keyword.arg == "memory" for keyword in call.keywords):
        return False
    return not call_has_scope_hints(call)


def is_unscoped_memory_store(store: MemoryStoreComponent) -> bool:
    return not store.scope_present


def is_unrestricted_handoff(handoff: AgentHandoffComponent) -> bool:
    return not handoff.allowlist_present


def _handoff_target(call: ast.Call) -> str | None:
    if call.args:
        if isinstance(call.args[0], ast.Name):
            return call.args[0].id
        return const_str(call.args[0])
    for keyword in call.keywords:
        if keyword.arg in {"agent", "to", "target", "destination"}:
            if isinstance(keyword.value, ast.Name):
                return keyword.value.id
            return const_str(keyword.value)
    return None


def _open_mode(call: ast.Call) -> str | None:
    if len(call.args) >= 2:
        mode = const_str(call.args[1])
        if mode:
            return mode
    for keyword in call.keywords:
        if keyword.arg == "mode":
            return const_str(keyword.value)
    return None


def _enclosing_assign_name(tree: ast.AST, call: ast.Call) -> str | None:
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and node.value is call:
            if node.targets:
                return assignment_name(node.targets[0])
        if isinstance(node, ast.AnnAssign) and node.value is call:
            return assignment_name(node.target)
    return None
