from pathlib import Path

import pytest

from asta_cloud.analyzers.context import ScanContext
from asta_cloud.config import ScanConfig
from asta_cloud.discovery.inventory import build_inventory
from asta_cloud.discovery.parse import parse_modules

REPO_ROOT = Path(__file__).resolve().parents[1]
FIXTURES = Path(__file__).resolve().parent / "fixtures"
EXAMPLES = REPO_ROOT / "examples"


@pytest.fixture
def fixtures_dir() -> Path:
    return FIXTURES


def context_from_file(path: Path) -> ScanContext:
    root = path.parent
    modules = parse_modules(root, [path.resolve()])
    inventory = build_inventory(root, modules)
    return ScanContext(root=root, config=ScanConfig(), modules=modules, inventory=inventory)
