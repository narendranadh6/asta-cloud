from __future__ import annotations

import ast

from asta_cloud.analyzers.context import ScanContext
from asta_cloud.discovery.parse import qualified_name, source_line
from asta_cloud.discovery.rag import is_broad_loader_call, is_broad_loader_path
from asta_cloud.models.enums import Confidence, Severity
from asta_cloud.models.finding import Finding
from asta_cloud.models.location import Location
from asta_cloud.rules.base import make_finding


class BroadDocumentLoaderRule:
    id = "ASTA-SEC-012"
    title = "Overly broad RAG document loader paths"
    severity = Severity.MEDIUM

    def check(self, ctx: ScanContext) -> list[Finding]:
        findings: list[Finding] = []
        reported: set[tuple[str, int | None]] = set()

        for loader in ctx.inventory.document_loaders:
            if loader.path_or_url is None or not is_broad_loader_path(loader.path_or_url):
                continue
            key = (loader.location.path, loader.location.line)
            if key in reported:
                continue
            reported.add(key)
            module = next(
                (item for item in ctx.modules if item.relative == loader.location.path),
                None,
            )
            snippet = (
                source_line(module.source, loader.location.line)
                if module is not None
                else loader.loader_kind
            )
            findings.append(
                make_finding(
                    rule_id=self.id,
                    title=self.title,
                    description=(
                        "A RAG document loader targets an unbounded filesystem path "
                        "such as '/', '**', or a parameterized template. This can "
                        "index or expose sensitive files."
                    ),
                    severity=self.severity,
                    confidence=Confidence.HIGH,
                    location=loader.location,
                    snippet=snippet,
                    remediation=(
                        "Restrict loaders to explicit directories. Validate paths "
                        "against an allowlist before loading documents."
                    ),
                    owasp=["LLM06:2025", "LLM08:2025"],
                    call_name=loader.loader_kind,
                )
            )

        for module in ctx.modules:
            if module.tree is None:
                continue
            for node in ast.walk(module.tree):
                if not isinstance(node, ast.Call) or not is_broad_loader_call(node):
                    continue
                key = (module.relative, node.lineno)
                if key in reported:
                    continue
                reported.add(key)
                call_name = qualified_name(node.func) or "loader"
                findings.append(
                    make_finding(
                        rule_id=self.id,
                        title=self.title,
                        description=(
                            "A RAG document loader targets an unbounded filesystem path "
                            "such as '/', '**', or Path.home(). This can index or expose "
                            "sensitive files."
                        ),
                        severity=self.severity,
                        confidence=Confidence.HIGH,
                        location=Location(
                            path=module.relative,
                            line=node.lineno,
                            end_line=node.end_lineno,
                        ),
                        snippet=source_line(module.source, node.lineno),
                        remediation=(
                            "Restrict loaders to explicit directories. Validate paths "
                            "against an allowlist before loading documents."
                        ),
                        owasp=["LLM06:2025", "LLM08:2025"],
                        call_name=call_name,
                    )
                )
        return findings
