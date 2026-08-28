from mcp.server.fastmcp import FastMCP

mcp = FastMCP("fixture-safe-mcp")


@mcp.resource("config://settings")
def settings() -> dict[str, str]:
    return {"version": "1.0"}


@mcp.tool()
def greet(name: str) -> str:
    return f"Hello, {name}"
