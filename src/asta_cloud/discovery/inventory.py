from __future__ import annotations

import ast
from pathlib import Path

from asta_cloud.discovery.frameworks import (
    Framework,
    detect_module_framework,
    framework_from_call,
    framework_from_decorators,
    merge_framework,
)
from asta_cloud.discovery.mcp import (
    extract_mcp_prompts,
    extract_mcp_resources,
    extract_mcp_servers,
    extract_mcp_tools,
    module_uses_mcp,
)
from asta_cloud.discovery.parse import (
    ParsedModule,
    assignment_name,
    callee_names,
    const_str,
    decorator_base_names,
    decorator_qualified_names,
    function_param_names,
    iter_functions,
    qualified_name,
)
from asta_cloud.discovery.rag import extract_document_loaders, module_uses_rag
from asta_cloud.discovery.workflow import extract_agent_handoffs, extract_memory_stores
from asta_cloud.models.inventory import (
    AgentComponent,
    AgentHandoffComponent,
    DocumentLoaderComponent,
    Inventory,
    McpResourceComponent,
    McpServerComponent,
    MemoryStoreComponent,
    ParseErrorInfo,
    PromptComponent,
    ToolComponent,
)
from asta_cloud.models.location import Location
from asta_cloud.security.redact import redact_text

_PROMPT_NAMES = {"system_prompt", "instructions", "prompt", "system"}
_PROMPT_ASSIGN_NAMES = {"system_prompt", "instructions", "prompt", "SYSTEM_PROMPT"}
_ALLOWLIST_KEYWORDS = {
    "allowed_tools",
    "tool_choice",
    "permit",
    "allowed_tool_names",
    "tool_allowlist",
}
_AGENT_CALL_NAMES = {
    "agent",
    "chatagent",
    "assistant",
    "create_agent",
    "create_react_agent",
    "create_tool_calling_agent",
    "agentexecutor",
    "reactagent",
    "agentrunner",
    "runner",
    "from_tools",
}
_AGENT_INTERNAL_CALLEES = {
    "get_response",
    "_build_response_create_kwargs",
    "_get_response_via_chat",
    "_get_response_via_responses",
    "_stream_response_via_chat",
    "_stream_response_via_responses",
    "_fetch_responses_response",
    "_fetch_chat_response",
    "agentspandata",
}
_TOOL_CALL_NAMES = {
    "tool",
    "functiontool",
    "structuredtool",
    "function_tool",
    "queryenginetool",
}
_TOOL_DECORATORS = {"tool", "tools"}
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


def _is_prompt_name(name: str | None) -> bool:
    if not name:
        return False
    lowered = name.lower()
    return lowered in {n.lower() for n in _PROMPT_ASSIGN_NAMES} or lowered in _PROMPT_NAMES


def _list_name_ids(node: ast.AST | None) -> list[str]:
    if node is None:
        return []
    names: list[str] = []
    if isinstance(node, (ast.List, ast.Tuple, ast.Set)):
        for elt in node.elts:
            if isinstance(elt, ast.Name):
                names.append(elt.id)
            elif isinstance(elt, ast.Constant) and isinstance(elt.value, str):
                names.append(elt.value)
    elif isinstance(node, ast.Name):
        names.append(node.id)
    return names


