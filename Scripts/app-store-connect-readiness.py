#!/usr/bin/env python3
"""Verify local App Store Connect readiness for the free BlitzRecorder release."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


MAC_BUNDLE_ID = "dev.blitzreels.blitzrecorder"
IOS_BUNDLE_ID = "dev.blitzreels.blitzrecorder.camera"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Verify BlitzRecorder App Store Connect readiness.")
    parser.add_argument("--dry-run", action="store_true", help="Accepted for compatibility; only local checks run.")
    parser.add_argument("--api-base", default="https://api.appstoreconnect.apple.com", help="Accepted for compatibility.")
    parser.add_argument("--price-territory", default="USA", help="Accepted for compatibility.")
    parser.add_argument("--expected-price", default="0", help="Accepted for compatibility.")
    return parser.parse_args()


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def require(path: Path) -> None:
    if not path.exists():
        fail(f"missing {path}")


def reject_text(path: Path, text: str) -> None:
    if text in path.read_text(encoding="utf-8"):
        fail(f"{path} still contains {text!r}")


def main() -> int:
    _ = parse_args()
    root = Path(__file__).resolve().parents[1]
    fields_path = root / "AppStore/AppStoreConnectFields.generated.json"
    require(fields_path)
    fields = json.loads(fields_path.read_text(encoding="utf-8"))

    if fields["apps"]["macOS"]["bundleId"] != MAC_BUNDLE_ID:
        fail("macOS bundle ID mismatch")
    if fields["apps"]["iOS"]["bundleId"] != IOS_BUNDLE_ID:
        fail("iOS bundle ID mismatch")
    if fields["apps"]["macOS"]["initiatesPurchases"]:
        fail("macOS app must not initiate purchases")
    if fields["apps"]["iOS"]["initiatesPurchases"]:
        fail("iOS app must not initiate purchases")
    if fields.get("subscription") is not None:
        fail("subscription payload must be null")

    reject_text(root / "project.yml", "storeKitConfiguration")
    reject_text(root / "AppStore/Metadata-macOS.md", "$7.99")
    reject_text(root / "AppStore/ReviewNotes.md", "BlitzRecorder Pro")

    print("App Store Connect local readiness passed for free/no-IAP release.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
