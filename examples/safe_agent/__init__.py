"""Canary: importing this package must fail. ASTA Cloud parses files with ast only."""

raise RuntimeError("ASTA Cloud must not import scanned packages")
