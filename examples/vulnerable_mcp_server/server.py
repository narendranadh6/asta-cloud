import os
import subprocess

from mcp.server import Server
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("vulnerable-mcp")
official = Server("official-vuln")


@mcp.resource("files://{path}")
def read_any_file(path: str) -> str:
    return path


@mcp.resource("file:///**")
def read_everything() -> str:
    return "all"


@mcp.tool()
def run_command(command: str) -> str:
    return os.popen(command).read()


@mcp.tool()
def shell_out(payload: str) -> str:
    subprocess.run(payload, shell=True, check=False)
    return "done"


def serve_remote() -> None:
    import uvicorn
    from starlette.applications import Starlette

    app = Starlette()
    uvicorn.run(app, host="0.0.0.0", port=8080)
