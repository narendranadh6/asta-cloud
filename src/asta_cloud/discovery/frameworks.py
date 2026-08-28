from __future__ import annotations

import ast
from typing import Literal

Framework = Literal["langchain", "openai_agents", "llamaindex", "mcp", "generic"]

_MCP_IMPORT_PREFIXES = ("mcp", "fastmcp")

_LANGCHAIN_IMPORT_PREFIXES = ("langchain", "langchain_core", "langchain_community")
_OPENAI_AGENTS_IMPORT_PREFIXES = ("agents", "openai_agents")
_LLAMAINDEX_IMPORT_PREFIXES = ("llama_index", "llama_index.core")

_LANGCHAIN_CALL_SUFFIXES = {
    "structuredtool",
    "agentexecutor",
    "chatopenai",
    "chatprompttemplate",
    "prompttemplate",
    "create_react_agent",
    "create_tool_calling_agent",
    "humanmessage",
    "systemmessage",
    "bind_tools",
}

_OPENAI_AGENTS_CALL_SUFFIXES = {
    "function_tool",
    "agent",
    "runner",
    "handoff",
}

_LLAMAINDEX_CALL_SUFFIXES = {
    "functiontool",
    "queryenginetool",
    "reactagent",
    "agentrunner",
    "chatmessage",
    "from_defaults",
    "from_tools",
}

_LANGCHAIN_DECORATORS = {"tool", "structured_tool"}
_OPENAI_AGENTS_DECORATORS = {"function_tool"}
_LLAMAINDEX_DECORATORS = {"tool"}


def detect_module_framework(tree: ast.AST) -> Framework | None:
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                hint = _framework_from_module(alias.name)
                if hint:
                    return hint
        elif isinstance(node, ast.ImportFrom) and node.module:
            hint = _framework_from_module(node.module)
            if hint:
                return hint
    return None


def framework_from_call(call_name: str | None) -> Framework | None:
    if not call_name:
        return None
    lowered = call_name.lower()
    base = lowered.split(".")[-1]
    if base in _LANGCHAIN_CALL_SUFFIXES or "langchain" in lowered:
        return "langchain"
    if base in _OPENAI_AGENTS_CALL_SUFFIXES:
        return "openai_agents"
    if "openai.agents" in lowered or lowered.startswith("agents."):
        return "openai_agents"
    if base in _LLAMAINDEX_CALL_SUFFIXES or "llama_index" in lowered:
        return "llamaindex"
    if base == "fastmcp" or "mcp.server" in lowered or lowered.startswith("mcp."):
        return "mcp"
    return None


def framework_from_decorators(decorator_names: list[str], qualified: list[str]) -> Framework | None:
    lowered = {name.lower() for name in decorator_names}
    qual_lower = [name.lower() for name in qualified]
    if lowered & _OPENAI_AGENTS_DECORATORS or any("function_tool" in q for q in qual_lower):
        return "openai_agents"
    if any("llama_index" in q for q in qual_lower):
        return "llamaindex"
    if lowered & _LANGCHAIN_DECORATORS or any(
        q.endswith(".tool") or "langchain" in q for q in qual_lower
    ):
        return "langchain"
    if lowered & _LLAMAINDEX_DECORATORS and any("llama" in q for q in qual_lower):
        return "llamaindex"
    return None


def merge_framework(*hints: Framework | None) -> Framework | None:
    for hint in hints:
        if hint and hint != "generic":
            return hint
    return None


def _framework_from_module(module: str) -> Framework | None:
    for prefix in _MCP_IMPORT_PREFIXES:
        if module == prefix or module.startswith(f"{prefix}."):
            return "mcp"
    for prefix in _LANGCHAIN_IMPORT_PREFIXES:
        if module == prefix or module.startswith(f"{prefix}."):
            return "langchain"
    for prefix in _OPENAI_AGENTS_IMPORT_PREFIXES:
        if module == prefix or module.startswith(f"{prefix}."):
            return "openai_agents"
    for prefix in _LLAMAINDEX_IMPORT_PREFIXES:
        if module == prefix or module.startswith(f"{prefix}."):
            return "llamaindex"
    return None
