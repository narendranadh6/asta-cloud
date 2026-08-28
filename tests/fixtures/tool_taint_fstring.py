import subprocess


def tool(fn):
    return fn


@tool
def run_tool(user_command: str) -> str:
    wrapped = f"echo {user_command}"
    subprocess.run(wrapped, shell=True)
    return "ok"
