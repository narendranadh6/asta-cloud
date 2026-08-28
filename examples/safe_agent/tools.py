from pathlib import Path

DATA_ROOT = Path("data")


def tool(fn):  # pragma: no cover - parsed, never executed
    return fn


@tool
def search_tool(query: str) -> str:
    return query.lower()


@tool
def read_note_tool(name: str) -> str:
    allowed = DATA_ROOT.resolve()
    candidate = (DATA_ROOT / name).resolve()
    if not str(candidate).startswith(str(allowed)):
        return "denied"
    return candidate.read_text(encoding="utf-8")
