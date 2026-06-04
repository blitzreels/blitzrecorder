#!/usr/bin/env python3
"""Print App Store Connect setup guidance for the free BlitzRecorder release."""

from __future__ import annotations

import argparse


MAC_BUNDLE_ID = "dev.blitzreels.blitzrecorder"
IOS_BUNDLE_ID = "dev.blitzreels.blitzrecorder.camera"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Show BlitzRecorder App Store Connect setup guidance.")
    parser.add_argument("--apply", action="store_true", help="Kept for compatibility; no resources are created.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.apply:
        print("No App Store Connect resources were created. BlitzRecorder has no IAP or subscriptions.")
    else:
        print("Dry run: BlitzRecorder App Store Connect setup")

    print(f"- macOS bundle ID: {MAC_BUNDLE_ID}")
    print(f"- iOS companion bundle ID: {IOS_BUNDLE_ID}")
    print("- Price: free")
    print("- In-app purchases: none")
    print("- Subscriptions: none")
    print("- Create app records manually in App Store Connect, then paste metadata from AppStore/Metadata-*.md.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
