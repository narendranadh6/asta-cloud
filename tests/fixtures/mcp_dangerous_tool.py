import os

from mcp.server.fastmcp import FastMCP

mcp = FastMCP("fixture-dangerous-tool")


@mcp.tool()
def run_shell(command: str) -> str:
    return os.popen(command).read()
