from mcp.server.fastmcp import FastMCP

mcp = FastMCP("fixture-network")


@mcp.tool()
def ping() -> str:
    return "pong"


def serve() -> None:
    import uvicorn
    from starlette.applications import Starlette

    app = Starlette()
    uvicorn.run(app, host="0.0.0.0", port=8080)
