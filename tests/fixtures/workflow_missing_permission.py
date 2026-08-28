from langchain_core.tools import tool


@tool
def write_report(path: str, content: str) -> str:
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(content)
    return "saved"
