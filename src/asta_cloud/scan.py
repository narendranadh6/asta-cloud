from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path

from asta_cloud.analyzers.context import ScanContext
from asta_cloud.baseline import (
    BaselineError,
    apply_baseline,
    load_baseline,
    resolve_baseline_path,
    save_baseline,
)
from asta_cloud.config import ConfigError, load_config
from asta_cloud.discovery.files import collect_python_files
from asta_cloud.discovery.inventory import build_inventory
from asta_cloud.discovery.parse import parse_modules
from asta_cloud.models.enums import SEVERITY_RANK, Severity
from asta_cloud.models.finding import Finding
from asta_cloud.models.report import ScanReport, Summary
from asta_cloud.rules.registry import UnknownRuleError, enabled_rules
from asta_cloud.security.paths import PathSafetyError, resolve_scan_root
from asta_cloud.security.redact import redact_inventory, redact_report
from asta_cloud.validation.engine import validate_findings

PRODUCT = "asta-cloud"
SCHEMA_VERSION = "1.0.0"
NO_VALIDATION_NOTE = (
    "No runtime validation was performed and target code was not executed."
)


class ScanError(Exception):
    """User-facing scan failure (CLI exit 2)."""


def run_scan(
    target: str | Path,
    config_path: str | Path | None = None,
    output_path: str | Path | None = None,
    validate_override: bool | None = None,
    baseline_path: str | Path | None = None,
    update_baseline: bool = False,
) -> tuple[ScanReport, bool]:
    try:
        root = resolve_scan_root(target)
    except PathSafetyError as exc:
        raise ScanError(str(exc)) from exc

    explicit = Path(config_path) if config_path is not None else None
    try:
        config, used_config = load_config(explicit, root)
    except ConfigError as exc:
        raise ScanError(str(exc)) from exc

    skip: set[Path] = set()
    if output_path is not None:
        skip.add(Path(output_path).expanduser().resolve())

    files, notes = collect_python_files(root, config, skip_resolved=skip)
    modules = parse_modules(root, files)
    inventory = build_inventory(root, modules)
    for error in inventory.parse_errors:
        notes.append(f"parse error in {error.path}: {error.message}")

    should_validate = (
        validate_override if validate_override is not None else config.enable_validation
    )

    ctx = ScanContext(root=root, config=config, modules=modules, inventory=inventory, notes=notes)
    try:
        rules = enabled_rules(config)
    except UnknownRuleError as exc:
        raise ScanError(str(exc)) from exc

    findings: list[Finding] = []
    for rule in rules:
        findings.extend(rule.check(ctx))
    findings = _dedupe_007(findings)
    findings = _dedupe_011(findings)
    findings = _apply_severity_overrides(findings, config.severity)

    if should_validate:
        findings, validation_counts = validate_findings(modules, findings)
        notes.append(
            "Local validation performed without executing target code: "
            f"{validation_counts['validated']} validated, "
            f"{validation_counts['suspected']} suspected, "
            f"{validation_counts['not_applicable']} not applicable."
        )
        validation_performed = True
    else:
        notes.append(NO_VALIDATION_NOTE)
        validation_performed = False

    effective_baseline = baseline_path if baseline_path is not None else config.baseline
    if update_baseline:
        if effective_baseline is None:
            raise ScanError(
                "A baseline path is required when using --update-baseline "
                "(pass --baseline or set baseline in asta.yaml)."
            )
        resolved_baseline = resolve_baseline_path(root, effective_baseline)
        save_baseline(resolved_baseline, findings)
        notes.append(
            f"Baseline written to {resolved_baseline} with {len(findings)} finding(s)."
        )
    elif effective_baseline is not None:
        resolved_baseline = resolve_baseline_path(root, effective_baseline)
        try:
            baseline = load_baseline(resolved_baseline)
        except BaselineError as exc:
            raise ScanError(str(exc)) from exc
        findings, suppressed = apply_baseline(findings, baseline)
        if suppressed:
            notes.append(
                f"{suppressed} finding(s) suppressed by baseline {resolved_baseline}."
            )

    inventory = redact_inventory(inventory)
    report = ScanReport(
        schema_version=SCHEMA_VERSION,
        product=PRODUCT,
        scanned_at=datetime.now(UTC),
        target=str(root),
        config_path=str(used_config) if used_config is not None else None,
        validation_performed=validation_performed,
        notes=notes,
        inventory=inventory,
        findings=findings,
        summary=_summary(len(files), findings),
    )
    report = redact_report(report)
    if update_baseline:
        return report, False
    failed = _meets_fail_on(report.findings, config.fail_on)
    return report, failed


def _apply_severity_overrides(
    findings: list[Finding],
    overrides: dict[str, Severity],
) -> list[Finding]:
    if not overrides:
        return findings
    updated: list[Finding] = []
    for finding in findings:
        override = overrides.get(finding.rule_id)
        if override is None:
            updated.append(finding)
        else:
            updated.append(finding.model_copy(update={"severity": override}))
    return updated


def _dedupe_011(findings: list[Finding]) -> list[Finding]:
    reported = {
        (item.location.path, item.location.line)
        for item in findings
        if item.rule_id == "ASTA-SEC-002"
    }
    kept: list[Finding] = []
    for item in findings:
        if item.rule_id == "ASTA-SEC-011" and (item.location.path, item.location.line) in reported:
            continue
        kept.append(item)
    return kept


def _dedupe_007(findings: list[Finding]) -> list[Finding]:
    reported = {
        (item.location.path, item.location.line)
        for item in findings
        if item.rule_id == "ASTA-SEC-002"
    }
    kept: list[Finding] = []
    for item in findings:
        if item.rule_id == "ASTA-SEC-007" and (item.location.path, item.location.line) in reported:
            continue
        kept.append(item)
    return kept


def _summary(files_scanned: int, findings: list[Finding]) -> Summary:
    counts = {severity.value: 0 for severity in Severity}
    for item in findings:
        counts[item.severity.value] += 1
    high_or_above = counts[Severity.HIGH.value] + counts[Severity.CRITICAL.value]
    return Summary(
        files_scanned=files_scanned,
        findings_by_severity=counts,
        high_or_above=high_or_above,
    )


def _meets_fail_on(findings: list[Finding], fail_on: Severity) -> bool:
    threshold = SEVERITY_RANK[fail_on]
    return any(SEVERITY_RANK[item.severity] >= threshold for item in findings)
