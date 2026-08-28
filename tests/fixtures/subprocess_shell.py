import subprocess


def cleanup_tmp() -> None:
    subprocess.run("echo cleanup", shell=True)
