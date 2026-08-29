# Share ASTA Cloud v0.10.0

## One-liner

**ASTA Cloud** — static security scans for LangChain, OpenAI Agents, MCP, and RAG Python code in every PR.

## Links

| | |
| --- | --- |
| Landing page | https://narendranadh6.github.io/asta-cloud/ |
| GitHub | https://github.com/narendranadh6/asta-cloud |
| PyPI | https://pypi.org/project/asta-cloud/0.10.0/ |
| Integration guide | https://github.com/narendranadh6/asta-cloud/blob/main/docs/github-integration.md |

## Install

```bash
pip install asta-cloud==0.10.0
asta scan . --config asta.yaml --format text
```

## GitHub Action (copy into `.github/workflows/asta.yml`)

```yaml
name: ASTA Security

on:
  pull_request:
    branches: [main]

permissions:
  contents: read
  pull-requests: write

jobs:
  asta:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: narendranadh6/asta-cloud/action@v0.10.0
        with:
          path: .
          config: asta.yaml
          post-comment: true
```

## Social post

```
Shipped ASTA Cloud v0.10 — SAST built for AI agent code.

• Tools, memory, handoffs, MCP, RAG patterns
• GitHub Action: PR comments + policy gate
• Baseline adoption for real repos (not just greenfield)

pip install asta-cloud==0.10.0
https://narendranadh6.github.io/asta-cloud/
```
