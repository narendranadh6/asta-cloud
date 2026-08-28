from pathlib import Path

import pytest

from asta_cloud.config import ScanConfig
from asta_cloud.discovery.files import collect_python_files
from asta_cloud.security.paths import PathSafetyError, resolve_scan_root


def test_rejects_url_targets() -> None:
    with pytest.raises(PathSafetyError, match="URL"):
        resolve_scan_root("https://example.com/repo")


def test_rejects_missing_directory(tmp_path: Path) -> None:
    with pytest.raises(PathSafetyError, match="does not exist"):
        resolve_scan_root(tmp_path / "missing")


def test_rejects_file_as_target(tmp_path: Path) -> None:
    target = tmp_path / "file.py"
    target.write_text("x = 1\n", encoding="utf-8")
    with pytest.raises(PathSafetyError, match="directory"):
        resolve_scan_root(target)


def test_skips_symlink_outside_target(tmp_path: Path) -> None:
    root = tmp_path / "proj"
    root.mkdir()
    (root / "ok.py").write_text("x = 1\n", encoding="utf-8")
    outside = tmp_path / "secret.py"
    outside.write_text("OPENAI_API_KEY = 'outside'\n", encoding="utf-8")
    (root / "escape.py").symlink_to(outside)

    files, notes = collect_python_files(root.resolve(), ScanConfig())
    names = {path.name for path in files}
    assert "ok.py" in names
    assert "escape.py" not in names
    assert any("symlink outside target" in note for note in notes)


def test_allows_symlink_inside_target(tmp_path: Path) -> None:
    root = tmp_path / "proj"
    inner = root / "pkg"
    inner.mkdir(parents=True)
    target_file = inner / "mod.py"
    target_file.write_text("x = 1\n", encoding="utf-8")
    (root / "alias.py").symlink_to(target_file)

    files, notes = collect_python_files(root.resolve(), ScanConfig())
    assert any(path.name == "alias.py" or path.name == "mod.py" for path in files)
    assert not any("symlink outside target" in note for note in notes)


def test_does_not_follow_parent_escape(tmp_path: Path) -> None:
    root = tmp_path / "proj"
    root.mkdir()
    (root / "ok.py").write_text("x = 1\n", encoding="utf-8")
    files, _notes = collect_python_files(root.resolve(), ScanConfig())
    for path in files:
        assert path.resolve().is_relative_to(root.resolve())
