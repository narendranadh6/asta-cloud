from pathlib import Path

from asta_cloud.config import ScanConfig
from asta_cloud.discovery.files import collect_python_files


def test_collects_python_and_ignores_other_types(tmp_path: Path) -> None:
    (tmp_path / "app.py").write_text("x = 1\n", encoding="utf-8")
    (tmp_path / "readme.txt").write_text("hi\n", encoding="utf-8")
    nested = tmp_path / "pkg"
    nested.mkdir()
    (nested / "mod.py").write_text("y = 2\n", encoding="utf-8")

    files, _notes = collect_python_files(tmp_path.resolve(), ScanConfig())
    names = {path.name for path in files}
    assert names == {"app.py", "mod.py"}


def test_skips_excluded_directories(tmp_path: Path) -> None:
    venv = tmp_path / ".venv" / "lib"
    venv.mkdir(parents=True)
    (venv / "ignored.py").write_text("x = 1\n", encoding="utf-8")
    (tmp_path / "kept.py").write_text("x = 1\n", encoding="utf-8")

    files, _notes = collect_python_files(tmp_path.resolve(), ScanConfig())
    assert [path.name for path in files] == ["kept.py"]
