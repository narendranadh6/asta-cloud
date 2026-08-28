from tests.conftest import FIXTURES, context_from_file

from asta_cloud.rules.broad_document_loader import BroadDocumentLoaderRule
from asta_cloud.rules.broad_filesystem import BroadFilesystemRule
from asta_cloud.rules.broad_mcp_resources import BroadMcpResourcesRule
from asta_cloud.rules.dangerous_shell import DangerousShellInToolsRule
from asta_cloud.rules.dangerous_subprocess import DangerousSubprocessRule
from asta_cloud.rules.mcp_dangerous_execution import McpDangerousExecutionRule
from asta_cloud.rules.mcp_network_auth import McpNetworkAuthRule
from asta_cloud.rules.missing_allowlist import MissingAllowlistRule
from asta_cloud.rules.rag_prompt_injection import RagPromptInjectionRule
from asta_cloud.rules.rag_user_url_loader import RagUserUrlLoaderRule
from asta_cloud.rules.registry import all_rules
from asta_cloud.rules.secrets import HardCodedSecretsRule
from asta_cloud.rules.sensitive_file_access import SensitiveFileAccessRule
from asta_cloud.rules.tool_missing_permission import ToolMissingPermissionRule
from asta_cloud.rules.unrestricted_handoff import UnrestrictedHandoffRule
from asta_cloud.rules.unrestricted_tool_use import UnrestrictedToolUseRule
from asta_cloud.rules.unscoped_agent_memory import UnscopedAgentMemoryRule
from asta_cloud.rules.user_controlled_commands import UserControlledCommandsRule

CASES = [
    (HardCodedSecretsRule, "secrets_hardcoded.py", "ASTA-SEC-001"),
    (DangerousShellInToolsRule, "tool_shell.py", "ASTA-SEC-002"),
    (UserControlledCommandsRule, "tool_user_command.py", "ASTA-SEC-003"),
    (UserControlledCommandsRule, "tool_taint_chain.py", "ASTA-SEC-003"),
    (UserControlledCommandsRule, "tool_taint_fstring.py", "ASTA-SEC-003"),
    (UnrestrictedToolUseRule, "prompt_unrestricted.py", "ASTA-SEC-004"),
    (MissingAllowlistRule, "agent_no_allowlist.py", "ASTA-SEC-005"),
    (SensitiveFileAccessRule, "tool_sensitive_file.py", "ASTA-SEC-006"),
    (DangerousSubprocessRule, "subprocess_shell.py", "ASTA-SEC-007"),
    (BroadFilesystemRule, "broad_fs.py", "ASTA-SEC-008"),
    (BroadFilesystemRule, "tool_taint_path.py", "ASTA-SEC-008"),
    (BroadMcpResourcesRule, "mcp_broad_resource.py", "ASTA-SEC-009"),
    (McpNetworkAuthRule, "mcp_network_no_auth.py", "ASTA-SEC-010"),
    (McpDangerousExecutionRule, "mcp_dangerous_tool.py", "ASTA-SEC-011"),
    (BroadDocumentLoaderRule, "rag_broad_loader.py", "ASTA-SEC-012"),
    (RagUserUrlLoaderRule, "rag_user_url.py", "ASTA-SEC-013"),
    (RagPromptInjectionRule, "rag_prompt_injection.py", "ASTA-SEC-014"),
    (UnscopedAgentMemoryRule, "workflow_unscoped_memory.py", "ASTA-SEC-015"),
    (ToolMissingPermissionRule, "workflow_missing_permission.py", "ASTA-SEC-016"),
    (UnrestrictedHandoffRule, "workflow_handoff.py", "ASTA-SEC-017"),
]


def test_each_rule_hits_its_fixture() -> None:
    seen: set[str] = set()
    for rule_cls, filename, rule_id in CASES:
        ctx = context_from_file(FIXTURES / filename)
        findings = rule_cls().check(ctx)
        assert any(item.rule_id == rule_id for item in findings), f"{rule_id} via {filename}"
        seen.add(rule_id)
        for item in findings:
            assert item.validation_status.value == "suspected"
            assert item.owasp
            assert item.evidence.snippet
            assert item.location.path
    assert seen == {
        "ASTA-SEC-001",
        "ASTA-SEC-002",
        "ASTA-SEC-003",
        "ASTA-SEC-004",
        "ASTA-SEC-005",
        "ASTA-SEC-006",
        "ASTA-SEC-007",
        "ASTA-SEC-008",
        "ASTA-SEC-009",
        "ASTA-SEC-010",
        "ASTA-SEC-011",
        "ASTA-SEC-012",
        "ASTA-SEC-013",
        "ASTA-SEC-014",
        "ASTA-SEC-015",
        "ASTA-SEC-016",
        "ASTA-SEC-017",
    }


def test_safe_patterns_trigger_no_rules() -> None:
    ctx = context_from_file(FIXTURES / "safe_patterns.py")
    for rule in all_rules():
        findings = rule.check(ctx)
        assert findings == [], f"{rule.id} fired on safe_patterns: {findings}"


def test_mcp_safe_fixture_triggers_no_mcp_rules() -> None:
    ctx = context_from_file(FIXTURES / "mcp_safe.py")
    for rule in (
        BroadMcpResourcesRule(),
        McpNetworkAuthRule(),
        McpDangerousExecutionRule(),
    ):
        assert rule.check(ctx) == [], f"{rule.id} fired on mcp_safe"


def test_rag_safe_fixture_triggers_no_rag_rules() -> None:
    ctx = context_from_file(FIXTURES / "rag_safe.py")
    for rule in (
        BroadDocumentLoaderRule(),
        RagUserUrlLoaderRule(),
        RagPromptInjectionRule(),
    ):
        assert rule.check(ctx) == [], f"{rule.id} fired on rag_safe"


def test_workflow_safe_fixture_triggers_no_workflow_rules() -> None:
    ctx = context_from_file(FIXTURES / "workflow_safe.py")
    for rule in (
        UnscopedAgentMemoryRule(),
        ToolMissingPermissionRule(),
        UnrestrictedHandoffRule(),
    ):
        assert rule.check(ctx) == [], f"{rule.id} fired on workflow_safe"
