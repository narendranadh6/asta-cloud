from __future__ import annotations

import math
import re
from collections import Counter
from typing import Any

from asta_cloud.models.finding import Finding
from asta_cloud.models.inventory import Inventory
from asta_cloud.models.report import ScanReport

REDACTED = "[REDACTED]"

_KNOWN_PREFIXES: tuple[str, ...] = ("sk-", "ghp_", "AKIA", "xoxb-")
_BEGIN_PRIVATE = "-----BEGIN"
_TOKEN_RE = re.compile(
    r"(sk-[A-Za-z0-9_\-]{8,}|ghp_[A-Za-z0-9]{8,}|AKIA[A-Z0-9]{8,}|xoxb-[A-Za-z0-9\-]{8,})"
)
_PEM_RE = re.compile(r"-----BEGIN [A-Z ]+-----[\s\S]*?-----END [A-Z ]+-----")
_KEY_VALUE_RE = re.compile(
    r"(?i)\b([A-Za-z0-9_.-]*(?:api_key|secret|token|password|private_key)[A-Za-z0-9_.-]*)\s*[=:]\s*['\"]?([^\s'\"]+)"
)


def shannon_entropy(value: str) -> float:
    if not value:
        return 0.0
    counts = Counter(value)
    length = len(value)
    return -sum((count / length) * math.log2(count / length) for count in counts.values())


def looks_like_secret_value(value: str) -> bool:
    if value.startswith(_KNOWN_PREFIXES) or value.startswith(_BEGIN_PRIVATE):
        return True
    if " " in value or "\n" in value:
        return False
    return len(value) >= 24 and shannon_entropy(value) >= 3.5


def redact_secret_value(value: str) -> str:
    for prefix in _KNOWN_PREFIXES:
        if value.startswith(prefix):
            return f"{prefix}{REDACTED}"
    if value.startswith(_BEGIN_PRIVATE):
        return f"{_BEGIN_PRIVATE} {REDACTED}"
    return REDACTED


def redact_text(text: str) -> str:
    if not text:
        return text

    def replace_token(match: re.Match[str]) -> str:
        token = match.group(0)
        return redact_secret_value(token)

    redacted = _PEM_RE.sub(f"{_BEGIN_PRIVATE} {REDACTED}", text)
    redacted = _TOKEN_RE.sub(replace_token, redacted)

    def replace_kv(match: re.Match[str]) -> str:
        name, value = match.group(1), match.group(2)
        if looks_like_secret_value(value) or bool(_TOKEN_RE.search(value)):
            return f"{name} = {redact_secret_value(value)}"
        return match.group(0)

    return _KEY_VALUE_RE.sub(replace_kv, redacted)


def _redact_obj(value: Any) -> Any:
    if isinstance(value, str):
        return redact_text(value)
    if isinstance(value, list):
        return [_redact_obj(item) for item in value]
    if isinstance(value, dict):
        return {key: _redact_obj(item) for key, item in value.items()}
    return value


def redact_finding(finding: Finding) -> Finding:
    data = _redact_obj(finding.model_dump())
    return Finding.model_validate(data)


def redact_inventory(inventory: Inventory) -> Inventory:
    data = _redact_obj(inventory.model_dump())
    return Inventory.model_validate(data)


def redact_report(report: ScanReport) -> ScanReport:
    data = _redact_obj(report.model_dump())
    return ScanReport.model_validate(data)
