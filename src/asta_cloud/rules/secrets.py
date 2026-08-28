from __future__ import annotations

import ast
import re

from asta_cloud.analyzers.context import ScanContext
from asta_cloud.discovery.parse import assignment_name, const_str
from asta_cloud.models.enums import Confidence, Severity
from asta_cloud.models.finding import Finding
from asta_cloud.models.location import Location
from asta_cloud.rules.base import make_finding
from asta_cloud.security.redact import looks_like_secret_value

_SECRET_NAME = re.compile(
    r"(?i)(api[_-]?key|secret|password|private[_-]?key|(^|_)token($|_))"
)


class HardCodedSecretsRule:
    id = "ASTA-SEC-001"
    title = "Hard-coded secrets or API keys"
    severity = Severity.HIGH

    def check(self, ctx: ScanContext) -> list[Finding]:
        findings: list[Finding] = []
        for module in ctx.modules:
            if module.tree is None:
                continue
            for node in ast.walk(module.tree):
                pairs = _secret_pairs(node)
                for name, value, target in pairs:
                    if not _SECRET_NAME.search(name):
                        continue
                    if not looks_like_secret_value(value):
                        continue
                    location = Location(
                        path=module.relative,
                        line=getattr(target, "lineno", None),
                        end_line=getattr(target, "end_lineno", None),
                    )
                    findings.append(
                        make_finding(
                            rule_id=self.id,
                            title=self.title,
                            description=(
                                "A secret-like name is assigned a hard-coded credential. "
                                "Store secrets in a secret manager or environment, not source."
                            ),
                            severity=self.severity,
                            confidence=Confidence.HIGH,
                            location=location,
                            snippet=f"assignment {name} = [REDACTED]",
                            remediation=(
                                "Remove the hard-coded value and load it from a secret store "
                                "or environment variable at runtime."
                            ),
                            owasp=["LLM06:2025"],
                        )
                    )
        return findings


def _secret_pairs(node: ast.AST) -> list[tuple[str, str, ast.AST]]:
    found: list[tuple[str, str, ast.AST]] = []
    if isinstance(node, ast.Assign):
        value = const_str(node.value)
        if value is None:
            return found
        for target in node.targets:
            name = assignment_name(target)
            if name:
                found.append((name, value, node))
    elif isinstance(node, ast.AnnAssign) and node.value is not None:
        value = const_str(node.value)
        name = assignment_name(node.target)
        if value is not None and name:
            found.append((name, value, node))
    elif isinstance(node, ast.Call):
        for keyword in node.keywords:
            if keyword.arg is None:
                continue
            value = const_str(keyword.value)
            if value is not None:
                found.append((keyword.arg, value, node))
    elif isinstance(node, ast.Dict):
        for key, value_node in zip(node.keys, node.values, strict=False):
            key_text = const_str(key)
            value = const_str(value_node)
            if key_text and value is not None:
                found.append((key_text, value, node))
    return found
