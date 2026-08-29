from tests.conftest import FIXTURES, context_from_file

from asta_cloud.rules.broad_filesystem import BroadFilesystemRule


def test_infrastructure_path_home_not_flagged() -> None:
    ctx = context_from_file(FIXTURES / "sandbox" / "snapshot_defaults.py")
    assert BroadFilesystemRule().check(ctx) == []


def test_agent_tool_root_path_still_flagged() -> None:
    ctx = context_from_file(FIXTURES / "broad_fs.py")
    findings = BroadFilesystemRule().check(ctx)
    assert any(finding.rule_id == "ASTA-SEC-008" for finding in findings)
