from __future__ import annotations

from asta_cloud.analyzers.context import ScanContext
from asta_cloud.discovery.parse import source_line
from asta_cloud.discovery.rag import (
    is_risky_rag_prompt_template,
    iter_rag_prompt_templates,
    module_has_retriever,
)
from asta_cloud.models.enums import Confidence, Severity
from asta_cloud.models.finding import Finding
from asta_cloud.models.location import Location
from asta_cloud.rules.base import make_finding


class RagPromptInjectionRule:
    id = "ASTA-SEC-014"
    title = "RAG prompt missing document context separation"
    severity = Severity.MEDIUM

    def check(self, ctx: ScanContext) -> list[Finding]:
        findings: list[Finding] = []
        for module in ctx.modules:
            if module.tree is None or not module_has_retriever(module.tree):
                continue
            for node, template in iter_rag_prompt_templates(module.tree):
                if not is_risky_rag_prompt_template(template):
                    continue
                findings.append(
                    make_finding(
                        rule_id=self.id,
                        title=self.title,
                        description=(
                            "A retrieval-augmented prompt template includes a user query "
                            "placeholder without a separate retrieved-context placeholder. "
                            "User input may be treated as trusted instructions."
                        ),
                        severity=self.severity,
                        confidence=Confidence.MEDIUM,
                        location=Location(
                            path=module.relative,
                            line=node.lineno,
                            end_line=node.end_lineno,
                        ),
                        snippet=source_line(module.source, node.lineno),
                        remediation=(
                            "Keep user queries and retrieved documents in distinct "
                            "template variables. Add explicit boundaries and instruct "
                            "the model to treat context as untrusted data."
                        ),
                        owasp=["LLM01:2025", "LLM08:2025"],
                    )
                )
        return findings
