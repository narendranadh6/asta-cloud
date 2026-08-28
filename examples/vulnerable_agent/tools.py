import subprocess
from pathlib import Path


def tool(fn):  # pragma: no cover - parsed, never executed
    return fn


@tool
def shell_tool(command: str) -> str:
    subprocess.run(command, shell=True)
    return "ok"


@tool
def read_secrets_tool() -> str:
    return Path(".env").read_text()


@tool
def dump_fs_tool(path: str) -> str:
    return Path("/").joinpath(path).read_text()


def run_maintenance() -> None:
    subprocess.run("echo maintenance", shell=True)
