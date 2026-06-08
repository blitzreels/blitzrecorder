#!/usr/bin/env python3
"""Generate exact App Store Connect field values from BlitzRecorder metadata."""

from __future__ import annotations

import json
import re
import argparse
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PATH = ROOT / "AppStore" / "AppStoreConnectFields.generated.json"

MAC_METADATA_PATH = ROOT / "AppStore" / "Metadata-macOS.md"
IOS_METADATA_PATH = ROOT / "AppStore" / "Metadata-iOS.md"
REVIEW_NOTES_PATH = ROOT / "AppStore" / "ReviewNotes.md"

MAC_BUNDLE_ID = "dev.blitzreels.blitzrecorder"
IOS_BUNDLE_ID = "dev.blitzreels.blitzrecorder.camera"
LANDING_URL = "https://blitzrecorder.com"
SUPPORT_URL = "https://blitzrecorder.com/support"
PRIVACY_URL = "https://blitzrecorder.com/privacy"
TERMS_URL = "https://blitzrecorder.com/terms"


def read(path: Path) -> str:
    if not path.exists():
        raise SystemExit(f"error: missing source file: {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8")


def section(markdown: str, heading: str) -> str:
    pattern = re.compile(
        rf"^## {re.escape(heading)}\s*\n(?P<body>.*?)(?=^## |\Z)",
        re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(markdown)
    if not match:
        raise SystemExit(f"error: missing metadata section: {heading}")
    return match.group("body").strip()


def first_value(markdown: str, heading: str) -> str:
    body = section(markdown, heading)
    for line in body.splitlines():
        value = line.strip()
        if value:
            return strip_inline_code(value)
    raise SystemExit(f"error: metadata section has no value: {heading}")


def strip_inline_code(value: str) -> str:
    if value.startswith("`") and value.endswith("`") and len(value) >= 2:
        return value[1:-1]
    return value


def app_fields(
    *,
    platform: str,
    metadata_path: Path,
    markdown: str,
    sku: str,
    category: str,
    screenshot_directories: list[str],
    companion_only: bool,
    initiates_purchases: bool,
) -> dict[str, Any]:
    app_name = first_value(markdown, "App Name")
    bundle_id = first_value(markdown, "Bundle ID")
    support_url = first_value(markdown, "Support URL")
    marketing_url = first_value(markdown, "Marketing URL")
    privacy_policy_url = first_value(markdown, "Privacy Policy URL")

    return {
        "platform": platform,
        "appName": app_name,
        "bundleId": bundle_id,
        "sku": sku,
        "primaryLocale": "en-US",
        "category": category,
        "subtitle": first_value(markdown, "Subtitle"),
        "promotionalText": first_value(markdown, "Promotional Text"),
        "description": section(markdown, "Description"),
        "keywords": first_value(markdown, "Keywords"),
        "supportUrl": support_url,
        "marketingUrl": marketing_url,
        "privacyPolicyUrl": privacy_policy_url,
        "termsUrl": TERMS_URL,
        "reviewNotes": section(markdown, "Review Notes"),
        "screenshotDirectories": screenshot_directories,
        "companionOnly": companion_only,
        "initiatesPurchases": initiates_purchases,
        "metadataSource": str(metadata_path.relative_to(ROOT)),
    }


def validate_fields(payload: dict[str, Any]) -> None:
    mac_app = payload["apps"]["macOS"]
    ios_app = payload["apps"]["iOS"]
    expected = [
        (mac_app["bundleId"], MAC_BUNDLE_ID, "macOS bundle ID"),
        (ios_app["bundleId"], IOS_BUNDLE_ID, "iOS bundle ID"),
    ]
    failures = [f"{label}: got {actual}, expected {expected}" for actual, expected, label in expected if actual != expected]

    for label, value, maximum in [
        ("macOS subtitle", mac_app["subtitle"], 30),
        ("iOS subtitle", ios_app["subtitle"], 30),
        ("macOS promotional text", mac_app["promotionalText"], 170),
        ("iOS promotional text", ios_app["promotionalText"], 170),
        ("macOS keywords", mac_app["keywords"], 100),
        ("iOS keywords", ios_app["keywords"], 100),
    ]:
        if len(value) > maximum:
            failures.append(f"{label} is {len(value)} characters, max is {maximum}")

    if not ios_app["companionOnly"]:
        failures.append("iOS companionOnly must be true")
    if ios_app["initiatesPurchases"]:
        failures.append("iOS initiatesPurchases must be false")
    if mac_app["initiatesPurchases"]:
        failures.append("macOS initiatesPurchases must be false")
    if payload["subscription"] is not None:
        failures.append("subscription must be null until the App Store product model is revisited")

    if failures:
        raise SystemExit("error: generated fields are invalid:\n- " + "\n- ".join(failures))


def build_payload() -> dict[str, Any]:
    mac_markdown = read(MAC_METADATA_PATH)
    ios_markdown = read(IOS_METADATA_PATH)

    return {
        "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "sourceFiles": [
            str(MAC_METADATA_PATH.relative_to(ROOT)),
            str(IOS_METADATA_PATH.relative_to(ROOT)),
            str(REVIEW_NOTES_PATH.relative_to(ROOT)),
        ],
        "urls": {
            "landing": LANDING_URL,
            "support": SUPPORT_URL,
            "privacyPolicy": PRIVACY_URL,
            "terms": TERMS_URL,
        },
        "apps": {
            "macOS": app_fields(
                platform="macOS",
                metadata_path=MAC_METADATA_PATH,
                markdown=mac_markdown,
                sku="BLITZRECORDER-MAC",
                category="Photo & Video",
                screenshot_directories=["AppStore/ScreenshotAssets/macOS"],
                companion_only=False,
                initiates_purchases=False,
            ),
            "iOS": app_fields(
                platform="iOS",
                metadata_path=IOS_METADATA_PATH,
                markdown=ios_markdown,
                sku="BLITZRECORDER-CAMERA-IOS",
                category="Photo & Video",
                screenshot_directories=[
                    "AppStore/ScreenshotAssets/iPhone-6.9",
                    "AppStore/ScreenshotAssets/iPad-13",
                ],
                companion_only=True,
                initiates_purchases=False,
            ),
        },
        "subscription": None,
    }


def comparable_payload(payload: dict[str, Any]) -> dict[str, Any]:
    comparable = dict(payload)
    comparable.pop("generatedAt", None)
    return comparable


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate exact BlitzRecorder App Store Connect field values.")
    parser.add_argument("--check", action="store_true", help="Verify the generated JSON matches metadata without rewriting it.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    payload = build_payload()

    validate_fields(payload)
    if args.check:
        if not OUTPUT_PATH.exists():
            raise SystemExit(f"error: missing generated file: {OUTPUT_PATH.relative_to(ROOT)}")
        existing = json.loads(OUTPUT_PATH.read_text(encoding="utf-8"))
        if comparable_payload(existing) != comparable_payload(payload):
            raise SystemExit(f"error: {OUTPUT_PATH.relative_to(ROOT)} is stale; run Scripts/generate-app-store-connect-fields.py")
        print(f"Verified {OUTPUT_PATH.relative_to(ROOT)}")
        return 0

    OUTPUT_PATH.write_text(json.dumps(payload, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    print(f"Generated {OUTPUT_PATH.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
