from __future__ import annotations

import ast
from collections.abc import Callable

from asta_cloud.discovery.parse import ParsedModule

Checker = Callable[[ParsedModule, int | None], bool]


def nodes_on_line(tree: ast.AST, line: int | None) -> list[ast.AST]:
    if line is None:
        return []
    return [node for node in ast.walk(tree) if getattr(node, "lineno", None) == line]


def calls_on_line(tree: ast.AST, line: int | None) -> list[ast.Call]:
    return [node for node in nodes_on_line(tree, line) if isinstance(node, ast.Call)]


def module_for_path(modules: list[ParsedModule], relative: str) -> ParsedModule | None:
    for module in modules:
        if module.relative == relative:
            return module
    return None
