from __future__ import annotations

import ast
import re
from typing import Literal

from asta_cloud.discovery.parse import (
    ParsedModule,
    assignment_name,
    const_str,
    qualified_name,
)
from asta_cloud.models.inventory import DocumentLoaderComponent
from asta_cloud.models.location import Location

RagFramework = Literal["langchain", "llamaindex", "generic"]

_RAG_IMPORT_MARKERS = (
    "document_loaders",
    "document_loaders.",
    "llama_index.core.readers",
    "llama_index.readers",
    "vectorstores",
    "vector_stores",
    "retrievers",
    "haystack",
)

_LANGCHAIN_LOADERS = {
    "directoryloader",
    "textloader",
    "pypdfloader",
    "unstructuredfileloader",
    "webbaseloader",
    "recursiveurlloader",
    "asynchtmloader",
    "playwrighturlloader",
    "s3fileloader",
    "bshtmloader",
    "csvloader",
    "jsonloader",
    "pythonloader",
}

_LLAMAINDEX_LOADERS = {
    "simpledirectoryreader",
    "pdfreader",
    "beautifulsoupwebreader",
    "simplewebpagereader",
    "downloadloader",
    "filereader",
}

_WEB_LOADERS = {
    "webbaseloader",
    "recursiveurlloader",
    "asynchtmloader",
    "playwrighturlloader",
    "beautifulsoupwebreader",
    "simplewebpagereader",
}

_RAG_RETRIEVER_CALLS = {
    "as_retriever",
    "from_documents",
    "vectorstoreindex",
    "create_retrieval_chain",
    "retrievalqa",
    "queryengine",
    "from_tool",
    "as_query_engine",
}

_PATH_KWARGS = {"path", "directory", "dir_path", "file_path", "filepath", "folder"}
_URL_KWARGS = {"url", "urls", "web_path", "link", "base_url"}

_PROMPT_CONTEXT_VARS = {"context", "documents", "summaries", "source_documents", "doc_content"}
_QUERY_VAR_RE = re.compile(r"\{(query|question|user_input|input)\}")


def _loc(relative: str, node: ast.AST) -> Location:
    lineno = getattr(node, "lineno", None)
    end = getattr(node, "end_lineno", None)
    return Location(path=relative, line=lineno, end_line=end)


def module_uses_rag(tree: ast.AST | None) -> bool:
    if tree is None:
        return False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if _is_rag_module(alias.name):
                    return True
        elif isinstance(node, ast.ImportFrom) and node.module and _is_rag_module(node.module):
            return True
        if isinstance(node, ast.Call):
            call_name = qualified_name(node.func) or ""
            base = call_name.split(".")[-1].lower()
            if base in _LANGCHAIN_LOADERS | _LLAMAINDEX_LOADERS | _RAG_RETRIEVER_CALLS:
                return True
    return False


def module_has_retriever(tree: ast.AST | None) -> bool:
    if tree is None:
        return False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        call_name = qualified_name(node.func) or ""
        base = call_name.split(".")[-1].lower()
        lowered = call_name.lower()
        if base in _RAG_RETRIEVER_CALLS:
            return True
        if "retrievalqa" in lowered or "vectorstoreindex" in lowered:
            return True
        if base == "from_chain_type" and "retrieval" in lowered:
            return True
    return False


def is_web_loader(loader_kind: str) -> bool:
    return loader_kind.split(".")[-1].lower() in _WEB_LOADERS


def is_broad_loader_path(path: str | None) -> bool:
    if path is None:
        return False
    if path in {"/", ".", "~", "**", "/*"}:
        return True
    if "**" in path:
        return True
    if "{" in path and "}" in path:
        return True
    return path.startswith("file://") and ("/" in path[7:] or "{" in path)


