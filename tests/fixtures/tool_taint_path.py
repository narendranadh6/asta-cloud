from pathlib import Path


def tool(fn):
    return fn


@tool
def read_path_tool(user_path: str) -> str:
    target = user_path
    return Path(target).read_text()