def _extract_prompts(
    module: ParsedModule, module_framework: Framework | None
) -> list[PromptComponent]:
    if module.tree is None:
        return []
    prompts: list[PromptComponent] = []
    for node in ast.walk(module.tree):
        if isinstance(node, ast.Assign):
            for target in node.targets:
                name = assignment_name(target)
                if _is_prompt_name(name):
                    text = const_str(node.value) or ""
                    value = node.value
                    call_name = qualified_name(value) if isinstance(value, ast.Call) else None
                    fw = merge_framework(
                        module_framework,
                        framework_from_call(call_name),
                    )
                    prompts.append(
                        PromptComponent(
                            name=name,
                            location=_loc(module.relative, node),
                            kind="assign",
                            preview=_preview(text or name or "prompt"),
                            framework=fw,
                        )
                    )
        elif isinstance(node, ast.AnnAssign):
            name = assignment_name(node.target)
            if _is_prompt_name(name) and node.value is not None:
                text = const_str(node.value) or ""
                call_name = qualified_name(node.value) if isinstance(node.value, ast.Call) else None
                fw = merge_framework(module_framework, framework_from_call(call_name))
                prompts.append(
                    PromptComponent(
                        name=name,
                        location=_loc(module.relative, node),
                        kind="assign",
                        preview=_preview(text or name or "prompt"),
                        framework=fw,
                    )
                )
        elif isinstance(node, ast.Call):
            for keyword in node.keywords:
                if keyword.arg and keyword.arg.lower() in _PROMPT_NAMES:
                    text = const_str(keyword.value) or keyword.arg
                    fw = merge_framework(
                        module_framework,
                        framework_from_call(qualified_name(node.func)),
                    )
                    prompts.append(
                        PromptComponent(
                            name=keyword.arg,
                            location=_loc(module.relative, node),
                            kind="call_kwarg",
                            preview=_preview(text),
                            framework=fw,
                        )
                    )
    return prompts


def _is_tool_function(fn: ast.FunctionDef | ast.AsyncFunctionDef) -> tuple[bool, str]:
    decorators = decorator_base_names(fn)
    if any(name in _TOOL_DECORATORS for name in decorators):
        return True, "decorator"
    if fn.name.lower().endswith("_tool"):
        return True, "function"
    return False, "function"


def _extract_tools(module: ParsedModule, module_framework: Framework | None) -> list[ToolComponent]:
    if module.tree is None:
        return []
    tools: list[ToolComponent] = []

    for fn in iter_functions(module.tree):
        is_tool, kind = _is_tool_function(fn)
        if not is_tool:
            continue
        fw = merge_framework(
            module_framework,
            framework_from_decorators(
                decorator_base_names(fn),
                decorator_qualified_names(fn),
            ),
        )
        tools.append(
            ToolComponent(
                name=fn.name,
                location=_loc(module.relative, fn),
                kind="decorator" if kind == "decorator" else "function",
                param_names=function_param_names(fn),
                callee_names=callee_names(fn),
                framework=fw,
            )
        )

    for node in ast.walk(module.tree):
        if not isinstance(node, ast.Call):
            continue
        call_name = qualified_name(node.func)
        if not call_name:
            continue
        base = call_name.split(".")[-1].lower()
        if base not in _TOOL_CALL_NAMES:
            continue
        name_node = node.args[0] if node.args else None
        name = const_str(name_node)
        if name is None:
            for keyword in node.keywords:
                if keyword.arg in {"name", "func"}:
                    name = const_str(keyword.value) or (
                        keyword.value.id if isinstance(keyword.value, ast.Name) else None
                    )
        if not name:
            name = call_name
        fw = merge_framework(module_framework, framework_from_call(call_name))
        tools.append(
            ToolComponent(
                name=name,
                location=_loc(module.relative, node),
                kind="call",
                param_names=[],
                callee_names=[call_name],
                framework=fw,
            )
        )
    return tools


def _is_agent_construction_callee(base: str) -> bool:
    base_l = base.lower()
    if base_l in _AGENT_INTERNAL_CALLEES:
        return False
    if base.startswith("_"):
        return False
    if base_l in _AGENT_CALL_NAMES:
        return True
    return base == "Agent"


def is_agent_construction_call(call: ast.Call) -> bool:
    call_name = qualified_name(call.func) or ""
    base = call_name.split(".")[-1]
    if not _is_agent_construction_callee(base):
        return False
    if any(keyword.arg == "tools" for keyword in call.keywords):
        return True
    base_l = base.lower()
    if base_l in {"from_tools", "create_react_agent", "create_tool_calling_agent"}:
        if base_l == "from_tools":
            return len(call.args) >= 1
        return len(call.args) >= 2
    return False


