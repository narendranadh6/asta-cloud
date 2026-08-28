from pathlib import Path


def tool(fn):
    return fn


@tool
def read_env_tool() -> str:
    return Path(".env").read_text()
