from __future__ import annotations

from asta_cloud.analyzers.context import ScanContext
from asta_cloud.analyzers.taint import iter_calls_with_taint
from asta_cloud.discovery.parse import iter_functions, qualified_name, source_line
from asta_cloud.discovery.rag import is_web_loader, web_loader_has_tainted_target
from asta_cloud.models.enums import Confidence, Severity
from asta_cloud.models.finding import Finding
from asta_cloud.models.location import Location
from asta_cloud.rules.base import make_finding


class RagUserUrlLoaderRule:
    id = "ASTA-SEC-013"
    title = "User-controlled URL in RAG web loader"
    severity = Severity.HIGH

    def check(self, ctx: ScanContext) -> list[Finding]:
        findings: list[Finding] = []
        for module in ctx.modules:
            if module.tree is None:
                continue
            for fn in iter_functions(module.tree):
                params = {arg.arg for arg in fn.args.args if arg.arg != "self"}
                if not params:
                    continue
                for call, tainted in iter_calls_with_taint(fn, params):
                    call_name = qualified_name(call.func) or ""
                    base = call_name.split(".")[-1]
                    if not is_web_loader(base):
                        continue
                    if not web_loader_has_tainted_target(call, tainted):
                        continue
                    findings.append(
                        make_finding(
                            rule_id=self.id,
                            title=self.title,
                            description=(
                                "A RAG web loader fetches content from a user-controlled "
                                "URL. Attackers can supply internal endpoints or malicious "
                                "pages for prompt injection or SSRF."
                            ),
                            severity=self.severity,
                            confidence=Confidence.HIGH,
                            location=Location(
                                path=module.relative,
                                line=call.lineno,
                                end_line=call.end_lineno,
                            ),
                            snippet=source_line(module.source, call.lineno),
                            remediation=(
                                "Allowlist permitted URL hosts and schemes. Never pass "
                                "raw user input directly into web loaders."
                            ),
                            owasp=["LLM01:2025", "LLM08:2025"],
                            call_name=call_name,
                        )
                    )
        return findings
