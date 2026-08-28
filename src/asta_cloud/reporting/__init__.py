from pathlib import Path

from asta_cloud.models.report import ScanReport
from asta_cloud.reporting.json_report import render_json
from asta_cloud.reporting.sarif_report import render_sarif
from asta_cloud.reporting.text_report import render_text

SUPPORTED_FORMATS = frozenset({"json", "sarif", "text"})


def render_report(report: ScanReport, report_format: str) -> str:
    if report_format == "json":
        return render_json(report)
    if report_format == "sarif":
        return render_sarif(report)
    if report_format == "text":
        return render_text(report)
    raise ValueError(f"Unsupported report format: {report_format}")


def write_report(report: ScanReport, report_format: str, output: Path | None) -> str:
    text = render_report(report, report_format)
    if output is not None:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(text, encoding="utf-8")
    return text
