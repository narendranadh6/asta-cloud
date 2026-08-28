from prompts import SYSTEM_PROMPT
from tools import read_note_tool, search_tool

API_HOST = "https://example.invalid"


class Agent:
    def __init__(self, **kwargs):  # pragma: no cover - parsed, never executed
        self.kwargs = kwargs


agent = Agent(
    tools=[search_tool, read_note_tool],
    allowed_tools=["search_tool", "read_note_tool"],
    instructions=SYSTEM_PROMPT,
)
