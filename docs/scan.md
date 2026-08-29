# ASTA Cloud scan reference

Local, offline, static analysis. Target code is never executed. Findings are **suspected**, not validated.

## CLI

```bash
asta scan TARGET [--config PATH] [--format json|sarif|text] [--output PATH] [--validate]
asta --version
asta --help
```

`TARGET` must be a local directory. URLs are rejected.

`--format` accepts `json` (default), `sarif`, or `text`. Any other value exits with code 2.

`--validate` re-reads parsed source files and independently confirms each finding at its reported line. Target code is **never executed**. Findings confirmed locally are marked `validated`; inconclusive findings stay `suspected`.

## Exit codes

- `0` — scan completed; no finding at or above `fail_on` (default `high`)
- `1` — scan completed; at least one finding at or above `fail_on`
- `2` — usage, config, path, or I/O error

`fail_on` uses **post-override** severities from config.

## Config (`asta.yaml`)

| Key | Default | Meaning |
| --- | --- | --- |
| `exclude` | `.git`, `.venv`, `venv`, `__pycache__`, `.mypy_cache`, `.ruff_cache`, `dist`, `build`, `node_modules`, `tests`, `unit_tests`, `integration_tests` | Path segment names to skip (any directory with that name) |
| `fail_on` | `high` | Minimum severity that yields exit code 1 |
| `enabled_rules` | all rules | Optional list of rule ids |
| `severity` | `{}` | Optional per-rule severity overrides (known rule ids only) |
| `validate` | `false` | Re-read source to confirm findings locally (never executes target code) |
| `max_file_bytes` | `1048576` | Skip larger Python files |

Example severity overrides:

```yaml
fail_on: high
severity:
  ASTA-SEC-004: high
  ASTA-SEC-008: low
```

Unknown keys are rejected. If `--config` is omitted, ASTA Cloud uses `TARGET/asta.yaml` when present, otherwise built-in defaults.

## Inventory (Milestone 2b)

Discovered agents, tools, and prompts may include an optional `framework` field:

- `langchain` — LangChain / LangChain Core patterns (`@tool`, `create_react_agent`, `AgentExecutor`, …)
- `openai_agents` — OpenAI Agents SDK patterns (`@function_tool`, `Agent`, `Runner`, …)
- `llamaindex` — LlamaIndex patterns (`FunctionTool`, `ReActAgent`, `QueryEngineTool`, …)

Framework hints come from imports, decorators, and call-site names. They do not execute framework code.

## Taint analysis (Milestone 2b)

Rules `ASTA-SEC-003` and `ASTA-SEC-008` use same-function taint tracking: tool parameters propagate through assignments, f-strings, and string concatenation before reaching sinks.

## Local validation (Milestone 3)

When `--validate` is passed (or `validate: true` in config), ASTA Cloud runs a second deterministic pass:

1. Re-read already-parsed modules (no new filesystem access outside the target).
2. For each finding, run a rule-specific AST check at the reported line.
3. Mark `validation_status` as `validated` only when the pattern is confirmed.

This does **not** import or execute the scanned application. It does not call an LLM or reach the network.

Without `--validate`, all findings remain `suspected` and `validation_performed` is `false`.

## MCP server scanning (Milestone 4a)

ASTA Cloud detects Python MCP servers built with **FastMCP** or the official **`mcp`** SDK. Inventory includes:

- `mcp_servers` — server name, SDK, inferred transport (`stdio`, `sse`, `http`), auth hints
- `mcp_resources` — resource URI templates from `@mcp.resource` / `@server.resource`
- MCP-tagged `tools` and `prompts` (`framework: mcp`)

Detection is AST-only: imports, `FastMCP` / `Server` instantiation, `@mcp.tool`, `@mcp.resource`, and transport calls such as `stdio_server`, `SseServerTransport`, or `uvicorn.run`.

## RAG scanning (Milestone 4b)

