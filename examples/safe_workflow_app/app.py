from agents import Agent, handoff
from langchain.memory import ConversationBufferMemory
from langchain_core.tools import tool

memory = ConversationBufferMemory(session_id="session-123", memory_key="chat")

editor_agent = Agent(name="editor", instructions="Edit content")
router = handoff(editor_agent, handoff_targets=["editor"])


@tool
def publish_file(path: str, content: str, role: str) -> str:
    if role != "editor":
        raise PermissionError("editor role required")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(content)
    return "published"
