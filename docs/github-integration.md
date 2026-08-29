# GitHub integration

ASTA Cloud ships a **composite GitHub Action** for pull-request policy gates today. A hosted **GitHub App** (org-wide install, central policy) is the next commercial step.

## Quick start (any repo)

Add `.github/workflows/asta.yml`:

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
          baseline: asta-baseline.json
          post-comment: true
          upload-sarif: true
```

## Policy model

Policy is defined in `asta.yaml`:

```yaml
fail_on: high
baseline: asta-baseline.json
severity:
  ASTA-SEC-008: low
```

| Control | Behavior |
| --- | --- |
| `fail_on` | PR check fails when findings meet or exceed this severity |
| `baseline` | Suppress known findings; fail only on **new** issues |
| `severity` | Per-rule overrides before `fail_on` is evaluated |

### Baseline workflow

```bash
# One-time: snapshot known issues
asta scan . --baseline asta-baseline.json --update-baseline
git add asta-baseline.json && git commit -m "Add ASTA baseline"

# CI uses baseline automatically via asta.yaml
```

## What the PR comment includes

- Pass/fail against policy
- Files scanned and severity counts
- Top rules and sample findings
- Updated in place on each push (no comment spam)

## Action inputs

| Input | Default | Description |
| --- | --- | --- |
| `path` | `.` | Scan target directory |
| `config` | `""` | Path to `asta.yaml` |
| `baseline` | `""` | Baseline JSON (overrides config if both set) |
| `post-comment` | `true` | PR summary comment |
| `upload-sarif` | `false` | Attach SARIF artifact |
| `python-version` | `3.12` | Python for `pip install asta-cloud` |

## Reusable workflow (monorepos)

```yaml
jobs:
  asta:
    uses: narendranadh6/asta-cloud/.github/workflows/asta-reusable-pr-scan.yml@v0.10.0
    with:
      path: libs/my-agent
      baseline: asta-baseline.json
```

## GitHub App roadmap (paid tier)

The Action covers **per-repo CI**. The **GitHub App** adds:

- One-click org install across all repositories
- Central policy templates and exceptions
- Audit log and posture dashboard
- Design-partner pilots: see [design-partner kit](design-partner/README.md)

Phase 1 (now): Action + policy file + baseline  
Phase 2 (commercial): GitHub App + hosted policy API

## Security notes

- Uses `GITHUB_TOKEN` with `pull-requests: write` only for comments
- Scans run locally in the runner; code is not sent to ASTA servers
- SARIF upload is optional and stays in your GitHub org
