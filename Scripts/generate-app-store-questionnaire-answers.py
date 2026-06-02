#!/usr/bin/env python3
"""Generate exact App Store questionnaire answers for BlitzRecorder."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SOURCE_PATH = ROOT / "AppStore" / "AppStoreQuestionnaires.md"
OUTPUT_PATH = ROOT / "AppStore" / "AppStoreQuestionnaireAnswers.generated.json"

SUBSCRIPTION_PRODUCT_ID = "dev.blitzreels.blitzrecorder.pro.monthly"
ANNUAL_SUBSCRIPTION_PRODUCT_ID = "dev.blitzreels.blitzrecorder.pro.annual"

REQUIRED_SOURCE_SNIPPETS = [
    "Recommended rating target: `4+`",
    "Does the app use IDFA? `No`",
    "Tracking: `No`",
    "Third-party advertising: `No`",
    "Made for Kids: `No`",
    "no non-exempt encryption",
    "SHA-256 transfer digest",
    "Users are responsible for rights",
    "iOS companion has no in-app purchases and no paywall.",
    SUBSCRIPTION_PRODUCT_ID,
    ANNUAL_SUBSCRIPTION_PRODUCT_ID,
]


def read_source() -> str:
    if not SOURCE_PATH.exists():
        raise SystemExit(f"error: missing source file: {SOURCE_PATH.relative_to(ROOT)}")
    return SOURCE_PATH.read_text(encoding="utf-8")


def build_payload() -> dict[str, Any]:
    return {
        "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "sourceFiles": [str(SOURCE_PATH.relative_to(ROOT))],
        "appliesTo": {
            "macOSBundleId": "dev.blitzreels.blitzrecorder",
            "iOSBundleId": "dev.blitzreels.blitzrecorder.camera",
        },
        "ageRating": {
            "recommendedTarget": "4+",
            "frequencyAnswers": {
                "cartoonOrFantasyViolence": "None",
                "realisticViolence": "None",
                "prolongedGraphicOrSadisticRealisticViolence": "None",
                "profanityOrCrudeHumor": "None",
                "matureOrSuggestiveThemes": "None",
                "horrorOrFearThemes": "None",
                "medicalOrTreatmentInformation": "None",
                "alcoholTobaccoDrugUseOrReferences": "None",
                "simulatedGambling": "None",
                "sexualContentOrNudity": "None",
            },
            "booleanAnswers": {
                "contests": False,
                "gambling": False,
                "unrestrictedWebAccess": False,
                "userGeneratedContentService": False,
            },
            "note": "Users create local recordings, but the apps do not host, publish, browse, moderate, or share UGC through a developer service.",
        },
        "exportCompliance": {
            "intendedResult": "no non-exempt encryption",
            "itsAppUsesNonExemptEncryption": False,
            "usesProprietaryEncryption": False,
            "usesCustomCryptographicProtocol": False,
            "usesVPNOrSecurityProductFunctionality": False,
            "usesCryptoWalletFunctionality": False,
            "sha256Use": "file-transfer integrity checks only",
            "networking": "Apple system networking and HTTPS for fixed BlitzRecorder/BlitzReels URLs; local network transport for companion pairing, preview, controls, and transfer.",
        },
        "contentRights": {
            "shipsThirdPartyMediaCatalogs": False,
            "shipsTemplatesMusicStockFootageOrEditorialContent": False,
            "usersResponsibleForRecordedContentRights": True,
            "termsSource": "Web/blitzrecorder/src/main.jsx",
        },
        "advertisingIdentifier": {
            "usesIDFA": False,
            "tracking": False,
            "thirdPartyAdvertising": False,
        },
        "kidsCategory": {
            "madeForKids": False,
            "rationale": "Creator/productivity recording tool with subscription purchase flow in the Mac app.",
        },
        "signInRequirement": {
            "appStoreSubscriptionRequiresBlitzReelsSignIn": False,
            "blitzReelsSignInOptional": True,
            "iosCompanionRequiresAccount": False,
            "iosCompanionPairing": "local network",
        },
        "paidContentAndSubscriptions": {
            "macAppHasAutoRenewableSubscription": True,
            "subscriptionName": "BlitzRecorder Pro",
            "monthlySubscriptionName": "BlitzRecorder Pro Monthly",
            "productId": SUBSCRIPTION_PRODUCT_ID,
            "price": "$7.99 per month",
            "annualSubscriptionName": "BlitzRecorder Pro Annual",
            "annualProductId": ANNUAL_SUBSCRIPTION_PRODUCT_ID,
            "annualPrice": "$49.99 per year",
            "freeBehavior": "10 free exports",
            "iosCompanionHasInAppPurchases": False,
            "iosCompanionHasPaywall": False,
        },
        "reviewTriggers": [
            "Analytics, crash reporting, ads, attribution, or tracking SDKs are added.",
            "Cloud upload, sharing, hosting, collaboration, comments, public profiles, or publishing are added.",
            "End-user templates, music, stock footage, or other bundled third-party media are added.",
            "Custom encryption, encrypted messaging, VPN/security, DRM, crypto wallet, or password-management functionality is added.",
            "BlitzReels entitlement responses start returning email, billing IDs, workspace IDs, subscription IDs, or receipt data.",
        ],
    }


def validate_payload(payload: dict[str, Any], source: str) -> None:
    failures: list[str] = []
    for snippet in REQUIRED_SOURCE_SNIPPETS:
        if snippet not in source:
            failures.append(f"source missing expected snippet: {snippet}")

    if payload["ageRating"]["recommendedTarget"] != "4+":
        failures.append("age rating target must be 4+")
    if payload["advertisingIdentifier"]["usesIDFA"]:
        failures.append("IDFA must be false")
    if payload["advertisingIdentifier"]["tracking"]:
        failures.append("tracking must be false")
    if payload["kidsCategory"]["madeForKids"]:
        failures.append("madeForKids must be false")
    if payload["exportCompliance"]["itsAppUsesNonExemptEncryption"]:
        failures.append("ITSAppUsesNonExemptEncryption must be false")
    if payload["paidContentAndSubscriptions"]["productId"] != SUBSCRIPTION_PRODUCT_ID:
        failures.append("subscription product ID mismatch")
    if payload["paidContentAndSubscriptions"]["iosCompanionHasInAppPurchases"]:
        failures.append("iOS companion must not have IAP")
    if payload["paidContentAndSubscriptions"]["iosCompanionHasPaywall"]:
        failures.append("iOS companion must not have paywall")

    if failures:
        raise SystemExit("error: generated questionnaire answers are invalid:\n- " + "\n- ".join(failures))


def comparable_payload(payload: dict[str, Any]) -> dict[str, Any]:
    comparable = dict(payload)
    comparable.pop("generatedAt", None)
    return comparable


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate exact BlitzRecorder App Store questionnaire answers.")
    parser.add_argument("--check", action="store_true", help="Verify generated JSON matches the questionnaire worksheet without rewriting it.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source = read_source()
    payload = build_payload()
    validate_payload(payload, source)

    if args.check:
        if not OUTPUT_PATH.exists():
            raise SystemExit(f"error: missing generated file: {OUTPUT_PATH.relative_to(ROOT)}")
        existing = json.loads(OUTPUT_PATH.read_text(encoding="utf-8"))
        if comparable_payload(existing) != comparable_payload(payload):
            raise SystemExit(f"error: {OUTPUT_PATH.relative_to(ROOT)} is stale; run Scripts/generate-app-store-questionnaire-answers.py")
        print(f"Verified {OUTPUT_PATH.relative_to(ROOT)}")
        return 0

    OUTPUT_PATH.write_text(json.dumps(payload, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    print(f"Generated {OUTPUT_PATH.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
