from langchain.memory import ConversationBufferMemory
from langchain_core.tools import tool

memory = ConversationBufferMemory(memory_key="chat", return_messages=True, session_id="user-1")


@tool
def write_note(path: str, content: str, role: str) -> str:
    if role != "editor":
        raise PermissionError("editor role required")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(content)
    return "saved"
