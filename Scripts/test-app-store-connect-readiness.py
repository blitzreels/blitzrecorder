#!/usr/bin/env python3
"""Smoke test for App Store Connect readiness."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    result = subprocess.run(
        [sys.executable, str(ROOT / "Scripts/app-store-connect-readiness.py"), "--dry-run"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        return result.returncode
    assert "free/no-IAP release" in result.stdout
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
