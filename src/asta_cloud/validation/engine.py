from __future__ import annotations

from asta_cloud.discovery.parse import ParsedModule
from asta_cloud.models.enums import ValidationStatus
from asta_cloud.models.finding import Finding
from asta_cloud.validation.checks import RULE_CHECKERS
from asta_cloud.validation.helpers import module_for_path


def validate_findings(
    modules: list[ParsedModule],
    findings: list[Finding],
) -> tuple[list[Finding], dict[str, int]]:
    """Re-read parsed modules and independently confirm each finding at its location."""
    counts = {
        ValidationStatus.VALIDATED.value: 0,
        ValidationStatus.SUSPECTED.value: 0,
        ValidationStatus.NOT_APPLICABLE.value: 0,
    }
    updated: list[Finding] = []

    for finding in findings:
        status = _validate_one(modules, finding)
        counts[status.value] += 1
        updated.append(finding.model_copy(update={"validation_status": status}))

    return updated, counts


def _validate_one(modules: list[ParsedModule], finding: Finding) -> ValidationStatus:
    checker = RULE_CHECKERS.get(finding.rule_id)
    if checker is None:
        return ValidationStatus.NOT_APPLICABLE

    module = module_for_path(modules, finding.location.path)
    if module is None or module.tree is None:
        return ValidationStatus.SUSPECTED

    if finding.location.line is None:
        return ValidationStatus.SUSPECTED

    if checker(module.tree, finding.location.line):
        return ValidationStatus.VALIDATED
    return ValidationStatus.SUSPECTED
