# Publishing ASTA Cloud

Releases publish artifacts to **PyPI** and **GHCR** when a GitHub release is published.

## Workflows

| Workflow | File | Trigger |
| --- | --- | --- |
| CI | `.github/workflows/ci.yml` | push / pull_request |
| Publish Docker | `.github/workflows/publish-docker.yml` | release published, manual |
| Publish PyPI | `.github/workflows/publish-pypi.yml` | release published, manual |

## One-time PyPI setup (trusted publishing)

ASTA Cloud uses [PyPI trusted publishing](https://docs.pypi.org/trusted-publishers/) (OIDC). No long-lived API token is stored in GitHub.

1. Create the PyPI project (first release only):
   - Option A: run **Publish PyPI** manually after step 2; PyPI creates the project on first upload.
   - Option B: register `asta-cloud` on [pypi.org](https://pypi.org) first.

2. On PyPI → **Account settings** → **Publishing** → **Add a new pending publisher**:
   - **PyPI Project Name:** `asta-cloud`
   - **Owner:** `narendranadh6`
   - **Repository name:** `asta-cloud`
   - **Workflow name:** `publish-pypi.yml`
   - **Environment name:** `pypi`

3. On GitHub → repo **Settings** → **Environments** → **New environment** → name it `pypi` (no secrets required for trusted publishing).

4. Create a GitHub release (or re-run **Publish PyPI** via Actions → workflow_dispatch).

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
