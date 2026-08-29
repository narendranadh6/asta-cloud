"""Handoff patterns that must not be flagged as unrestricted routing."""

from agents import Handoff


def build_handoff_factory() -> Handoff:
    return Handoff(
        tool_name="transfer",
        tool_description="Transfer to another agent",
        input_json_schema={},
        on_invoke_handoff=lambda ctx, data: None,
    )


class NodeIds:
    def handoff(self, item: object) -> str:
        return str(item)


def render_graph(handoff: object) -> str:
    node_ids = NodeIds()
    return node_ids.handoff(handoff)
