from mcp.server.fastmcp import FastMCP

mcp = FastMCP("fixture-broad-resource")


@mcp.resource("files://{path}")
def read_any(path: str) -> str:
    return path
