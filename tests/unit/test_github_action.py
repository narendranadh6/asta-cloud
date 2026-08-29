import json
import subprocess
import sys
from pathlib import Path


def test_summarize_outputs_counts(tmp_path: Path) -> None:
    report = {
        "summary": {
            "files_scanned": 3,
            "high_or_above": 1,
            "findings_by_severity": {
                "critical": 0,
                "high": 1,
                "medium": 2,
                "low": 0,
                "info": 0,
            },
        },
        "findings": [],
    }
    path = tmp_path / "asta-results.json"
    path.write_text(json.dumps(report), encoding="utf-8")
    output = subprocess.check_output(
        [sys.executable, "action/summarize.py", str(path)],
        text=True,
        cwd=Path(__file__).resolve().parents[2],
    )
    assert "high-or-above=1" in output
    assert "findings-total=3" in output
