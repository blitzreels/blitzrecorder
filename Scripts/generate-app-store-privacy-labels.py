#!/usr/bin/env python3
"""Generate exact App Store privacy nutrition label answers for BlitzRecorder."""

from __future__ import annotations

import argparse
import json
import plistlib
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SOURCE_PATH = ROOT / "AppStore" / "PrivacyNutritionLabels.md"
MAC_PRIVACY_MANIFEST = ROOT / "Sources" / "BlitzRecorderApp" / "PrivacyInfo.xcprivacy"
IOS_PRIVACY_MANIFEST = ROOT / "Apps" / "iOSCamera" / "Resources" / "PrivacyInfo.xcprivacy"
OUTPUT_PATH = ROOT / "AppStore" / "PrivacyNutritionLabels.generated.json"

MAC_BUNDLE_ID = "dev.blitzreels.blitzrecorder"
IOS_BUNDLE_ID = "dev.blitzreels.blitzrecorder.camera"

REQUIRED_SOURCE_SNIPPETS = [
    "Tracking: No.",
    "Third-party advertising: No.",
    "Data broker sharing: No.",
    "Data Used to Track You: No",
    "Data Linked to You: No",
    "Data Collected: No",
    "No account is required to record or export.",
    "Microphone: can include iPhone microphone audio",
    "NSPrivacyAccessedAPICategoryDiskSpace",
    "Sources/BlitzRecorderApp/PrivacyInfo.xcprivacy",
    "Apps/iOSCamera/Resources/PrivacyInfo.xcprivacy",
]


def read_text(path: Path) -> str:
    if not path.exists():
        raise SystemExit(f"error: missing source file: {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8")


def read_plist(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise SystemExit(f"error: missing privacy manifest: {path.relative_to(ROOT)}")
    with path.open("rb") as handle:
        return plistlib.load(handle)


def accessed_api_categories(manifest: dict[str, Any]) -> list[str]:
    categories: list[str] = []
    for item in manifest.get("NSPrivacyAccessedAPITypes", []):
        category = item.get("NSPrivacyAccessedAPIType")
        if category:
            categories.append(category)
    return sorted(categories)


def build_payload() -> dict[str, Any]:
    mac_manifest = read_plist(MAC_PRIVACY_MANIFEST)
    ios_manifest = read_plist(IOS_PRIVACY_MANIFEST)

    return {
        "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "sourceFiles": [
            str(SOURCE_PATH.relative_to(ROOT)),
            str(MAC_PRIVACY_MANIFEST.relative_to(ROOT)),
            str(IOS_PRIVACY_MANIFEST.relative_to(ROOT)),
        ],
        "shared": {
            "tracking": False,
            "thirdPartyAdvertising": False,
            "dataBrokerSharing": False,
            "recordingsUploadedByDefault": False,
            "localNetworkTrafficCollectedByDeveloper": False,
            "storeKitHandlesPurchases": False,
            "supportDataOnlyIfUserContactsSupport": True,
        },
        "apps": {
            "macOS": {
                "bundleId": MAC_BUNDLE_ID,
                "dataUsedToTrackYou": False,
                "dataLinkedToYou": False,
                "dataNotLinkedToYou": False,
                "collectedDataTypes": [],
                "notCollectedDataTypes": [
                    "Purchase History",
                    "Photos or Videos",
                    "Audio Data",
                    "Crash Data",
                    "Performance Data",
                    "Product Interaction",
                    "Email Address",
                ],
                "permissions": {
                    "camera": "Records the selected local camera source.",
                    "microphone": "Records selected microphone audio and may support local transcription-based file naming.",
                    "screenAndSystemAudioRecording": "Records selected screen and system audio sources.",
                    "speechRecognition": "Supports local transcription-based file naming.",
                    "localNetworkBonjour": "Discovers and pairs with BlitzRecorder Camera on iPhone or iPad.",
                    "userSelectedFileAccess": "Saves recordings and exports in the output folder the user chooses.",
                },
                "privacyManifest": {
                    "path": str(MAC_PRIVACY_MANIFEST.relative_to(ROOT)),
                    "tracking": bool(mac_manifest.get("NSPrivacyTracking", False)),
                    "collectedDataTypes": mac_manifest.get("NSPrivacyCollectedDataTypes", []),
                    "accessedAPITypes": accessed_api_categories(mac_manifest),
                },
            },
            "iOS": {
                "bundleId": IOS_BUNDLE_ID,
                "dataUsedToTrackYou": False,
                "dataLinkedToYou": False,
                "dataNotLinkedToYou": False,
                "dataCollected": False,
                "collectedDataTypes": [],
                "notCollectedDataTypes": [
                    "Photos or Videos",
                    "Crash Data",
                    "Performance Data",
                    "Product Interaction",
                    "Device ID",
                ],
                "permissions": {
                    "camera": "Captures the iPhone/iPad camera source selected by the user.",
                    "localNetworkBonjour": "Pairs with the Mac, sends monitor preview and camera telemetry, receives camera controls, and transfers local camera recordings.",
                    "microphone": "Can include iPhone microphone audio in the source camera file when recording starts.",
                },
                "privacyManifest": {
                    "path": str(IOS_PRIVACY_MANIFEST.relative_to(ROOT)),
                    "tracking": bool(ios_manifest.get("NSPrivacyTracking", False)),
                    "collectedDataTypes": ios_manifest.get("NSPrivacyCollectedDataTypes", []),
                    "accessedAPITypes": accessed_api_categories(ios_manifest),
                },
            },
        },
        "reviewTriggers": [
            "Analytics, crash reporting, logging upload, customer support upload, receipt validation, or account telemetry is added.",
            "Account, purchase, entitlement, analytics, or cloud upload flows are added.",
            "Recordings, thumbnails, transcripts, or logs are uploaded for any app feature.",
        ],
    }


