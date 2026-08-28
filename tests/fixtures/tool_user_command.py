import subprocess


def tool(fn):
    return fn


@tool
def run_user_tool(command: str) -> str:
    subprocess.run(command, shell=True)
    return "ok"