def _extract_agents(
    module: ParsedModule, module_framework: Framework | None
) -> list[AgentComponent]:
    if module.tree is None:
        return []
    agents: list[AgentComponent] = []
    for node in ast.walk(module.tree):
        if not isinstance(node, ast.Call):
            continue
        call_name = qualified_name(node.func)
        if not call_name:
            continue
        base = call_name.split(".")[-1]
        if not is_agent_construction_call(node):
            continue

        tools_node = None
        prompt_names: list[str] = []
        allowlist = False
        for keyword in node.keywords:
            if keyword.arg == "tools":
                tools_node = keyword.value
            elif keyword.arg and keyword.arg.lower() in _PROMPT_NAMES:
                if isinstance(keyword.value, ast.Name):
                    prompt_names.append(keyword.value.id)
                else:
                    prompt_names.append(keyword.arg)
            elif keyword.arg and keyword.arg.lower() in _ALLOWLIST_KEYWORDS:
                allowlist = True

        if tools_node is None:
            base_l = base.lower()
            if base_l == "from_tools" and node.args:
                tools_node = node.args[0]
            elif base_l in {"create_react_agent", "create_tool_calling_agent"} and len(
                node.args
            ) >= 2:
                tools_node = node.args[1]

        parent_name = _enclosing_assign_name(module.tree, node)
        fw = merge_framework(module_framework, framework_from_call(call_name))

        agents.append(
            AgentComponent(
                name=parent_name or base,
                location=_loc(module.relative, node),
                tool_names=_list_name_ids(tools_node),
                prompt_names=prompt_names,
                allowlist_present=allowlist,
                framework=fw,
            )
        )
    return agents


def _enclosing_assign_name(tree: ast.AST, call: ast.Call) -> str | None:
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and node.value is call:
            if node.targets:
                return assignment_name(node.targets[0])
        if isinstance(node, ast.AnnAssign) and node.value is call:
            return assignment_name(node.target)
    return None


def build_inventory(root: Path, modules: list[ParsedModule]) -> Inventory:
    agents: list[AgentComponent] = []
    prompts: list[PromptComponent] = []
    tools: list[ToolComponent] = []
    mcp_servers: list[McpServerComponent] = []
    mcp_resources: list[McpResourceComponent] = []
    document_loaders: list[DocumentLoaderComponent] = []
    memory_stores: list[MemoryStoreComponent] = []
    agent_handoffs: list[AgentHandoffComponent] = []
    parse_errors: list[ParseErrorInfo] = []
    python_files: list[str] = []

    for module in modules:
        python_files.append(module.relative)
        if module.parse_error:
            parse_errors.append(
                ParseErrorInfo(path=module.relative, message=redact_text(module.parse_error))
            )
            continue
        module_fw = detect_module_framework(module.tree) if module.tree is not None else None
        if module.tree is not None and module_uses_mcp(module.tree):
            module_fw = merge_framework(module_fw, "mcp")
        if module.tree is not None and module_uses_rag(module.tree):
            module_fw = merge_framework(module_fw, "langchain")
        agents.extend(_extract_agents(module, module_fw))
        module_prompts = _extract_prompts(module, module_fw)
        module_tools = _extract_tools(module, module_fw)
        module_mcp_tools = extract_mcp_tools(module)
        module_mcp_prompts = extract_mcp_prompts(module)
        mcp_tool_keys = {(item.location.path, item.name) for item in module_mcp_tools}
        mcp_prompt_keys = {(item.location.path, item.name) for item in module_mcp_prompts}
        tools.extend(module_mcp_tools)
        tools.extend(
            item
            for item in module_tools
            if (item.location.path, item.name) not in mcp_tool_keys
        )
        prompts.extend(module_mcp_prompts)
        prompts.extend(
            item
            for item in module_prompts
            if (item.location.path, item.name) not in mcp_prompt_keys
        )
        mcp_servers.extend(extract_mcp_servers(module))
        mcp_resources.extend(extract_mcp_resources(module))
        document_loaders.extend(extract_document_loaders(module))
        memory_stores.extend(extract_memory_stores(module))
        agent_handoffs.extend(extract_agent_handoffs(module))

    return Inventory(
        target=str(root),
        python_files=python_files,
        agents=agents,
        prompts=prompts,
        tools=tools,
        mcp_servers=mcp_servers,
        mcp_resources=mcp_resources,
        document_loaders=document_loaders,
        memory_stores=memory_stores,
        agent_handoffs=agent_handoffs,
        parse_errors=parse_errors,
    )