def validate_payload(payload: dict[str, Any], source: str) -> None:
    failures: list[str] = []
    for snippet in REQUIRED_SOURCE_SNIPPETS:
        if snippet not in source:
            failures.append(f"source missing expected snippet: {snippet}")

    mac = payload["apps"]["macOS"]
    ios = payload["apps"]["iOS"]

    if payload["shared"]["tracking"]:
        failures.append("shared tracking must be false")
    if payload["shared"]["thirdPartyAdvertising"]:
        failures.append("third-party advertising must be false")
    if mac["dataLinkedToYou"]:
        failures.append("macOS dataLinkedToYou must be false")
    if mac["dataUsedToTrackYou"]:
        failures.append("macOS dataUsedToTrackYou must be false")
    if mac["privacyManifest"]["tracking"]:
        failures.append("macOS privacy manifest tracking must be false")
    if mac["privacyManifest"]["collectedDataTypes"]:
        failures.append("macOS privacy manifest collected data types must be empty")
    if "NSPrivacyAccessedAPICategoryUserDefaults" not in mac["privacyManifest"]["accessedAPITypes"]:
        failures.append("macOS privacy manifest must declare UserDefaults access")
    if "NSPrivacyAccessedAPICategoryFileTimestamp" not in mac["privacyManifest"]["accessedAPITypes"]:
        failures.append("macOS privacy manifest must declare file timestamp access")

    if ios["dataCollected"]:
        failures.append("iOS dataCollected must be false")
    if ios["dataLinkedToYou"]:
        failures.append("iOS dataLinkedToYou must be false")
    if ios["privacyManifest"]["tracking"]:
        failures.append("iOS privacy manifest tracking must be false")
    if ios["privacyManifest"]["collectedDataTypes"]:
        failures.append("iOS privacy manifest collected data types must be empty")
    for category in [
        "NSPrivacyAccessedAPICategoryUserDefaults",
        "NSPrivacyAccessedAPICategoryFileTimestamp",
        "NSPrivacyAccessedAPICategoryDiskSpace",
    ]:
        if category not in ios["privacyManifest"]["accessedAPITypes"]:
            failures.append(f"iOS privacy manifest must declare {category}")
    if "iPhone microphone audio" not in ios["permissions"]["microphone"]:
        failures.append("iOS microphone permission must describe optional source camera audio")

    if failures:
        raise SystemExit("error: generated privacy labels are invalid:\n- " + "\n- ".join(failures))


def comparable_payload(payload: dict[str, Any]) -> dict[str, Any]:
    comparable = dict(payload)
    comparable.pop("generatedAt", None)
    return comparable


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate exact BlitzRecorder App Store privacy nutrition label answers.")
    parser.add_argument("--check", action="store_true", help="Verify generated JSON matches the privacy worksheet and manifests without rewriting it.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source = read_text(SOURCE_PATH)
    payload = build_payload()
    validate_payload(payload, source)

    if args.check:
        if not OUTPUT_PATH.exists():
            raise SystemExit(f"error: missing generated file: {OUTPUT_PATH.relative_to(ROOT)}")
        existing = json.loads(OUTPUT_PATH.read_text(encoding="utf-8"))
        if comparable_payload(existing) != comparable_payload(payload):
            raise SystemExit(f"error: {OUTPUT_PATH.relative_to(ROOT)} is stale; run Scripts/generate-app-store-privacy-labels.py")
        print(f"Verified {OUTPUT_PATH.relative_to(ROOT)}")
        return 0

    OUTPUT_PATH.write_text(json.dumps(payload, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    print(f"Generated {OUTPUT_PATH.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
