from __future__ import annotations

import ast
from typing import Literal

from asta_cloud.discovery.parse import (
    ParsedModule,
    const_str,
    decorator_base_names,
    decorator_qualified_names,
    function_param_names,
    iter_functions,
    qualified_name,
)
from asta_cloud.models.inventory import (
    McpResourceComponent,
    McpServerComponent,
    PromptComponent,
    ToolComponent,
)
from asta_cloud.models.location import Location
from asta_cloud.security.redact import redact_text

McpSdk = Literal["fastmcp", "official", "unknown"]
McpTransport = Literal["stdio", "sse", "http", "unknown"]

_MCP_IMPORT_PREFIXES = ("mcp", "fastmcp")
_FASTMCP_CALLS = {"fastmcp"}
_SERVER_CALLS = {"server"}
_MCP_TOOL_DECORATORS = {"tool"}
_MCP_RESOURCE_DECORATORS = {"resource"}
_MCP_PROMPT_DECORATORS = {"prompt"}
_AUTH_KEYWORDS = {
    "auth",
    "authenticate",
    "authorization",
    "api_key",
    "apikey",
    "bearer",
    "token",
    "oauth",
    "jwt",
}
_PREVIEW_LIMIT = 240


def _loc(relative: str, node: ast.AST) -> Location:
    lineno = getattr(node, "lineno", None)
    end = getattr(node, "end_lineno", None)
    return Location(path=relative, line=lineno, end_line=end)


def _preview(text: str) -> str:
    cleaned = redact_text(text).replace("\n", " ")
    if len(cleaned) > _PREVIEW_LIMIT:
        return cleaned[:_PREVIEW_LIMIT] + "…"
    return cleaned


def module_uses_mcp(tree: ast.AST | None) -> bool:
    if tree is None:
        return False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if _is_mcp_module(alias.name):
                    return True
        elif isinstance(node, ast.ImportFrom) and node.module and _is_mcp_module(node.module):
            return True
    return False


def module_has_auth_hint(tree: ast.AST | None) -> bool:
    if tree is None:
        return False
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            lowered = node.value.lower()
            if any(keyword in lowered for keyword in _AUTH_KEYWORDS):
                return True
        elif isinstance(node, ast.Name):
            if node.id.lower() in _AUTH_KEYWORDS:
                return True
        elif isinstance(node, ast.Attribute):
            if node.attr.lower() in _AUTH_KEYWORDS:
                return True
        elif isinstance(node, ast.Call):
            call_name = qualified_name(node.func) or ""
            if any(keyword in call_name.lower() for keyword in _AUTH_KEYWORDS):
                return True
            for keyword in node.keywords:
                if keyword.arg and keyword.arg.lower() in _AUTH_KEYWORDS:
                    return True
    return False


def detect_transport(tree: ast.AST | None) -> McpTransport:
    if tree is None:
        return "unknown"
    transport: McpTransport = "unknown"
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        call_name = (qualified_name(node.func) or "").lower()
        if "stdio_server" in call_name:
            return "stdio"
        if "sseservertransport" in call_name.replace("_", "") or "sse_server" in call_name:
            transport = "sse"
        if "uvicorn.run" in call_name or call_name.endswith("uvicorn.run"):
            transport = "http"
        if _call_has_public_bind(node):
            transport = "http"
        if _call_is_mcp_instance_run(node):
            return "stdio"
    if transport != "unknown":
        return transport
    for node in ast.walk(tree):
        if isinstance(node, ast.Attribute) and node.attr.lower() in {"sse", "streamable_http"}:
            return "sse"
    return "unknown"


def extract_mcp_servers(module: ParsedModule) -> list[McpServerComponent]:
    if module.tree is None or not module_uses_mcp(module.tree):
        return []
    transport = detect_transport(module.tree)
    auth_present = module_has_auth_hint(module.tree)
    servers: list[McpServerComponent] = []

    for node in ast.walk(module.tree):
        if not isinstance(node, ast.Call):
            continue
        call_name = qualified_name(node.func)
        if not call_name:
            continue
        base = call_name.split(".")[-1]
        sdk: McpSdk = "unknown"
        if base == "FastMCP":
            sdk = "fastmcp"
        elif base == "Server":
            sdk = "official"
        else:
            continue

        name = const_str(node.args[0]) if node.args else None
        if name is None:
            for keyword in node.keywords:
                if keyword.arg == "name":
                    name = const_str(keyword.value)
        servers.append(
            McpServerComponent(
                name=name,
                location=_loc(module.relative, node),
                sdk=sdk,
                transport=transport,
                auth_present=auth_present,
            )
        )
    return servers


