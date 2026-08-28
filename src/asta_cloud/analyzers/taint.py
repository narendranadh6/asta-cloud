from __future__ import annotations

import ast
from collections.abc import Iterator

from asta_cloud.discovery.parse import qualified_name


def expr_uses_tainted(node: ast.AST, tainted: set[str]) -> bool:
    if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load) and node.id in tainted:
        return True
    if isinstance(node, ast.JoinedStr):
        return any(
            isinstance(part, ast.FormattedValue) and expr_uses_tainted(part.value, tainted)
            for part in node.values
        )
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        return expr_uses_tainted(node.left, tainted) or expr_uses_tainted(node.right, tainted)
    if isinstance(node, ast.Call):
        if any(expr_uses_tainted(arg, tainted) for arg in node.args):
            return True
        return any(expr_uses_tainted(keyword.value, tainted) for keyword in node.keywords)
    for child in ast.iter_child_nodes(node):
        if expr_uses_tainted(child, tainted):
            return True
    return False


def calls_in_expr(node: ast.AST) -> list[ast.Call]:
    return [child for child in ast.walk(node) if isinstance(child, ast.Call)]


def _add_assign_targets(target: ast.AST, tainted: set[str]) -> set[str]:
    updated = set(tainted)
    if isinstance(target, ast.Name):
        updated.add(target.id)
    elif isinstance(target, (ast.Tuple, ast.List)):
        for elt in target.elts:
            updated |= _add_assign_targets(elt, set())
    return updated


def _apply_assign(targets: list[ast.expr], value: ast.AST, tainted: set[str]) -> set[str]:
    if not expr_uses_tainted(value, tainted):
        return tainted
    updated = set(tainted)
    for target in targets:
        updated |= _add_assign_targets(target, set())
    return updated


CallTaintOut = list[tuple[ast.Call, set[str]]]


def _visit_block(stmts: list[ast.stmt], tainted: set[str], out: CallTaintOut) -> set[str]:
    for stmt in stmts:
        tainted = _visit_stmt(stmt, tainted, out)
    return tainted


def _visit_stmt(stmt: ast.stmt, tainted: set[str], out: CallTaintOut) -> set[str]:
    if isinstance(stmt, ast.Assign):
        for call in calls_in_expr(stmt.value):
            out.append((call, set(tainted)))
        return _apply_assign(stmt.targets, stmt.value, tainted)
    if isinstance(stmt, ast.AnnAssign) and stmt.value is not None:
        for call in calls_in_expr(stmt.value):
            out.append((call, set(tainted)))
        return _apply_assign([stmt.target], stmt.value, tainted)
    if isinstance(stmt, ast.AugAssign):
        if expr_uses_tainted(stmt.value, tainted) or (
            isinstance(stmt.target, ast.Name) and stmt.target.id in tainted
        ):
            return _add_assign_targets(stmt.target, tainted)
        return tainted
    if isinstance(stmt, ast.Expr):
        for call in calls_in_expr(stmt.value):
            out.append((call, set(tainted)))
        return tainted
    if isinstance(stmt, ast.Return) and stmt.value is not None:
        for call in calls_in_expr(stmt.value):
            out.append((call, set(tainted)))
        return tainted
    if isinstance(stmt, ast.If):
        tainted = _visit_block(stmt.body, tainted, out)
        return _visit_block(stmt.orelse, tainted, out)
    if isinstance(stmt, (ast.For, ast.AsyncFor)):
        if stmt.iter is not None:
            for call in calls_in_expr(stmt.iter):
                out.append((call, set(tainted)))
        return _visit_block(stmt.body, tainted, out)
    if isinstance(stmt, (ast.While, ast.With, ast.AsyncWith)):
        return _visit_block(stmt.body, tainted, out)
    if isinstance(stmt, ast.Try):
        tainted = _visit_block(stmt.body, tainted, out)
        for handler in stmt.handlers:
            tainted = _visit_block(handler.body, tainted, out)
        tainted = _visit_block(stmt.orelse, tainted, out)
        return _visit_block(stmt.finalbody, tainted, out)
    return tainted


def iter_calls_with_taint(
    fn: ast.FunctionDef | ast.AsyncFunctionDef,
    sources: set[str],
) -> Iterator[tuple[ast.Call, set[str]]]:
    """Yield each call in fn with the tainted-name set at that program point."""
    collected: list[tuple[ast.Call, set[str]]] = []
    _visit_block(fn.body, set(sources), collected)
    yield from collected


def call_has_tainted_argument(call: ast.Call, tainted: set[str]) -> bool:
    if not tainted:
        return False
    for arg in call.args:
        if expr_uses_tainted(arg, tainted):
            return True
    for keyword in call.keywords:
        if keyword.value is not None and expr_uses_tainted(keyword.value, tainted):
            return True
    return False


def sink_call_name(call: ast.Call) -> str | None:
    return qualified_name(call.func)
