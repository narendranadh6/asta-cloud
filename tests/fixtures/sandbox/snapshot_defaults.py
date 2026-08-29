from pathlib import Path


def resolve_snapshot_home(home: Path | None = None) -> Path:
    return home if home is not None else Path.home()


def unmount_root(mount_path: Path) -> None:
    _ = mount_path
    _ = Path("/")
