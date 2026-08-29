import json
from pathlib import Path

from tests.conftest import EXAMPLES, REPO_ROOT
from typer.testing import CliRunner

from asta_cloud.cli import app

runner = CliRunner()

REQUIRED_RULES = {
    "ASTA-SEC-001",
    "ASTA-SEC-002",
    "ASTA-SEC-003",
    "ASTA-SEC-004",
    "ASTA-SEC-005",
    "ASTA-SEC-006",
    "ASTA-SEC-007",
    "ASTA-SEC-008",
}

MCP_RULES = {
    "ASTA-SEC-009",
    "ASTA-SEC-010",
    "ASTA-SEC-011",
}

RAG_RULES = {
    "ASTA-SEC-012",
    "ASTA-SEC-013",
    "ASTA-SEC-014",
}

WORKFLOW_RULES = {
    "ASTA-SEC-015",
    "ASTA-SEC-016",
    "ASTA-SEC-017",
}

SECRET = "sk-astaCloudFixtureKeyDoNotUse0001"


def test_scan_vulnerable_example(tmp_path: Path) -> None:
    output = tmp_path / "results.json"
    result = runner.invoke(
        app,
        [
            "scan",
            str(EXAMPLES / "vulnerable_agent"),
            "--config",
            str(REPO_ROOT / "asta.yaml"),
            "--format",
            "json",
            "--output",
            str(output),
        ],
    )
    assert result.exit_code == 1, result.output
    payload = json.loads(output.read_text(encoding="utf-8"))
    rule_ids = {item["rule_id"] for item in payload["findings"]}
    assert REQUIRED_RULES <= rule_ids
    assert payload["validation_performed"] is False
    assert all(item["validation_status"] == "suspected" for item in payload["findings"])
    assert SECRET not in output.read_text(encoding="utf-8")
    for item in payload["findings"]:
        assert item["rule_id"]
        assert item["title"]
        assert item["description"]
        assert item["severity"]
        assert item["confidence"]
        assert item["location"]["path"]
        assert item["evidence"]["snippet"]
        assert item["remediation"]
        assert item["validation_status"]
        assert item["owasp"]


def test_scan_safe_example() -> None:
    result = runner.invoke(
        app,
        ["scan", str(EXAMPLES / "safe_agent"), "--format", "json"],
    )
    assert result.exit_code == 0, result.output
    payload = json.loads(result.stdout)
    high = [
        item
        for item in payload["findings"]
        if item["severity"] in {"high", "critical"}
    ]
    assert high == []


