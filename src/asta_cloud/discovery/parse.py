from __future__ import annotations

import ast
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path

from asta_cloud.security.paths import open_contained, relative_posix


@dataclass(frozen=True)
class ParsedModule:
    path: Path
    relative: str
    source: str
    tree: ast.AST | None
    parse_error: str | None


def parse_modules(root: Path, files: list[Path]) -> list[ParsedModule]:
    modules: list[ParsedModule] = []
    for path in files:
        source = open_contained(path, root)
        relative = relative_posix(path, root)
        try:
            tree: ast.AST | None = ast.parse(source, filename=relative)
            error = None
        except SyntaxError as exc:
            tree = None
            error = f"syntax error: {exc.msg}"
        modules.append(
            ParsedModule(
                path=path,
                relative=relative,
                source=source,
                tree=tree,
                parse_error=error,
            )
        )
    return modules


def qualified_name(node: ast.AST | None) -> str | None:
    if node is None:
        return None
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        parent = qualified_name(node.value)
        if parent:
            return f"{parent}.{node.attr}"
        return node.attr
    return None


def const_str(node: ast.AST | None) -> str | None:
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.JoinedStr):
        parts: list[str] = []
        for value in node.values:
            if isinstance(value, ast.Constant) and isinstance(value.value, str):
                parts.append(value.value)
        return "".join(parts) if parts else None
    return None


def iter_calls(tree: ast.AST) -> Iterator[ast.Call]:
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            yield node


def iter_functions(tree: ast.AST) -> Iterator[ast.FunctionDef | ast.AsyncFunctionDef]:
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            yield node


def decorator_qualified_names(fn: ast.FunctionDef | ast.AsyncFunctionDef) -> list[str]:
    names: list[str] = []
    for decorator in fn.decorator_list:
        target = decorator.func if isinstance(decorator, ast.Call) else decorator
        qualified = qualified_name(target)
        if qualified:
            names.append(qualified)
    return names


def decorator_base_names(fn: ast.FunctionDef | ast.AsyncFunctionDef) -> list[str]:
    names: list[str] = []
    for decorator in fn.decorator_list:
        target = decorator.func if isinstance(decorator, ast.Call) else decorator
        qualified = qualified_name(target)
        if qualified:
            names.append(qualified.split(".")[-1].lower())
    return names


def function_param_names(fn: ast.FunctionDef | ast.AsyncFunctionDef) -> list[str]:
    args = fn.args
    params = [arg.arg for arg in args.posonlyargs + args.args + args.kwonlyargs]
    if args.vararg:
        params.append(args.vararg.arg)
    if args.kwarg:
        params.append(args.kwarg.arg)
    return [name for name in params if name != "self"]


def callee_names(node: ast.AST) -> list[str]:
    names: list[str] = []
    for call in iter_calls(node):
        name = qualified_name(call.func)
        if name:
            names.append(name)
    return names


def keyword_value(call: ast.Call, name: str) -> ast.AST | None:
    for keyword in call.keywords:
        if keyword.arg == name:
            return keyword.value
    return None


def has_keyword(call: ast.Call, *names: str) -> bool:
    wanted = {name.lower() for name in names}
    return any(kw.arg is not None and kw.arg.lower() in wanted for kw in call.keywords)


def is_shell_true(call: ast.Call) -> bool:
    value = keyword_value(call, "shell")
    return isinstance(value, ast.Constant) and value.value is True


def assignment_name(node: ast.AST) -> str | None:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return node.attr
    return None


def source_line(source: str, lineno: int | None) -> str:
    if lineno is None or lineno < 1:
        return ""
    lines = source.splitlines()
    if lineno > len(lines):
        return ""
    return lines[lineno - 1].strip()


def name_used_in(node: ast.AST, names: set[str]) -> bool:
    for child in ast.walk(node):
        if isinstance(child, ast.Name) and child.id in names:
            return True
    return False
