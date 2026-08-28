from pathlib import Path


def tool(fn):
    return fn


@tool
def dump_root_tool() -> str:
    return str(Path("/"))