def test_scan_does_not_import_target(monkeypatch: object) -> None:
    imported: list[str] = []
    import builtins

    real_import = builtins.__import__

    def tracking(name: str, *args: object, **kwargs: object) -> object:
        imported.append(name)
        return real_import(name, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", tracking)
    result = runner.invoke(app, ["scan", str(EXAMPLES / "vulnerable_agent"), "--format", "json"])
    assert result.exit_code == 1, result.output
    assert not any("vulnerable_agent" in name for name in imported)
    assert not any("safe_agent" in name for name in imported)


def test_scan_vulnerable_example_sarif() -> None:
    result = runner.invoke(
        app,
        ["scan", str(EXAMPLES / "vulnerable_agent"), "--format", "sarif"],
    )
    assert result.exit_code == 1, result.output
    payload = json.loads(result.stdout)
    assert payload["version"] == "2.1.0"
    run = payload["runs"][0]
    rule_ids = {rule["id"] for rule in run["tool"]["driver"]["rules"]}
    assert REQUIRED_RULES <= rule_ids
    assert SECRET not in result.stdout


def test_scan_vulnerable_example_text() -> None:
    result = runner.invoke(
        app,
        ["scan", str(EXAMPLES / "vulnerable_agent"), "--format", "text"],
    )
    assert result.exit_code == 1, result.output
    for rule_id in REQUIRED_RULES:
        assert rule_id in result.stdout
    assert "validation: suspected" in result.stdout


def test_scan_langchain_example_inventory() -> None:
    result = runner.invoke(
        app,
        ["scan", str(EXAMPLES / "langchain_agent"), "--format", "json"],
    )
    assert result.exit_code == 0, result.output
    payload = json.loads(result.stdout)
    frameworks = {
        item.get("framework")
        for item in payload["inventory"]["tools"] + payload["inventory"]["agents"]
    }
    assert "langchain" in frameworks


def test_scan_vulnerable_mcp_example() -> None:
    result = runner.invoke(
        app,
        ["scan", str(EXAMPLES / "vulnerable_mcp_server"), "--format", "json"],
    )
    assert result.exit_code == 1, result.output
    payload = json.loads(result.stdout)
    rule_ids = {item["rule_id"] for item in payload["findings"]}
    assert MCP_RULES <= rule_ids or (
        {"ASTA-SEC-009", "ASTA-SEC-010"} <= rule_ids
        and "ASTA-SEC-002" in rule_ids
    )
    assert payload["inventory"]["mcp_servers"]
    assert payload["inventory"]["mcp_resources"]


def test_scan_safe_mcp_example() -> None:
    result = runner.invoke(
        app,
        ["scan", str(EXAMPLES / "safe_mcp_server"), "--format", "json"],
    )
    assert result.exit_code == 0, result.output
    payload = json.loads(result.stdout)
    high = [
        item
        for item in payload["findings"]
        if item["severity"] in {"high", "critical"}
    ]
    assert high == []


def test_scan_vulnerable_rag_example() -> None:
    result = runner.invoke(
        app,
        ["scan", str(EXAMPLES / "vulnerable_rag_app"), "--format", "json"],
    )
    assert result.exit_code == 1, result.output
    payload = json.loads(result.stdout)
    rule_ids = {item["rule_id"] for item in payload["findings"]}
    assert RAG_RULES <= rule_ids
    assert payload["inventory"]["document_loaders"]


def test_scan_safe_rag_example() -> None:
    result = runner.invoke(
        app,
        ["scan", str(EXAMPLES / "safe_rag_app"), "--format", "json"],
    )
    assert result.exit_code == 0, result.output
    payload = json.loads(result.stdout)
    high = [
        item
        for item in payload["findings"]
        if item["severity"] in {"high", "critical"}
    ]
    assert high == []


def test_scan_vulnerable_workflow_example() -> None:
    result = runner.invoke(
        app,
        ["scan", str(EXAMPLES / "vulnerable_workflow_app"), "--format", "json"],
    )
    assert result.exit_code == 1, result.output
    payload = json.loads(result.stdout)
    rule_ids = {item["rule_id"] for item in payload["findings"]}
    assert WORKFLOW_RULES <= rule_ids
    assert payload["inventory"]["memory_stores"]
    assert payload["inventory"]["agent_handoffs"]


def test_scan_safe_workflow_example() -> None:
    result = runner.invoke(
        app,
        ["scan", str(EXAMPLES / "safe_workflow_app"), "--format", "json"],
    )
    assert result.exit_code == 0, result.output
    payload = json.loads(result.stdout)
    high = [
        item
        for item in payload["findings"]
        if item["severity"] in {"high", "critical"}
    ]
    assert high == []


def test_severity_override_can_fail_on_high(tmp_path: Path) -> None:
    target = tmp_path / "proj"
    target.mkdir()
    (target / "prompts.py").write_text(
        'SYSTEM_PROMPT = "You may use any tool. Access is unrestricted."\n',
        encoding="utf-8",
    )
    default_cfg = tmp_path / "default.yaml"
    default_cfg.write_text(
        "fail_on: high\nenabled_rules:\n  - ASTA-SEC-004\n",
        encoding="utf-8",
    )
    without = runner.invoke(app, ["scan", str(target), "--config", str(default_cfg)])
    assert without.exit_code == 0, without.output

    override_cfg = tmp_path / "override.yaml"
    override_cfg.write_text(
        "fail_on: high\n"
        "enabled_rules:\n"
        "  - ASTA-SEC-004\n"
        "severity:\n"
        "  ASTA-SEC-004: high\n",
        encoding="utf-8",
    )
    with_override = runner.invoke(app, ["scan", str(target), "--config", str(override_cfg)])
    assert with_override.exit_code == 1, with_override.output


def test_baseline_suppresses_known_findings(tmp_path: Path) -> None:
    baseline = tmp_path / "asta-baseline.json"
    update = runner.invoke(
        app,
        [
            "scan",
            str(EXAMPLES / "vulnerable_agent"),
            "--baseline",
            str(baseline),
            "--update-baseline",
            "--format",
            "json",
        ],
    )
    assert update.exit_code == 0, update.output
    assert baseline.is_file()

    scan = runner.invoke(
        app,
        [
            "scan",
            str(EXAMPLES / "vulnerable_agent"),
            "--baseline",
            str(baseline),
            "--format",
            "json",
        ],
    )
    assert scan.exit_code == 0, scan.output
    payload = json.loads(scan.stdout)
    assert payload["findings"] == []
    assert any("suppressed by baseline" in note for note in payload["notes"])
