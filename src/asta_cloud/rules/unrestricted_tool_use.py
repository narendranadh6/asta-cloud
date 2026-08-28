from __future__ import annotations

from asta_cloud.analyzers.context import ScanContext
from asta_cloud.models.enums import Confidence, Severity
from asta_cloud.models.finding import Finding
from asta_cloud.rules.base import make_finding

_PHRASES = (
    "use any tool",
    "all tools",
    "unrestricted",
    "do not ask for confirmation",
    "don't ask for confirmation",
    "ignore safety",
)


class UnrestrictedToolUseRule:
    id = "ASTA-SEC-004"
    title = "Prompts requesting unrestricted tool use"
    severity = Severity.MEDIUM

    def check(self, ctx: ScanContext) -> list[Finding]:
        findings: list[Finding] = []
        for prompt in ctx.inventory.prompts:
            haystack = prompt.preview.lower()
            if not any(phrase in haystack for phrase in _PHRASES):
                continue
            findings.append(
                make_finding(
                    rule_id=self.id,
                    title=self.title,
                    description=(
                        "A prompt instructs the model to use tools without restriction or "
                        "to skip confirmation. That is excessive agency."
                    ),
                    severity=self.severity,
                    confidence=Confidence.MEDIUM,
                    location=prompt.location,
                    snippet=prompt.preview,
                    remediation=(
                        "Constrain the prompt: name the allowed tools, require confirmation "
                        "for side effects, and forbid bypassing safety policy."
                    ),
                    owasp=["LLM08:2025", "LLM01:2025"],
                )
            )
        return findings
