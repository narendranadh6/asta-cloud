from pydantic import BaseModel, ConfigDict, Field

from asta_cloud.models.enums import Confidence, Severity, ValidationStatus
from asta_cloud.models.location import Location


class Evidence(BaseModel):
    model_config = ConfigDict(extra="forbid")

    snippet: str
    call_name: str | None = None


class Finding(BaseModel):
    model_config = ConfigDict(extra="forbid")

    instance_id: str
    rule_id: str
    title: str
    description: str
    severity: Severity
    confidence: Confidence
    location: Location
    evidence: Evidence
    remediation: str
    validation_status: ValidationStatus
    owasp: list[str] = Field(default_factory=list)
