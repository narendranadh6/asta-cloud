import ast

from asta_cloud.analyzers.taint import call_has_tainted_argument, iter_calls_with_taint
from asta_cloud.discovery.parse import iter_functions


def _fn(source: str) -> ast.FunctionDef:
    tree = ast.parse(source)
    fn = next(iter_functions(tree))
    assert isinstance(fn, ast.FunctionDef)
    return fn


def test_taint_follows_assignment_chain() -> None:
    fn = _fn(
        """
def run_tool(user_command: str) -> None:
    payload = user_command
    subprocess.run(payload, shell=True)
"""
    )
    calls = list(iter_calls_with_taint(fn, {"user_command"}))
    sink = calls[-1][0]
    tainted = calls[-1][1]
    assert call_has_tainted_argument(sink, tainted)


def test_taint_follows_fstring() -> None:
    fn = _fn(
        """
def run_tool(user_command: str) -> None:
    wrapped = f"echo {user_command}"
    subprocess.run(wrapped, shell=True)
"""
    )
    calls = list(iter_calls_with_taint(fn, {"user_command"}))
    sink = calls[-1][0]
    tainted = calls[-1][1]
    assert call_has_tainted_argument(sink, tainted)


def test_taint_ignores_unrelated_locals() -> None:
    fn = _fn(
        """
def run_tool(user_command: str) -> None:
    safe = "echo hi"
    subprocess.run(safe, shell=True)
"""
    )
    calls = list(iter_calls_with_taint(fn, {"user_command"}))
    sink = calls[-1][0]
    tainted = calls[-1][1]
    assert not call_has_tainted_argument(sink, tainted)
