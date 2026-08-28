from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from asta_cloud.models.finding import Finding
from asta_cloud.models.inventory import Inventory


class Summary(BaseModel):
    model_config = ConfigDict(extra="forbid")

    files_scanned: int
    findings_by_severity: dict[str, int]
    high_or_above: int


class ScanReport(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schema_version: str
    product: str
    scanned_at: datetime
    target: str
    config_path: str | None
    validation_performed: bool
    notes: list[str] = Field(default_factory=list)
    inventory: Inventory
    findings: list[Finding] = Field(default_factory=list)
    summary: Summary
