from __future__ import annotations

from pathlib import Path
from typing import Annotated

import typer

from asta_cloud import __version__
from asta_cloud.reporting import SUPPORTED_FORMATS, write_report
from asta_cloud.scan import ScanError, run_scan

app = typer.Typer(
    name="asta",
    help="ASTA Cloud — local evidence-first security scanner for AI agents.",
    no_args_is_help=True,
    add_completion=False,
)


def _version_callback(value: bool) -> None:
    if value:
        typer.echo(__version__)
        raise typer.Exit(0)


@app.callback()
def _root(
    version: Annotated[
        bool,
        typer.Option(
            "--version",
            help="Show version and exit.",
            callback=_version_callback,
            is_eager=True,
        ),
    ] = False,
) -> None:
    """ASTA Cloud CLI."""


@app.command()
def scan(
    target: Annotated[
        Path,
        typer.Argument(help="Local directory to scan (never a URL)."),
    ],
    config: Annotated[
        Path | None,
        typer.Option("--config", help="Path to asta.yaml."),
    ] = None,
    report_format: Annotated[
        str,
        typer.Option("--format", help="Report format: json, sarif, or text."),
    ] = "json",
    output: Annotated[
        Path | None,
        typer.Option("--output", help="Write the report to this file instead of stdout."),
    ] = None,
    validate: Annotated[
        bool | None,
        typer.Option(
            "--validate/--no-validate",
            help="Re-read source and confirm findings locally (never executes target code).",
        ),
    ] = None,
    baseline: Annotated[
        Path | None,
        typer.Option(
            "--baseline",
            help="JSON baseline file; matching findings are suppressed from fail_on.",
        ),
    ] = None,
    update_baseline: Annotated[
        bool,
        typer.Option(
            "--update-baseline",
            help="Write current findings to the baseline file and exit 0.",
        ),
    ] = False,
) -> None:
    """Statically scan a local Python repository for AI-agent security issues."""
    if report_format not in SUPPORTED_FORMATS:
        supported = ", ".join(sorted(SUPPORTED_FORMATS))
        typer.secho(
            f"Unsupported format {report_format!r}. Supported formats: {supported}.",
            err=True,
        )
        raise typer.Exit(2)

    try:
        report, failed = run_scan(
            target,
            config_path=config,
            output_path=output,
            validate_override=validate,
            baseline_path=baseline,
            update_baseline=update_baseline,
        )
    except ScanError as exc:
        typer.secho(str(exc), err=True)
        raise typer.Exit(2) from exc

    text = write_report(report, report_format, output)
    if output is None:
        typer.echo(text, nl=False)
    raise typer.Exit(1 if failed else 0)
