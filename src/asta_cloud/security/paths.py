from __future__ import annotations

import os
from collections.abc import Sequence
from pathlib import Path, PurePosixPath


class PathSafetyError(Exception):
    """Unsafe or unusable scan target (CLI exit 2)."""


def looks_like_url(target: str) -> bool:
    lowered = target.strip().lower()
    return lowered.startswith(("http://", "https://"))


def resolve_scan_root(target: str | Path) -> Path:
    text = str(target).strip()
    if not text:
        raise PathSafetyError("Scan target must not be empty.")
    if looks_like_url(text):
        raise PathSafetyError("Refusing to scan a URL target. Supply a local directory.")

    path = Path(text).expanduser()
    if not path.exists():
        raise PathSafetyError(f"Scan target does not exist: {path}")
    if not path.is_dir():
        raise PathSafetyError(f"Scan target must be a directory: {path}")
    return path.resolve()


def is_contained(path: Path, root: Path) -> bool:
    try:
        resolved = path.resolve()
        root_resolved = root.resolve()
    except (OSError, RuntimeError):
        return False
    return resolved.is_relative_to(root_resolved)


def relative_link_posix(path: Path, root: Path) -> str:
    """Relative path of a directory entry without resolving symlink targets."""
    try:
        return Path(os.path.relpath(path, start=root)).as_posix()
    except ValueError:
        return path.name


def relative_posix(path: Path, root: Path) -> str:
    resolved = path.resolve()
    rel = resolved.relative_to(root.resolve())
    return PurePosixPath(rel.as_posix()).as_posix()


def is_excluded(path: Path, root: Path, exclude: Sequence[str]) -> bool:
    names = set(exclude)
    if path.name in names:
        return True
    try:
        rel = Path(os.path.relpath(path, start=root))
    except ValueError:
        return True
    return any(part in names for part in rel.parts)


def _symlink_resolves_inside(path: Path, root: Path) -> bool:
    try:
        if not path.is_symlink():
            return True
        resolved = path.resolve()
    except (OSError, RuntimeError):
        return False
    return is_contained(resolved, root)


def discover_python_files(
    root: Path,
    exclude: Sequence[str],
    max_file_bytes: int,
    skip_resolved: set[Path] | None = None,
) -> tuple[list[Path], list[str]]:
    """Walk root without following external symlinks. Returns contained .py files and notes."""
    notes: list[str] = []
    files: list[Path] = []
    skip = skip_resolved or set()
    root = root.resolve()

    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        current = Path(dirpath)
        kept_dirs: list[str] = []
        for name in dirnames:
            child = current / name
            if is_excluded(child, root, exclude):
                continue
            try:
                if child.is_symlink() and not _symlink_resolves_inside(child, root):
                    notes.append(
                        f"skipped symlink outside target: {relative_link_posix(child, root)}"
                    )
                    continue
            except OSError:
                continue
            if not is_contained(child, root):
                notes.append(f"skipped path outside target: {name}")
                continue
            kept_dirs.append(name)
        dirnames[:] = kept_dirs

        for name in filenames:
            child = current / name
            if is_excluded(child, root, exclude):
                continue
            try:
                if child.is_symlink() and not _symlink_resolves_inside(child, root):
                    notes.append(
                        f"skipped symlink outside target: {relative_link_posix(child, root)}"
                    )
                    continue
            except OSError:
                continue
            if not is_contained(child, root):
                continue
            resolved = child.resolve()
            if not resolved.is_relative_to(root):
                notes.append(
                    f"skipped symlink outside target: {relative_link_posix(child, root)}"
                )
                continue
            if resolved in skip:
                continue
            if resolved.suffix != ".py":
                continue
            try:
                size = resolved.stat().st_size
            except OSError:
                continue
            if size > max_file_bytes:
                notes.append(
                    f"skipped oversize file: {relative_posix(resolved, root)} ({size} bytes)"
                )
                continue
            files.append(resolved)

    files.sort()
    return files, notes


def open_contained(path: Path, root: Path) -> str:
    """Read a UTF-8 file only after confirming it resolves inside root."""
    resolved = path.resolve()
    if not is_contained(resolved, root):
        raise PathSafetyError(f"Refusing to read path outside scan target: {path}")
    try:
        return resolved.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return resolved.read_text(encoding="utf-8", errors="replace")