ASTA Cloud detects common Python RAG patterns from LangChain and LlamaIndex:

- `document_loaders` in inventory — loader kind and literal path/URL when available
- Retriever/index calls (`VectorStoreIndex`, `as_retriever`, `RetrievalQA`, `create_retrieval_chain`, …)

New rules cover broad document loader paths, user-controlled web loader URLs, and prompt templates that omit retrieved-context placeholders.

## Agent workflow scanning (Milestone 4c)

ASTA Cloud inventories agent memory stores, handoffs, and workflow patterns from LangChain and OpenAI Agents:

- `memory_stores` — buffer/history stores with scope hints (`session_id`, `user_id`, `tenant_id`, …)
- `agent_handoffs` — `handoff`, `transfer`, and delegation calls with target hints

Rules flag unscoped memory, privileged tools without permission checks, and unrestricted multi-agent handoffs.

## Report formats

### JSON

Top-level: `schema_version`, `product`, `scanned_at`, `target`, `config_path`, `validation_performed`, `notes`, `inventory`, `findings`, `summary`.

`validation_performed` is `true` only when `--validate` or `validate: true` was used.

Each finding includes: `instance_id`, `rule_id`, `title`, `description`, `severity`, `confidence`, `location` (`path`, `line`, `end_line`), `evidence` (`snippet`, optional `call_name`), `remediation`, `validation_status`, `owasp`.

### SARIF 2.1.0

CI-friendly output for GitHub Code Scanning and similar tools. Uses relative artifact URIs, maps severities to SARIF levels (`error` / `warning` / `note`), and includes `partialFingerprints.instanceId` for deduplication.

### Text

Grep-friendly lines:

```
path/to/file.py:12: high ASTA-SEC-002 <title>
  description: ...
  evidence: ...
  remediation: ...
  owasp: LLM08:2025
  validation: suspected
```

Secret values are redacted to `[REDACTED]` in all formats.

## Rule catalog

| Id | Title | Default severity | OWASP |
| --- | --- | --- | --- |
| `ASTA-SEC-001` | Hard-coded secrets or API keys | high | LLM06:2025 |
| `ASTA-SEC-002` | Agent tools containing dangerous shell execution | high | LLM08:2025 |
| `ASTA-SEC-003` | Tools executing user-controlled commands | high | LLM01:2025, LLM08:2025 |
| `ASTA-SEC-004` | Prompts requesting unrestricted tool use | medium | LLM08:2025, LLM01:2025 |
| `ASTA-SEC-005` | Missing tool allowlists | medium | LLM08:2025 |
| `ASTA-SEC-006` | Sensitive file access through agent tools | high | LLM06:2025 |
| `ASTA-SEC-007` | Dangerous subprocess usage | high | A03:2021 |
| `ASTA-SEC-008` | Overly broad filesystem access | medium | LLM08:2025 |
| `ASTA-SEC-009` | Overly broad MCP resource URI templates | medium | LLM08:2025 |
| `ASTA-SEC-010` | MCP network transport without visible authentication | high | LLM06:2025, LLM08:2025 |
| `ASTA-SEC-011` | Dangerous execution in MCP tools | high | LLM08:2025, LLM01:2025 |
| `ASTA-SEC-012` | Overly broad RAG document loader paths | medium | LLM06:2025, LLM08:2025 |
| `ASTA-SEC-013` | User-controlled URL in RAG web loader | high | LLM01:2025, LLM08:2025 |
| `ASTA-SEC-014` | RAG prompt missing document context separation | medium | LLM01:2025, LLM08:2025 |
| `ASTA-SEC-015` | Agent memory store without session scoping | medium | LLM06:2025, LLM08:2025 |
| `ASTA-SEC-016` | Privileged agent tool missing permission check | high | LLM08:2025, LLM06:2025 |
| `ASTA-SEC-017` | Unrestricted multi-agent handoff | medium | LLM08:2025, LLM01:2025 |
