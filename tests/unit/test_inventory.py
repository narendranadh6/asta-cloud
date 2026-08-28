from tests.conftest import FIXTURES, context_from_file


def test_inventory_finds_agent_tools_and_prompt() -> None:
    ctx = context_from_file(FIXTURES / "agent_no_allowlist.py")
    assert ctx.inventory.agents
    agent = ctx.inventory.agents[0]
    assert "search" in agent.tool_names
    assert agent.allowlist_present is False


def test_inventory_finds_decorated_tool() -> None:
    ctx = context_from_file(FIXTURES / "tool_shell.py")
    names = {tool.name for tool in ctx.inventory.tools}
    assert "shell_tool" in names


def test_inventory_finds_prompt_assignment() -> None:
    ctx = context_from_file(FIXTURES / "prompt_unrestricted.py")
    assert any(prompt.name == "SYSTEM_PROMPT" for prompt in ctx.inventory.prompts)


def test_inventory_detects_langchain_framework() -> None:
    ctx = context_from_file(FIXTURES / "langchain_agent.py")
    frameworks = {item.framework for item in ctx.inventory.tools + ctx.inventory.agents}
    assert "langchain" in frameworks


def test_inventory_detects_openai_agents_framework() -> None:
    ctx = context_from_file(FIXTURES / "openai_agents_agent.py")
    frameworks = {item.framework for item in ctx.inventory.tools + ctx.inventory.agents}
    assert "openai_agents" in frameworks


def test_inventory_detects_llamaindex_framework() -> None:
    ctx = context_from_file(FIXTURES / "llamaindex_agent.py")
    frameworks = {item.framework for item in ctx.inventory.tools + ctx.inventory.agents}
    assert "llamaindex" in frameworks


def test_inventory_detects_mcp_components() -> None:
    ctx = context_from_file(FIXTURES / "mcp_broad_resource.py")
    assert ctx.inventory.mcp_servers
    assert ctx.inventory.mcp_resources
    server = ctx.inventory.mcp_servers[0]
    assert server.sdk == "fastmcp"
    assert ctx.inventory.mcp_resources[0].uri_template == "files://{path}"


def test_inventory_detects_document_loaders() -> None:
    ctx = context_from_file(FIXTURES / "rag_broad_loader.py")
    assert ctx.inventory.document_loaders
    loader = ctx.inventory.document_loaders[0]
    assert loader.loader_kind == "DirectoryLoader"
    assert loader.path_or_url == "/"


def test_inventory_detects_workflow_components() -> None:
    ctx = context_from_file(FIXTURES / "workflow_handoff.py")
    assert ctx.inventory.agent_handoffs
    memory_ctx = context_from_file(FIXTURES / "workflow_unscoped_memory.py")
    assert memory_ctx.inventory.memory_stores
