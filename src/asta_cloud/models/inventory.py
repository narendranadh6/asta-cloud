from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from asta_cloud.models.location import Location

FrameworkKind = Literal["langchain", "openai_agents", "llamaindex", "mcp", "generic"]


class PromptComponent(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str | None
    location: Location
    kind: Literal["assign", "call_kwarg", "constant"]
    preview: str
    framework: FrameworkKind | None = None


class ToolComponent(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str
    location: Location
    kind: Literal["function", "decorator", "call"]
    param_names: list[str] = Field(default_factory=list)
    callee_names: list[str] = Field(default_factory=list)
    framework: FrameworkKind | None = None


class AgentComponent(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str | None
    location: Location
    tool_names: list[str] = Field(default_factory=list)
    prompt_names: list[str] = Field(default_factory=list)
    allowlist_present: bool
    framework: FrameworkKind | None = None


class McpServerComponent(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str | None
    location: Location
    sdk: Literal["fastmcp", "official", "unknown"]
    transport: Literal["stdio", "sse", "http", "unknown"]
    auth_present: bool


class McpResourceComponent(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str | None
    location: Location
    uri_template: str


class DocumentLoaderComponent(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str | None
    location: Location
    loader_kind: str
    path_or_url: str | None = None
    framework: FrameworkKind | None = None


class MemoryStoreComponent(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str | None
    location: Location
    store_kind: str
    scope_present: bool


class AgentHandoffComponent(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str | None
    location: Location
    target_hint: str | None = None
    allowlist_present: bool


class ParseErrorInfo(BaseModel):
    model_config = ConfigDict(extra="forbid")

    path: str
    message: str


class Inventory(BaseModel):
    model_config = ConfigDict(extra="forbid")

    target: str
    python_files: list[str] = Field(default_factory=list)
    agents: list[AgentComponent] = Field(default_factory=list)
    prompts: list[PromptComponent] = Field(default_factory=list)
    tools: list[ToolComponent] = Field(default_factory=list)
    mcp_servers: list[McpServerComponent] = Field(default_factory=list)
    mcp_resources: list[McpResourceComponent] = Field(default_factory=list)
    document_loaders: list[DocumentLoaderComponent] = Field(default_factory=list)
    memory_stores: list[MemoryStoreComponent] = Field(default_factory=list)
    agent_handoffs: list[AgentHandoffComponent] = Field(default_factory=list)
    parse_errors: list[ParseErrorInfo] = Field(default_factory=list)
