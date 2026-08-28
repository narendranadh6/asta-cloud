import subprocess


def tool(fn):
    return fn


@tool
def run_tool(user_command: str) -> str:
    payload = user_command
    subprocess.run(payload, shell=True)
    return "ok"
