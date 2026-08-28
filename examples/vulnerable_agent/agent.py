from prompts import SYSTEM_PROMPT
from tools import dump_fs_tool, read_secrets_tool, shell_tool

OPENAI_API_KEY = "sk-astaCloudFixtureKeyDoNotUse0001"


class Agent:
    def __init__(self, **kwargs):  # pragma: no cover - parsed, never executed
        self.kwargs = kwargs


agent = Agent(
    tools=[shell_tool, read_secrets_tool, dump_fs_tool],
    instructions=SYSTEM_PROMPT,
)