def extract_mcp_resources(module: ParsedModule) -> list[McpResourceComponent]:
    if module.tree is None or not module_uses_mcp(module.tree):
        return []
    resources: list[McpResourceComponent] = []
    for fn in iter_functions(module.tree):
        for decorator in fn.decorator_list:
            uri, is_resource = _resource_uri_from_decorator(decorator)
            if not is_resource or uri is None:
                continue
            resources.append(
                McpResourceComponent(
                    name=fn.name,
                    location=_loc(module.relative, decorator),
                    uri_template=uri,
                )
            )
    return resources


def extract_mcp_tools(module: ParsedModule) -> list[ToolComponent]:
    if module.tree is None or not module_uses_mcp(module.tree):
        return []
    tools: list[ToolComponent] = []
    for fn in iter_functions(module.tree):
        if not _is_mcp_tool_function(fn):
            continue
        tools.append(
            ToolComponent(
                name=fn.name,
                location=_loc(module.relative, fn),
                kind="decorator",
                param_names=function_param_names(fn),
                callee_names=[],
                framework="mcp",
            )
        )
    return tools


def extract_mcp_prompts(module: ParsedModule) -> list[PromptComponent]:
    if module.tree is None or not module_uses_mcp(module.tree):
        return []
    prompts: list[PromptComponent] = []
    for fn in iter_functions(module.tree):
        if not any(_is_mcp_prompt_decorator(decorator) for decorator in fn.decorator_list):
            continue
        prompts.append(
            PromptComponent(
                name=fn.name,
                location=_loc(module.relative, fn),
                kind="constant",
                preview=_preview(fn.name),
                framework="mcp",
            )
        )
    return prompts


def is_broad_mcp_resource_uri(uri: str) -> bool:
    lowered = uri.lower()
    if any(token in uri for token in ("{path}", "{file}", "{filepath}", "{filename}")):
        return True
    if "**" in uri:
        return True
    if lowered.startswith("file://") and ("/" in uri[7:] or "{" in uri):
        return True
    if uri in {"/", "/*", "file:///", "files://"}:
        return True
    return False


def module_has_network_transport(tree: ast.AST | None) -> bool:
    transport = detect_transport(tree)
    return transport in {"sse", "http"}


def _is_mcp_module(module: str) -> bool:
    return any(
        module == prefix or module.startswith(f"{prefix}.")
        for prefix in _MCP_IMPORT_PREFIXES
    )


def _call_is_mcp_instance_run(node: ast.Call) -> bool:
    func = node.func
    if not isinstance(func, ast.Attribute) or func.attr != "run":
        return False
    if isinstance(func.value, ast.Name):
        lowered = func.value.id.lower()
        return lowered == "mcp" or lowered.endswith("_mcp")
    return False


def _call_has_public_bind(node: ast.Call) -> bool:
    for keyword in node.keywords:
        if keyword.arg != "host":
            continue
        value = const_str(keyword.value)
        if value == "0.0.0.0":
            return True
        if isinstance(keyword.value, ast.Constant) and keyword.value.value == "0.0.0.0":
            return True
    return False


def _resource_uri_from_decorator(decorator: ast.expr) -> tuple[str | None, bool]:
    target = decorator.func if isinstance(decorator, ast.Call) else decorator
    qualified = qualified_name(target) or ""
    base = qualified.split(".")[-1].lower()
    if base not in _MCP_RESOURCE_DECORATORS:
        return None, False
    if isinstance(decorator, ast.Call) and decorator.args:
        return const_str(decorator.args[0]), True
    return None, True


def _is_mcp_tool_function(fn: ast.FunctionDef | ast.AsyncFunctionDef) -> bool:
    decorators = decorator_base_names(fn)
    qualified = decorator_qualified_names(fn)
    if any(name in _MCP_TOOL_DECORATORS for name in decorators):
        return True
    return any(q.endswith(".tool") or q == "tool" for q in qualified)


def _is_mcp_prompt_decorator(decorator: ast.expr) -> bool:
    target = decorator.func if isinstance(decorator, ast.Call) else decorator
    qualified = qualified_name(target) or ""
    return qualified.split(".")[-1].lower() in _MCP_PROMPT_DECORATORS
