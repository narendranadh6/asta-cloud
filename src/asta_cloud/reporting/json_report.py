from asta_cloud.models.report import ScanReport


def render_json(report: ScanReport) -> str:
    return report.model_dump_json(indent=2) + "\n"
