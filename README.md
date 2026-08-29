# ASTA Cloud

Evidence-first security testing for AI agents, RAG applications, MCP servers, prompts, tools, memory, permissions, and agent workflows.

The first product is a **local Python CLI**. It is not a SaaS application and does not call an LLM.

## Authorized use only

ASTA Cloud scans **local directories you explicitly supply**. Use it only on systems and code you are authorized to test. It never executes the scanned application, never follows symlinks outside the target directory, and never transmits findings or secrets.

## Install

```bash
python -m pip install asta-cloud
```

For local development:

```bash
python -m pip install -e ".[dev]"
```

Requires Python 3.11 or newer.

### Docker (GHCR)

```bash
docker run --rm -v "$PWD:/target:ro" ghcr.io/narendranadh6/asta-cloud:latest \
  scan /target --format text
```

Images publish to GitHub Container Registry on each GitHub release.

PyPI packages publish on each GitHub release as well (`pip install asta-cloud`). Maintainer setup: [docs/publishing.md](docs/publishing.md).

**Landing page:** [docs/index.html](docs/index.html) · **GitHub PR policy:** [docs/github-integration.md](docs/github-integration.md) · **Design partners:** [docs/design-partner/README.md](docs/design-partner/README.md)

## CI

GitHub Actions runs `ruff`, `mypy`, `pytest` (Python 3.11 and 3.12), generates a SARIF report from `examples/vulnerable_agent`, verifies the Docker image, and runs the ASTA PR policy action on pull requests. See [`.github/workflows/ci.yml`](.github/workflows/ci.yml) and [docs/github-integration.md](docs/github-integration.md).

## GitHub PR policy

Add the composite Action to fail PRs when findings meet `fail_on` in `asta.yaml`:

```yaml
- uses: narendranadh6/asta-cloud/action@v0.10.0
  with:
    path: .
    config: asta.yaml
    post-comment: true
```

Copy [`templates/github-action-workflow.yml`](templates/github-action-workflow.yml) or see [docs/github-integration.md](docs/github-integration.md) for baseline, SARIF, and reusable workflows.

## Scan

```bash
asta scan ./examples/vulnerable_agent \
  --config asta.yaml \
  --format json \
  --output results.json
```

Omit `--output` to print to stdout. `--format` accepts `json` (default), `sarif`, or `text`.

```bash
# SARIF for CI / GitHub Code Scanning
asta scan ./examples/vulnerable_agent --format sarif --output results.sarif

# Grep-friendly text
asta scan ./examples/vulnerable_agent --format text

# Confirm findings locally (never executes target code)
asta scan ./examples/vulnerable_agent --validate --format json

# Adopt in CI with a baseline (fail only on new findings)
asta scan ./examples/vulnerable_agent --baseline asta-baseline.json --update-baseline
asta scan ./examples/vulnerable_agent --baseline asta-baseline.json --format sarif

# Scan an MCP server example
asta scan ./examples/vulnerable_mcp_server --format json

# Scan a RAG application example
asta scan ./examples/vulnerable_rag_app --format json

# Scan an agent workflow example
asta scan ./examples/vulnerable_workflow_app --format json
```

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Scan finished; no findings at or above `fail_on` (default: `high`) |
| 1 | Scan finished; at least one finding at or above `fail_on` |
| 2 | Usage, config, path, or I/O error |

## Security boundaries

- Scan only the directory you pass as `TARGET`.
- Never scan URLs or internet targets.
- Never execute target code (`ast.parse` only).
- Never read files outside the target (except an explicitly passed `--config`).
- Never follow symlinks that resolve outside the target.
- Redact secret values in reports. Do not collect or transmit secrets.
- All findings are **suspected**. ASTA Cloud does not claim a vulnerability was validated unless a later validation step actually ran.

See [docs/scan.md](docs/scan.md) for framework detection, taint analysis, rule catalog, config keys, and report formats.