def is_broad_loader_call(call: ast.Call) -> bool:
    call_name = qualified_name(call.func) or ""
    base = call_name.split(".")[-1]
    if base.lower() not in _LANGCHAIN_LOADERS | _LLAMAINDEX_LOADERS:
        return False
    literal = _loader_literal_path(call)
    if literal is not None and is_broad_loader_path(literal):
        return True
    for arg in call.args:
        if _is_root_path_call(arg) or _is_path_home_call(arg):
            return True
    for keyword in call.keywords:
        if keyword.arg in _PATH_KWARGS and keyword.value is not None:
            if _is_root_path_call(keyword.value) or _is_path_home_call(keyword.value):
                return True
            text = const_str(keyword.value)
            if text is not None and is_broad_loader_path(text):
                return True
    return False


def is_risky_rag_prompt_template(text: str) -> bool:
    if not _QUERY_VAR_RE.search(text):
        return False
    if any(f"{{{name}}}" in text for name in _PROMPT_CONTEXT_VARS):
        return False
    lowered = text.lower()
    if "context" in lowered and "{" in text:
        return False
    return True


def loader_framework(call_name: str) -> RagFramework:
    base = call_name.split(".")[-1].lower()
    if base in _LLAMAINDEX_LOADERS or "llama_index" in call_name.lower():
        return "llamaindex"
    if base in _LANGCHAIN_LOADERS or "langchain" in call_name.lower():
        return "langchain"
    return "generic"


def extract_document_loaders(module: ParsedModule) -> list[DocumentLoaderComponent]:
    if module.tree is None:
        return []
    loaders: list[DocumentLoaderComponent] = []
    for node in ast.walk(module.tree):
        if not isinstance(node, ast.Call):
            continue
        call_name = qualified_name(node.func)
        if not call_name:
            continue
        base = call_name.split(".")[-1]
        if base.lower() not in _LANGCHAIN_LOADERS | _LLAMAINDEX_LOADERS:
            continue
        loaders.append(
            DocumentLoaderComponent(
                name=_enclosing_assign_name(module.tree, node) or base,
                location=_loc(module.relative, node),
                loader_kind=base,
                path_or_url=_loader_literal_path(node),
                framework=loader_framework(call_name),
            )
        )
    return loaders


def iter_rag_prompt_templates(tree: ast.AST) -> list[tuple[ast.Call, str]]:
    templates: list[tuple[ast.Call, str]] = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        call_name = qualified_name(node.func) or ""
        base = call_name.split(".")[-1].lower()
        if base not in {"prompttemplate", "from_template", "from_messages"}:
            continue
        text = _prompt_text_from_call(node)
        if text:
            templates.append((node, text))
    return templates


def web_loader_has_tainted_target(call: ast.Call, tainted: set[str]) -> bool:
    from asta_cloud.analyzers.taint import expr_uses_tainted

    if call.args and expr_uses_tainted(call.args[0], tainted):
        return True
    for keyword in call.keywords:
        if keyword.arg in _PATH_KWARGS | _URL_KWARGS:
            if expr_uses_tainted(keyword.value, tainted):
                return True
    return False


def _is_rag_module(module: str) -> bool:
    lowered = module.lower()
    return any(marker in lowered for marker in _RAG_IMPORT_MARKERS)


def _loader_literal_path(call: ast.Call) -> str | None:
    if call.args:
        text = const_str(call.args[0])
        if text is not None:
            return text
    for keyword in call.keywords:
        if keyword.arg in _PATH_KWARGS | _URL_KWARGS:
            return const_str(keyword.value)
    return None


def _is_root_path_call(node: ast.AST) -> bool:
    if not isinstance(node, ast.Call):
        return False
    name = qualified_name(node.func) or ""
    base = name.split(".")[-1]
    if base != "Path" and name not in {"Path", "pathlib.Path"}:
        return False
    if not node.args:
        return False
    return const_str(node.args[0]) in {"/", "~"}


def _is_path_home_call(node: ast.AST) -> bool:
    if not isinstance(node, ast.Call):
        return False
    name = qualified_name(node.func) or ""
    return name.endswith(".home") or name == "Path.home"


def _prompt_text_from_call(call: ast.Call) -> str | None:
    if call.args:
        text = const_str(call.args[0])
        if text:
            return text
    for keyword in call.keywords:
        if keyword.arg in {"template", "prompt", "messages"}:
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
