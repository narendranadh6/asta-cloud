from pathlib import Path

from tests.conftest import FIXTURES, context_from_file

from asta_cloud.discovery.inventory import is_agent_construction_call
from asta_cloud.discovery.workflow import (
    _is_memory_store_callee,
    extract_memory_stores,
    is_user_handoff_call,
)
from asta_cloud.rules.missing_allowlist import MissingAllowlistRule
from asta_cloud.rules.unrestricted_handoff import UnrestrictedHandoffRule
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


def test_internal_tool_forwarding_not_flagged_as_missing_allowlist() -> None:
    ctx = context_from_file(FIXTURES / "agent_internal_tool_forwarding.py")
    assert MissingAllowlistRule().check(ctx) == []


def test_handoff_false_positives_not_flagged() -> None:
    ctx = context_from_file(FIXTURES / "workflow_handoff_false_positives.py")
    assert UnrestrictedHandoffRule().check(ctx) == []


def test_user_handoff_call_rejects_class_constructors_and_methods() -> None:
    import ast

    handoff_class = ast.parse("Handoff(tool_name='x')").body[0].value  # type: ignore[assignment]
    handoff_fn = ast.parse("handoff(agent)").body[0].value  # type: ignore[assignment]
    handoff_method = ast.parse("node_ids.handoff(item)").body[0].value  # type: ignore[assignment]
    assert not is_user_handoff_call(handoff_class)
    assert is_user_handoff_call(handoff_fn)
    assert not is_user_handoff_call(handoff_method)


def test_agent_construction_call_rejects_model_tool_forwarding() -> None:
    import ast

    call = ast.parse(
        "model.get_response(system_instructions='x', input=[], "
        "model_settings={}, tools=all_tools, output_schema=None, handoffs=[], prompt=prompt)"
    ).body[0].value  # type: ignore[assignment]
    assert not is_agent_construction_call(call)
    agent_call = ast.parse("Agent(name='x', tools=[tool])").body[0].value  # type: ignore[assignment]
    assert is_agent_construction_call(agent_call)
