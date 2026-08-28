from pathlib import Path

import pytest

from asta_cloud.config import ConfigError, ScanConfig, load_config
from asta_cloud.models.enums import Severity


def test_missing_file_uses_defaults(tmp_path: Path) -> None:
    config, used = load_config(None, tmp_path)
    assert used is None
    assert config.fail_on is Severity.HIGH
    assert ".venv" in config.exclude
    assert config.enabled_rules is None


def test_loads_target_yaml(tmp_path: Path) -> None:
    path = tmp_path / "asta.yaml"
    path.write_text("fail_on: medium\n", encoding="utf-8")
    config, used = load_config(None, tmp_path)
    assert used == path.resolve()
    assert config.fail_on is Severity.MEDIUM


def test_invalid_yaml_raises(tmp_path: Path) -> None:
    path = tmp_path / "asta.yaml"
    path.write_text(": this is not valid: [\n", encoding="utf-8")
    with pytest.raises(ConfigError, match="Invalid YAML"):
        load_config(path, tmp_path)


def test_unknown_key_rejected(tmp_path: Path) -> None:
    path = tmp_path / "asta.yaml"
    path.write_text("unknown_option: true\n", encoding="utf-8")
    with pytest.raises(ConfigError, match="Invalid config"):
        load_config(path, tmp_path)


def test_explicit_missing_file(tmp_path: Path) -> None:
    with pytest.raises(ConfigError, match="not found"):
        load_config(tmp_path / "missing.yaml", tmp_path)


def test_scan_config_defaults() -> None:
    config = ScanConfig()
    assert config.max_file_bytes == 1_048_576
    assert config.severity == {}


def test_loads_severity_overrides(tmp_path: Path) -> None:
    path = tmp_path / "asta.yaml"
    path.write_text(
        "severity:\n  ASTA-SEC-004: high\n  ASTA-SEC-008: low\n",
        encoding="utf-8",
    )
    config, _used = load_config(path, tmp_path)
    assert config.severity["ASTA-SEC-004"] is Severity.HIGH
    assert config.severity["ASTA-SEC-008"] is Severity.LOW


def test_unknown_severity_rule_id_rejected(tmp_path: Path) -> None:
    path = tmp_path / "asta.yaml"
    path.write_text("severity:\n  ASTA-SEC-999: high\n", encoding="utf-8")
    with pytest.raises(ConfigError, match="Unknown rule id"):
        load_config(path, tmp_path)
