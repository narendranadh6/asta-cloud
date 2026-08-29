# Publishing ASTA Cloud

Releases publish artifacts to **PyPI** and **GHCR** when a GitHub release is published.

## Workflows

| Workflow | File | Trigger |
| --- | --- | --- |
| CI | `.github/workflows/ci.yml` | push / pull_request |
| Publish Docker | `.github/workflows/publish-docker.yml` | release published, manual |
| Publish PyPI | `.github/workflows/publish-pypi.yml` | release published, manual |

## One-time PyPI setup

Choose **one** of these options.

### Option A: API token (fastest)

1. On PyPI → **Account settings** → **API tokens** → **Add API token**
   - Scope: entire account (first upload) or project `asta-cloud`
   - Copy the token (`pypi-...`)
2. On GitHub → repo **Settings** → **Secrets and variables** → **Actions** → **New repository secret**
   - Name: `PYPI_API_TOKEN`
   - Value: the token
3. Re-run **Publish PyPI** in Actions.

### Option B: Trusted publishing (no stored token)

1. On PyPI → **Account settings** → **Publishing** → **Add a new pending publisher**:
   - **PyPI Project Name:** `asta-cloud`
   - **Owner:** `narendranadh6`
   - **Repository name:** `asta-cloud`
   - **Workflow name:** `publish-pypi.yml`
   - **Environment name:** leave blank
2. Re-run **Publish PyPI** in Actions.

Do **not** set `PYPI_API_TOKEN` if using trusted publishing only.

## Release checklist

1. Bump `version` in `pyproject.toml` and `src/asta_cloud/__init__.py`.
2. Run tests locally: `pytest -q`, `ruff check .`, `mypy src`.
3. Commit and push to `main`.
4. Tag and push: `git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z`.
5. Create GitHub release from the tag (triggers PyPI + GHCR publish).

## Manual publish

```bash
python -m pip install build
python -m build
# Upload with twine if needed locally (prefer GitHub Actions in production)
```

## GHCR

Docker images publish to `ghcr.io/narendranadh6/asta-cloud`. Make the package **public** under GitHub Packages if you want unauthenticated pulls.
