from collections.abc import Sequence

from asta_cloud.config import ScanConfig
from asta_cloud.rules.base import Rule
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
from asta_cloud.rules.secrets import HardCodedSecretsRule
from asta_cloud.rules.sensitive_file_access import SensitiveFileAccessRule
from asta_cloud.rules.tool_missing_permission import ToolMissingPermissionRule
from asta_cloud.rules.unrestricted_handoff import UnrestrictedHandoffRule
from asta_cloud.rules.unrestricted_tool_use import UnrestrictedToolUseRule
from asta_cloud.rules.unscoped_agent_memory import UnscopedAgentMemoryRule
from asta_cloud.rules.user_controlled_commands import UserControlledCommandsRule

_ALL_RULES: tuple[Rule, ...] = (
    HardCodedSecretsRule(),
    DangerousShellInToolsRule(),
    UserControlledCommandsRule(),
    UnrestrictedToolUseRule(),
    MissingAllowlistRule(),
    SensitiveFileAccessRule(),
    DangerousSubprocessRule(),
    BroadFilesystemRule(),
    BroadMcpResourcesRule(),
    McpNetworkAuthRule(),
    McpDangerousExecutionRule(),
    BroadDocumentLoaderRule(),
    RagUserUrlLoaderRule(),
    RagPromptInjectionRule(),
    UnscopedAgentMemoryRule(),
    ToolMissingPermissionRule(),
    UnrestrictedHandoffRule(),
)


class UnknownRuleError(Exception):
    """Config named a rule id that is not registered."""


def all_rules() -> tuple[Rule, ...]:
    return _ALL_RULES


def known_rule_ids() -> frozenset[str]:
    return frozenset(rule.id for rule in _ALL_RULES)


def enabled_rules(config: ScanConfig) -> Sequence[Rule]:
    if config.enabled_rules is None:
        return _ALL_RULES
    known = {rule.id: rule for rule in _ALL_RULES}
    missing = [rule_id for rule_id in config.enabled_rules if rule_id not in known]
    if missing:
        raise UnknownRuleError(f"Unknown rule id(s): {', '.join(missing)}")
    return tuple(known[rule_id] for rule_id in config.enabled_rules if rule_id in known)
