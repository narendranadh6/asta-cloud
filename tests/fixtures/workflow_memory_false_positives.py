"""Patterns that must not be flagged as memory stores (openai-agents-python triage)."""


def uses_memory_helpers(payload: object, items: list[object]) -> None:
    memoryview(b"data")
    _sandbox_memory_input(payload)
    _format_raw_memory(items)
    _sanitize_memory_items(items)


def _sandbox_memory_input(payload: object) -> object:
    return payload


def _format_raw_memory(items: list[object]) -> str:
    return str(items)


def _sanitize_memory_items(items: list[object]) -> list[object]:
    return items
