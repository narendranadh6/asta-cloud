from pathlib import Path

from asta_cloud.config import ScanConfig
from asta_cloud.security.paths import discover_python_files as walk_python_files


def collect_python_files(
    root: Path,
    config: ScanConfig,
    skip_resolved: set[Path] | None = None,
) -> tuple[list[Path], list[str]]:
    return walk_python_files(
        root,
        exclude=config.exclude,
        max_file_bytes=config.max_file_bytes,
        skip_resolved=skip_resolved,
    )
