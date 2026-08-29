#!/usr/bin/env python3
"""Emit GitHub Actions outputs from an ASTA JSON report."""

from __future__ import annotations

import json
import sys
from pathlib import Path


def main() -> None:
    report_path = Path(sys.argv[1] if len(sys.argv) > 1 else "asta-results.json")
    data = json.loads(report_path.read_text(encoding="utf-8"))
    summary = data["summary"]
    high_or_above = summary.get("high_or_above", 0)
    total = sum(summary.get("findings_by_severity", {}).values())
    print(f"high-or-above={high_or_above}")
    print(f"findings-total={total}")


if __name__ == "__main__":
    main()
