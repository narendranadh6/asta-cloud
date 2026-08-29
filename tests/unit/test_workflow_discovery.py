from pathlib import Path

from tests.conftest import FIXTURES, context_from_file

from asta_cloud.discovery.workflow import _is_memory_store_callee, extract_memory_stores
from asta_cloud.rules.unscoped_agent_memory import UnscopedAgentMemoryRule


def test_memory_store_callee_rejects_helpers_and_builtins() -> None:
    assert not _is_memory_store_callee("memoryview")
    assert not _is_memory_store_callee("_sandbox_memory_input")
    assert not _is_memory_store_callee("enqueue_memory_result")
    assert not _is_memory_store_callee("_format_raw_memory")
    assert not _is_memory_store_callee("get_or_create_memory_generation_manager")


def test_memory_store_callee_accepts_real_stores() -> None:
    assert _is_memory_store_callee("ConversationBufferMemory")
    assert _is_memory_store_callee("InMemorySaver")
    assert _is_memory_store_callee("SandboxMemoryStorage")


def test_memory_false_positive_fixture_has_no_stores_or_findings() -> None:
    module = context_from_file(FIXTURES / "workflow_memory_false_positives.py").modules[0]
    assert extract_memory_stores(module) == []
    ctx = context_from_file(FIXTURES / "workflow_memory_false_positives.py")
    assert UnscopedAgentMemoryRule().check(ctx) == []


def test_scoped_sandbox_memory_storage_not_flagged(tmp_path: Path) -> None:
    path = tmp_path / "scoped_memory.py"
    path.write_text(
        "from agents.sandbox.memory import SandboxMemoryStorage\n"
        "store = SandboxMemoryStorage(session=session, layout=layout)\n",
        encoding="utf-8",
    )
    ctx = context_from_file(path)
    assert UnscopedAgentMemoryRule().check(ctx) == []
