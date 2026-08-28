from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from asta_cloud.config import ScanConfig
from asta_cloud.discovery.parse import ParsedModule
from asta_cloud.models.inventory import Inventory


@dataclass
class ScanContext:
    root: Path
    config: ScanConfig
    modules: list[ParsedModule]
    inventory: Inventory
    notes: list[str] = field(default_factory=list)

    def module_by_relative(self, relative: str) -> ParsedModule | None:
        for module in self.modules:
            if module.relative == relative:
                return module
        return None
