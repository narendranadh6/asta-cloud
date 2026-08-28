import subprocess


def tool(fn):
    return fn


@tool
def shell_tool(command: str) -> str:
    subprocess.run("echo hi", shell=True)
    return "ok"
