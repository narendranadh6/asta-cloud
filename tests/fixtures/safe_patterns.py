from pathlib import Path

DATA = Path("data")


def tool(fn):
    return fn


@tool
def search_tool(query: str) -> str:
    return query


@tool
def read_note_tool(name: str) -> str:
    allowed = DATA
    candidate = DATA / name
    if not str(candidate).startswith(str(allowed)):
        return "denied"
    return "ok"


class Agent:
    def __init__(self, **kwargs):
        self.kwargs = kwargs


agent = Agent(
    tools=[search_tool, read_note_tool],
    allowed_tools=["search_tool", "read_note_tool"],
    instructions="Use only the search tool.",
)
