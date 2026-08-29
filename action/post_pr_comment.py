#!/usr/bin/env python3
"""Post or update an ASTA Cloud summary comment on a pull request."""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from collections import Counter
from pathlib import Path


def _api(method: str, url: str, payload: dict | None = None) -> dict:
    token = os.environ["GITHUB_TOKEN"]
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urllib.request.urlopen(request) as response:
        return json.loads(response.read().decode("utf-8"))


def _marker() -> str:
    return "<!-- asta-cloud-pr-comment -->"


def _build_body(report: dict, exit_code: int) -> str:
    summary = report["summary"]
    counts = summary.get("findings_by_severity", {})
    high_or_above = summary.get("high_or_above", 0)
    total = sum(counts.values())
    by_rule = Counter(item["rule_id"] for item in report.get("findings", []))

    if exit_code == "0":
        status = "✅ **Policy gate passed**"
    else:
        status = "❌ **Policy gate failed**"

    lines = [
        _marker(),
        "## ASTA Cloud security scan",
        "",
        status,
        "",
        f"- Files scanned: **{summary.get('files_scanned', 0)}**",
        f"- Findings: **{total}** (high+: **{high_or_above}**)",
        "",
        "| Severity | Count |",
        "| --- | ---: |",
    ]
    for severity in ("critical", "high", "medium", "low", "info"):
        if counts.get(severity):
            lines.append(f"| {severity} | {counts[severity]} |")

    if by_rule:
        lines.extend(["", "### Top rules", ""])
        for rule_id, count in by_rule.most_common(8):
            lines.append(f"- `{rule_id}`: {count}")

    findings = report.get("findings", [])
    if findings:
        lines.extend(["", "### Sample findings", ""])
        for item in findings[:5]:
            loc = item["location"]
            line = loc.get("line")
            path = loc["path"]
            lines.append(
                f"- `{item['rule_id']}` **{item['severity']}** "
                f"`{path}:{line}` — {item['title']}"
            )
        if len(findings) > 5:
            lines.append(f"- …and {len(findings) - 5} more")

    lines.extend(
        [
            "",
            "_Static analysis only. Target code is never executed._",
        ]
    )
    return "\n".join(lines)


def main() -> None:
    report_path = Path(os.environ.get("ASTA_REPORT", "asta-results.json"))
    exit_code = os.environ.get("ASTA_EXIT_CODE", "0")
    repo = os.environ["GITHUB_REPOSITORY"]
    event_path = Path(os.environ["GITHUB_EVENT_PATH"])
    event = json.loads(event_path.read_text(encoding="utf-8"))
    pr_number = event["pull_request"]["number"]

    report = json.loads(report_path.read_text(encoding="utf-8"))
    body = _build_body(report, exit_code)

    list_url = f"https://api.github.com/repos/{repo}/issues/{pr_number}/comments"
    comments = _api("GET", list_url)
    marker = _marker()
    existing = next((item for item in comments if marker in item.get("body", "")), None)

    if existing:
        url = existing["url"]
        _api("PATCH", url, {"body": body})
    else:
        _api("POST", list_url, {"body": body})


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as exc:
        print(exc.read().decode("utf-8"), file=sys.stderr)
        raise SystemExit(1) from exc
