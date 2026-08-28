from __future__ import annotations

import ast

from asta_cloud.analyzers.context import ScanContext
from asta_cloud.discovery.parse import qualified_name, source_line
from asta_cloud.discovery.workflow import agent_call_has_unscoped_memory, is_unscoped_memory_store
from asta_cloud.models.enums import Confidence, Severity
from asta_cloud.models.finding import Finding
from asta_cloud.models.location import Location
from asta_cloud.rules.base import make_finding

_AGENT_CALL_SUFFIXES = {
    "agent",
    "create_agent",
    "create_react_agent",
    "create_tool_calling_agent",
    "agentexecutor",
    "reactagent",
    "runner",
}


class UnscopedAgentMemoryRule:
    id = "ASTA-SEC-015"
    title = "Agent memory store without session scoping"
    severity = Severity.MEDIUM

    def check(self, ctx: ScanContext) -> list[Finding]:
        findings: list[Finding] = []
        reported: set[tuple[str, int | None]] = set()

        for store in ctx.inventory.memory_stores:
            if not is_unscoped_memory_store(store):
                continue
            key = (store.location.path, store.location.line)
            if key in reported:
                continue
            reported.add(key)
            findings.append(self._finding(ctx, store.location, store.store_kind))

        for module in ctx.modules:
            if module.tree is None:
                continue
            for node in ast.walk(module.tree):
                if not isinstance(node, ast.Call):
                    continue
                call_name = qualified_name(node.func) or ""
                base = call_name.split(".")[-1].lower()
                if base not in _AGENT_CALL_SUFFIXES and "agent" not in base:
                    continue
                if not agent_call_has_unscoped_memory(node):
                    continue
                key = (module.relative, node.lineno)
                if key in reported:
                    continue
                reported.add(key)
                findings.append(
                    self._finding(
                        ctx,
                        Location(path=module.relative, line=node.lineno, end_line=node.end_lineno),
                        call_name,
                    )
                )
        return findings

    def _finding(self, ctx: ScanContext, location: Location, call_name: str) -> Finding:
        module = next((item for item in ctx.modules if item.relative == location.path), None)
        snippet = source_line(module.source, location.line) if module is not None else call_name
        return make_finding(
            rule_id=self.id,
            title=self.title,
            description=(
                "An agent memory store or agent memory attachment lacks session, user, "
                "or tenant scoping. Memory from one user may leak to another."
            ),
            severity=self.severity,
            confidence=Confidence.MEDIUM,
            location=location,
            snippet=snippet,
            remediation=(
                "Scope memory by session_id, user_id, or tenant_id. Use isolated "
                "namespaces for each principal."
            ),
            owasp=["LLM06:2025", "LLM08:2025"],
            call_name=call_name,
        )
