"""The synthetic ranking benchmark runs, is reproducible, and keeps hard constraints."""

from __future__ import annotations

from app.tools.ranking_benchmark import run


async def test_benchmark_is_reproducible_and_never_breaks_constraints() -> None:
    first = await run(quick=True)
    assert first == await run(quick=True)
    assert first["synthetic"] is True
    versions = first["versions"]
    for summary in versions.values():
        assert summary["constraint_violations"] == 0
        assert summary["turns"] > 0
    # session-v4's tuned weights: at least as relevant as v3, with fewer skips (synthetic).
    assert versions["session-v4"]["relevance_at_10"] >= versions["session-v3"]["relevance_at_10"]
    assert versions["session-v4"]["skip_rate"] <= versions["session-v3"]["skip_rate"]
    # Flow 2.0's spacing: fewer back-to-back repeats of one artist than v2.
    assert (
        versions["session-v3"]["adjacent_same_artist"]
        <= versions["session-v2"]["adjacent_same_artist"]
    )
