#!/usr/bin/env python3
"""Verify BlitzRecorder App Store Connect records.

Required environment for live checks:
  ASC_KEY_ID
  ASC_ISSUER_ID
  ASC_PRIVATE_KEY_PATH or ASC_PRIVATE_KEY

The script intentionally checks read-only state. It does not create App Store
Connect records because app creation, subscription review metadata, tax/banking,
and legal agreements can require account-owner decisions.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


MAC_BUNDLE_ID = "dev.blitzreels.blitzrecorder"
IOS_BUNDLE_ID = "dev.blitzreels.blitzrecorder.camera"
SUBSCRIPTION_PRODUCT_ID = "dev.blitzreels.blitzrecorder.pro.monthly"
ANNUAL_SUBSCRIPTION_PRODUCT_ID = "dev.blitzreels.blitzrecorder.pro.annual"
SUBSCRIPTION_GROUP_NAME = "BlitzRecorder Pro"
SUBSCRIPTION_REFERENCE_NAME = "BlitzRecorder Pro Monthly"
SUBSCRIPTION_DISPLAY_NAME = "BlitzRecorder Pro"
SUBSCRIPTION_DESCRIPTION = "Unlimited exports in BlitzRecorder."
SUBSCRIPTION_LOCALE = "en-US"
SUBSCRIPTION_PERIOD = "ONE_MONTH"
EXPECTED_PRICE_USD = "7.99"
EXPECTED_ANNUAL_PRICE_USD = "49.99"
EXPECTED_STOREKIT_PERIOD = "P1M"
EXPECTED_MARKETING_VERSION = "0.1.0"
EXPECTED_BUILD_NUMBER = "1"
API_BASE = "https://api.appstoreconnect.apple.com"
FIELDS_PATH = Path(__file__).resolve().parents[1] / "AppStore" / "AppStoreConnectFields.generated.json"


class ReadinessError(RuntimeError):
    pass


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def der_to_raw_ecdsa_signature(der: bytes) -> bytes:
    if len(der) < 8 or der[0] != 0x30:
        raise ReadinessError("OpenSSL returned an invalid ECDSA DER signature")

    offset = 2
    sequence_length = der[1]
    if sequence_length & 0x80:
        length_bytes = sequence_length & 0x7F
        sequence_length = int.from_bytes(der[offset : offset + length_bytes], "big")
        offset += length_bytes

    end = offset + sequence_length
    values: list[bytes] = []
    while offset < end:
        if der[offset] != 0x02:
            raise ReadinessError("OpenSSL returned an invalid ECDSA integer")
        offset += 1
        integer_length = der[offset]
        offset += 1
        value = der[offset : offset + integer_length]
        offset += integer_length
        value = value.lstrip(b"\x00")
        if len(value) > 32:
            raise ReadinessError("OpenSSL returned an ECDSA integer longer than P-256")
        values.append(value.rjust(32, b"\x00"))

    if len(values) != 2:
        raise ReadinessError("OpenSSL returned an ECDSA signature without r and s")
    return b"".join(values)


def make_jwt(key_id: str, issuer_id: str, private_key_path: Path) -> str:
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    now = int(time.time())
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + 20 * 60,
        "aud": "appstoreconnect-v1",
    }
    signing_input = ".".join(
        [
            b64url(json.dumps(header, separators=(",", ":")).encode("utf-8")),
            b64url(json.dumps(payload, separators=(",", ":")).encode("utf-8")),
        ]
    )
    signature_der = subprocess.check_output(
        [
            "openssl",
            "dgst",
            "-sha256",
            "-sign",
            str(private_key_path),
        ],
        input=signing_input.encode("ascii"),
    )
    return f"{signing_input}.{b64url(der_to_raw_ecdsa_signature(signature_der))}"


def private_key_path_from_env() -> tuple[Path, tempfile.TemporaryDirectory[str] | None]:
    path = os.environ.get("ASC_PRIVATE_KEY_PATH")
    if path:
        return Path(path).expanduser(), None

    private_key = os.environ.get("ASC_PRIVATE_KEY")
    if not private_key:
        raise ReadinessError("Set ASC_PRIVATE_KEY_PATH or ASC_PRIVATE_KEY.")

    temp_dir = tempfile.TemporaryDirectory(prefix="blitzrecorder-asc-key-")
    key_path = Path(temp_dir.name) / "AuthKey.p8"
    key_path.write_text(private_key, encoding="utf-8")
    key_path.chmod(0o600)
    return key_path, temp_dir


class AppStoreConnectClient:
    def __init__(self, token: str, api_base: str) -> None:
        self.token = token
        self.api_base = api_base.rstrip("/")

    def get(self, path_or_url: str, query: dict[str, str] | None = None) -> dict[str, Any]:
        if path_or_url.startswith("http"):
            url = path_or_url
        else:
            url = f"{self.api_base}{path_or_url}"

        if query:
            separator = "&" if "?" in url else "?"
            url = f"{url}{separator}{urllib.parse.urlencode(query)}"

        request = urllib.request.Request(
            url,
            headers={
                "Authorization": f"Bearer {self.token}",
                "Accept": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as error:
            body = error.read().decode("utf-8", errors="replace")
            raise ReadinessError(f"GET {url} failed with HTTP {error.code}: {body}") from error

    def get_all(self, path: str, query: dict[str, str] | None = None) -> list[dict[str, Any]]:
        items: list[dict[str, Any]] = []
        response = self.get(path, query)
        while True:
            data = response.get("data", [])
            if isinstance(data, list):
                items.extend(data)
            elif data:
                items.append(data)
            next_url = response.get("links", {}).get("next")
            if not next_url:
                return items
            response = self.get(next_url)


def one_matching(items: list[dict[str, Any]], predicate: Any, label: str) -> dict[str, Any] | None:
    matches = [item for item in items if predicate(item)]
    if not matches:
        print(f"✗ Missing {label}")
        return None
    item = matches[0]
    print(f"✓ Found {label}: {item.get('id')}")
    return item


def app_platform(app: dict[str, Any], fallback: str) -> str:
    return str(app.get("attributes", {}).get("platform") or fallback)


def expected_fields() -> dict[str, Any]:
    try:
        return json.loads(FIELDS_PATH.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise ReadinessError(f"Missing {FIELDS_PATH.relative_to(FIELDS_PATH.parents[1])}") from error
    except json.JSONDecodeError as error:
        raise ReadinessError(f"{FIELDS_PATH.relative_to(FIELDS_PATH.parents[1])} is invalid JSON: {error}") from error


def normalize_price(value: Any) -> str | None:
    if value is None:
        return None
    try:
        return f"{float(str(value)):.2f}"
    except ValueError:
        return str(value)


def text_matches(actual: Any, expected: str) -> bool:
    return str(actual or "").strip() == expected.strip()


def check_attribute(label: str, attributes: dict[str, Any], key: str, expected: str) -> int:
    actual = attributes.get(key)
    if text_matches(actual, expected):
        print(f"✓ {label} {key} matches")
        return 0
    print(f"✗ {label} {key} is {actual!r}, expected {expected!r}")
    return 1


def first_locale_match(items: list[dict[str, Any]], locale: str) -> dict[str, Any] | None:
    return next((item for item in items if item.get("attributes", {}).get("locale") == locale), None)


def verify_app_store_version(
    client: AppStoreConnectClient,
    *,
    app: dict[str, Any],
    platform: str,
    label: str,
) -> int:
    versions = client.get_all(
        f"/v1/apps/{app['id']}/appStoreVersions",
        {
            "filter[versionString]": EXPECTED_MARKETING_VERSION,
            "limit": "200",
        },
    )
    version = one_matching(
        versions,
        lambda item, platform=platform: (
            item.get("attributes", {}).get("versionString") == EXPECTED_MARKETING_VERSION
            and item.get("attributes", {}).get("platform", platform) == platform
        ),
        f"{label} App Store version {EXPECTED_MARKETING_VERSION}",
    )
    if not version:
        return 1

    state = version.get("attributes", {}).get("appStoreState")
    print(f"✓ {label} App Store version state is {state or 'unknown'}")
    return 0


def find_app_store_version(
    client: AppStoreConnectClient,
    *,
    app: dict[str, Any],
    platform: str,
) -> dict[str, Any] | None:
    versions = client.get_all(
        f"/v1/apps/{app['id']}/appStoreVersions",
        {
            "filter[versionString]": EXPECTED_MARKETING_VERSION,
            "limit": "200",
        },
    )
    return next(
        (
            item
            for item in versions
            if item.get("attributes", {}).get("versionString") == EXPECTED_MARKETING_VERSION
            and item.get("attributes", {}).get("platform", platform) == platform
        ),
        None,
    )


def verify_uploaded_build(
    client: AppStoreConnectClient,
    *,
    app: dict[str, Any],
    label: str,
) -> int:
    builds = client.get_all(
        "/v1/builds",
        {
            "filter[app]": app["id"],
            "filter[version]": EXPECTED_BUILD_NUMBER,
            "limit": "200",
        },
    )
    build = one_matching(
        builds,
        lambda item: str(item.get("attributes", {}).get("version")) == EXPECTED_BUILD_NUMBER,
        f"{label} uploaded build {EXPECTED_BUILD_NUMBER}",
    )
    if not build:
        return 1

    state = build.get("attributes", {}).get("processingState")
    if state == "VALID":
        print(f"✓ {label} uploaded build {EXPECTED_BUILD_NUMBER} is VALID")
        return 0

    print(f"✗ {label} uploaded build {EXPECTED_BUILD_NUMBER} processing state is {state or 'unknown'}, expected VALID")
    return 1


def verify_app_info_localization(
    client: AppStoreConnectClient,
    *,
    app: dict[str, Any],
    label: str,
    expected_app: dict[str, Any],
) -> int:
    failures = 0
    app_infos = client.get_all(f"/v1/apps/{app['id']}/appInfos", {"limit": "200"})
    if not app_infos:
        print(f"✗ Missing {label} app info")
        return 1

    localizations: list[dict[str, Any]] = []
    for app_info in app_infos:
        localizations.extend(client.get_all(f"/v1/appInfos/{app_info['id']}/appInfoLocalizations", {"limit": "200"}))

    localization = first_locale_match(localizations, expected_app["primaryLocale"])
    if not localization:
        print(f"✗ Missing {label} app info {expected_app['primaryLocale']} localization")
        return 1

    print(f"✓ Found {label} app info {expected_app['primaryLocale']} localization: {localization.get('id')}")
    attributes = localization.get("attributes", {})
    failures += check_attribute(f"{label} app info localization", attributes, "name", expected_app["appName"])
    failures += check_attribute(f"{label} app info localization", attributes, "subtitle", expected_app["subtitle"])
    failures += check_attribute(
        f"{label} app info localization",
        attributes,
        "privacyPolicyUrl",
        expected_app["privacyPolicyUrl"],
    )
    return failures


def verify_version_localization(
    client: AppStoreConnectClient,
    *,
    version: dict[str, Any],
    label: str,
    expected_app: dict[str, Any],
) -> int:
    localizations = client.get_all(
        f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations",
        {"limit": "200"},
    )
    localization = first_locale_match(localizations, expected_app["primaryLocale"])
    if not localization:
        print(f"✗ Missing {label} App Store version {expected_app['primaryLocale']} localization")
        return 1

    print(f"✓ Found {label} App Store version {expected_app['primaryLocale']} localization: {localization.get('id')}")
    attributes = localization.get("attributes", {})
    failures = 0
    failures += check_attribute(f"{label} version localization", attributes, "description", expected_app["description"])
    failures += check_attribute(f"{label} version localization", attributes, "keywords", expected_app["keywords"])
    failures += check_attribute(f"{label} version localization", attributes, "promotionalText", expected_app["promotionalText"])
    failures += check_attribute(f"{label} version localization", attributes, "supportUrl", expected_app["supportUrl"])
    failures += check_attribute(f"{label} version localization", attributes, "marketingUrl", expected_app["marketingUrl"])
    return failures


def verify_subscription_group_localization(
    client: AppStoreConnectClient,
    *,
    group_id: str,
) -> int:
    localizations = client.get_all(f"/v1/subscriptionGroups/{group_id}/subscriptionGroupLocalizations")
    localization = one_matching(
        localizations,
        lambda item: item.get("attributes", {}).get("locale") == SUBSCRIPTION_LOCALE,
        f"subscription group {SUBSCRIPTION_LOCALE} localization",
    )
    if not localization:
        return 1

    name = localization.get("attributes", {}).get("name")
    if name == SUBSCRIPTION_GROUP_NAME:
        print(f"✓ Subscription group {SUBSCRIPTION_LOCALE} display name is {SUBSCRIPTION_GROUP_NAME}")
        return 0

    print(f"✗ Subscription group {SUBSCRIPTION_LOCALE} display name is {name!r}, expected {SUBSCRIPTION_GROUP_NAME!r}")
    return 1


def verify_subscription_metadata(
    client: AppStoreConnectClient,
    *,
    subscription: dict[str, Any],
) -> int:
    failures = 0
    attributes = subscription.get("attributes", {})

    reference_name = attributes.get("name")
    if reference_name == SUBSCRIPTION_REFERENCE_NAME:
        print(f"✓ Subscription reference name is {SUBSCRIPTION_REFERENCE_NAME}")
    else:
        print(f"✗ Subscription reference name is {reference_name!r}, expected {SUBSCRIPTION_REFERENCE_NAME!r}")
        failures += 1

    localizations = client.get_all(f"/v1/subscriptions/{subscription['id']}/subscriptionLocalizations")
    localization = one_matching(
        localizations,
        lambda item: item.get("attributes", {}).get("locale") == SUBSCRIPTION_LOCALE,
        f"subscription {SUBSCRIPTION_LOCALE} localization",
    )
    if not localization:
        return failures + 1

    localization_attributes = localization.get("attributes", {})
    display_name = localization_attributes.get("name")
    if display_name == SUBSCRIPTION_DISPLAY_NAME:
        print(f"✓ Subscription {SUBSCRIPTION_LOCALE} display name is {SUBSCRIPTION_DISPLAY_NAME}")
    else:
        print(f"✗ Subscription {SUBSCRIPTION_LOCALE} display name is {display_name!r}, expected {SUBSCRIPTION_DISPLAY_NAME!r}")
        failures += 1

    description = localization_attributes.get("description")
    if description == SUBSCRIPTION_DESCRIPTION:
        print(f"✓ Subscription {SUBSCRIPTION_LOCALE} description is {SUBSCRIPTION_DESCRIPTION}")
    else:
        print(f"✗ Subscription {SUBSCRIPTION_LOCALE} description is {description!r}, expected {SUBSCRIPTION_DESCRIPTION!r}")
        failures += 1

    return failures


def check_live(args: argparse.Namespace) -> int:
    key_id = os.environ.get("ASC_KEY_ID")
    issuer_id = os.environ.get("ASC_ISSUER_ID")
    if not key_id or not issuer_id:
        raise ReadinessError("Set ASC_KEY_ID and ASC_ISSUER_ID.")

    key_path, temp_dir = private_key_path_from_env()
    try:
        token = make_jwt(key_id, issuer_id, key_path)
    finally:
        if temp_dir is not None:
            temp_dir.cleanup()

    client = AppStoreConnectClient(token=token, api_base=args.api_base)
    expected = expected_fields()
    failures = 0

    for bundle_id in (MAC_BUNDLE_ID, IOS_BUNDLE_ID):
        bundle_ids = client.get_all(
            "/v1/bundleIds",
            {"filter[identifier]": bundle_id, "limit": "200"},
        )
        if not one_matching(
            bundle_ids,
            lambda item, bundle_id=bundle_id: item.get("attributes", {}).get("identifier") == bundle_id,
            f"registered bundle ID {bundle_id}",
        ):
            failures += 1

    apps = client.get_all("/v1/apps", {"limit": "200"})
    mac_app = one_matching(
        apps,
        lambda item: item.get("attributes", {}).get("bundleId") == MAC_BUNDLE_ID,
        f"macOS app record {MAC_BUNDLE_ID}",
    )
    ios_app = one_matching(
        apps,
        lambda item: item.get("attributes", {}).get("bundleId") == IOS_BUNDLE_ID,
        f"iOS companion app record {IOS_BUNDLE_ID}",
    )
    if not mac_app:
        failures += 1
    if not ios_app:
        failures += 1

    if mac_app:
        mac_platform = app_platform(mac_app, "MAC_OS")
        mac_version = find_app_store_version(client, app=mac_app, platform=mac_platform)
        failures += verify_app_store_version(
            client,
            app=mac_app,
            platform=mac_platform,
            label="macOS",
        )
        if mac_version:
            failures += verify_version_localization(
                client,
                version=mac_version,
                label="macOS",
                expected_app=expected["apps"]["macOS"],
            )
        failures += verify_app_info_localization(
            client,
            app=mac_app,
            label="macOS",
            expected_app=expected["apps"]["macOS"],
        )
        failures += verify_uploaded_build(client, app=mac_app, label="macOS")

    if ios_app:
        ios_platform = app_platform(ios_app, "IOS")
        ios_version = find_app_store_version(client, app=ios_app, platform=ios_platform)
        failures += verify_app_store_version(
            client,
            app=ios_app,
            platform=ios_platform,
            label="iOS companion",
        )
        if ios_version:
            failures += verify_version_localization(
                client,
                version=ios_version,
                label="iOS companion",
                expected_app=expected["apps"]["iOS"],
            )
        failures += verify_app_info_localization(
            client,
            app=ios_app,
            label="iOS companion",
            expected_app=expected["apps"]["iOS"],
        )
        failures += verify_uploaded_build(client, app=ios_app, label="iOS companion")

    if mac_app:
        groups = client.get_all(f"/v1/apps/{mac_app['id']}/subscriptionGroups", {"limit": "200"})
        group = one_matching(
            groups,
            lambda item: item.get("attributes", {}).get("referenceName") == SUBSCRIPTION_GROUP_NAME,
            f"subscription group {SUBSCRIPTION_GROUP_NAME}",
        )
        if not group:
            failures += 1
        else:
            failures += verify_subscription_group_localization(client, group_id=group["id"])
            subscriptions = client.get_all(
                f"/v1/subscriptionGroups/{group['id']}/subscriptions",
                {"filter[productId]": SUBSCRIPTION_PRODUCT_ID, "limit": "200"},
            )
            subscription = one_matching(
                subscriptions,
                lambda item: item.get("attributes", {}).get("productId") == SUBSCRIPTION_PRODUCT_ID,
                f"subscription product {SUBSCRIPTION_PRODUCT_ID}",
            )
            if not subscription:
                failures += 1
            else:
                failures += verify_subscription_metadata(client, subscription=subscription)
                attributes = subscription.get("attributes", {})
                period = attributes.get("subscriptionPeriod")
                if period == SUBSCRIPTION_PERIOD:
                    print(f"✓ Subscription period is {SUBSCRIPTION_PERIOD}")
                else:
                    print(f"✗ Subscription period is {period!r}, expected {SUBSCRIPTION_PERIOD}")
                    failures += 1

                price_response = client.get(
                    f"/v1/subscriptions/{subscription['id']}/prices",
                    {
                        "filter[territory]": args.price_territory,
                        "include": "subscriptionPricePoint",
                        "limit": "200",
                    },
                )
                price_points = {
                    item.get("id"): item
                    for item in price_response.get("included", [])
                    if item.get("type") == "subscriptionPricePoints"
                }
                prices = []
                for price in price_response.get("data", []):
                    point_id = (
                        price.get("relationships", {})
                        .get("subscriptionPricePoint", {})
                        .get("data", {})
                        .get("id")
                    )
                    customer_price = price_points.get(point_id, {}).get("attributes", {}).get("customerPrice")
                    normalized = normalize_price(customer_price)
                    if normalized:
                        prices.append(normalized)

                expected = normalize_price(args.expected_price)
                if expected in prices:
                    print(f"✓ {args.price_territory} subscription price includes {expected}")
                else:
                    printable = ", ".join(prices) if prices else "none"
                    print(f"✗ {args.price_territory} subscription prices are {printable}; expected {expected}")
                    failures += 1

    return 1 if failures else 0


def check_text_contains(root: Path, relative_path: str, expected: str) -> int:
    path = root / relative_path
    if not path.exists():
        print(f"✗ Missing {relative_path}")
        return 1
    text = path.read_text(encoding="utf-8")
    if expected in text:
        print(f"✓ {relative_path} contains {expected}")
        return 0
    print(f"✗ {relative_path} missing {expected}")
    return 1


def check_text_excludes(root: Path, relative_path: str, unexpected: str) -> int:
    path = root / relative_path
    if not path.exists():
        print(f"✗ Missing {relative_path}")
        return 1
    text = path.read_text(encoding="utf-8")
    if unexpected not in text:
        print(f"✓ {relative_path} does not contain {unexpected}")
        return 0
    print(f"✗ {relative_path} unexpectedly contains {unexpected}")
    return 1


def check_storekit_configuration(root: Path) -> int:
    path = root / "AppStore/BlitzRecorder.storekit"
    if not path.exists():
        print("✗ Missing AppStore/BlitzRecorder.storekit")
        return 1

    failures = 0
    try:
        storekit = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        print(f"✗ AppStore/BlitzRecorder.storekit is invalid JSON: {error}")
        return 1

    subscriptions = [
        subscription
        for group in storekit.get("subscriptionGroups", [])
        for subscription in group.get("subscriptions", [])
    ]
    subscription = next(
        (item for item in subscriptions if item.get("productID") == SUBSCRIPTION_PRODUCT_ID),
        None,
    )
    if subscription is None:
        print(f"✗ StoreKit configuration missing subscription {SUBSCRIPTION_PRODUCT_ID}")
        return 1
    print(f"✓ StoreKit configuration contains subscription {SUBSCRIPTION_PRODUCT_ID}")

    price = normalize_price(subscription.get("displayPrice"))
    expected_price = normalize_price(EXPECTED_PRICE_USD)
    if price == expected_price:
        print(f"✓ StoreKit display price is {expected_price}")
    else:
        print(f"✗ StoreKit display price is {price!r}, expected {expected_price}")
        failures += 1

    period = subscription.get("recurringSubscriptionPeriod")
    if period == EXPECTED_STOREKIT_PERIOD:
        print(f"✓ StoreKit subscription period is {EXPECTED_STOREKIT_PERIOD}")
    else:
        print(f"✗ StoreKit subscription period is {period!r}, expected {EXPECTED_STOREKIT_PERIOD}")
        failures += 1

    display_names = [
        localization.get("displayName")
        for localization in subscription.get("localizations", [])
    ]
    descriptions = [
        localization.get("description")
        for localization in subscription.get("localizations", [])
    ]
    if "BlitzRecorder Pro" in display_names:
        print("✓ StoreKit subscription localization includes BlitzRecorder Pro")
    else:
        print("✗ StoreKit subscription localization missing BlitzRecorder Pro")
        failures += 1
    if SUBSCRIPTION_DESCRIPTION in descriptions:
        print(f"✓ StoreKit subscription localization description is {SUBSCRIPTION_DESCRIPTION}")
    else:
        print(f"✗ StoreKit subscription localization description missing {SUBSCRIPTION_DESCRIPTION}")
        failures += 1

    return failures


def check_local_files(root: Path) -> int:
    failures = 0
    contains_checks = [
        ("Info.plist", MAC_BUNDLE_ID),
        ("Info.plist", "$(MARKETING_VERSION)"),
        ("Info.plist", "$(CURRENT_PROJECT_VERSION)"),
        ("Info.plist", "_blitzrecorder-camera._tcp"),
        ("Apps/iOSCamera/Info.plist", "$(PRODUCT_BUNDLE_IDENTIFIER)"),
        ("Apps/iOSCamera/Info.plist", "$(MARKETING_VERSION)"),
        ("Apps/iOSCamera/Info.plist", "$(CURRENT_PROJECT_VERSION)"),
        ("Apps/iOSCamera/Info.plist", "_blitzrecorder-camera._tcp"),
        ("Apps/iOSCamera/Info.plist", "<string>camera</string>"),
        ("Apps/iOSCamera/Info.plist", "NSMicrophoneUsageDescription"),
        ("project.yml", "PRODUCT_BUNDLE_IDENTIFIER: dev.blitzreels.blitzrecorder.camera"),
        ("project.yml", "storeKitConfiguration: AppStore/BlitzRecorder.storekit"),
        ("project.yml", f'MARKETING_VERSION: "{EXPECTED_MARKETING_VERSION}"'),
        ("project.yml", f'CURRENT_PROJECT_VERSION: "{EXPECTED_BUILD_NUMBER}"'),
        ("Sources/BlitzRecorderApp/AccessController.swift", f'static let monthlyProductID = "{SUBSCRIPTION_PRODUCT_ID}"'),
        ("Sources/BlitzRecorderApp/AccessController.swift", f'static let annualProductID = "{ANNUAL_SUBSCRIPTION_PRODUCT_ID}"'),
        ("Sources/BlitzRecorderApp/AccessController.swift", "static let freeExportLimit = 3"),
        ("Sources/BlitzRecorderApp/UI/BlitzReelsCreatorPage.swift", "BlitzRecorder Pro unlocks unlimited exports on Mac."),
        ("Sources/BlitzRecorderApp/UI/BlitzReelsCreatorPage.swift", "App Store subscriptions renew until cancelled in Apple account settings."),
        ("Sources/BlitzRecorderApp/UI/BlitzReelsCreatorPage.swift", "Eligible active BlitzReels subscribers can sign in for included Pro access."),
        ("Sources/BlitzRecorderApp/UI/BlitzReelsCreatorPage.swift", "BlitzReels Sign In"),
        ("Sources/BlitzRecorderApp/UI/BlitzReelsCreatorPage.swift", "Restore"),
        ("Sources/BlitzRecorderApp/UI/BlitzReelsCreatorPage.swift", "Terms"),
        ("Sources/BlitzRecorderApp/UI/BlitzReelsCreatorPage.swift", "Privacy"),
        ("Sources/BlitzRecorderApp/UI/BlitzReelsCreatorPage.swift", "Support"),
        ("AppStore/SubmissionChecklist.md", SUBSCRIPTION_PRODUCT_ID),
        ("AppStore/SubmissionChecklist.md", ANNUAL_SUBSCRIPTION_PRODUCT_ID),
        ("AppStore/SubmissionChecklist.md", "$7.99 per month"),
        ("AppStore/SubmissionChecklist.md", "$49.99 per year"),
        ("AppStore/SubmissionChecklist.md", "AppStore/ReviewNotes.md"),
        ("AppStore/SubmissionChecklist.md", "AppStore/DeviceQAChecklist.md"),
        ("AppStore/SubmissionChecklist.md", "AppStore/PrivacyNutritionLabels.md"),
        ("AppStore/SubmissionChecklist.md", "AppStore/PrivacyNutritionLabels.generated.json"),
        ("AppStore/SubmissionChecklist.md", "AppStore/AppStoreConnectManualSetup.md"),
        ("AppStore/SubmissionChecklist.md", "AppStore/AppStoreQuestionnaires.md"),
        ("AppStore/SubmissionChecklist.md", "AppStore/AppStoreConnectFields.generated.json"),
        ("AppStore/SubmissionChecklist.md", "AppStore/AppStoreQuestionnaireAnswers.generated.json"),
        ("AppStore/SubmissionChecklist.md", "Scripts/release-status.sh --full"),
        ("AppStore/SubmissionChecklist.md", "Scripts/collect-release-evidence.sh --full"),
        ("AppStore/SubmissionChecklist.md", "BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE=true"),
        ("AppStore/SubmissionChecklist.md", "BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE=false"),
        ("AppStore/Metadata.md", SUBSCRIPTION_PRODUCT_ID),
        ("AppStore/Metadata.md", ANNUAL_SUBSCRIPTION_PRODUCT_ID),
        ("AppStore/Metadata.md", "AppStore/DeviceQAChecklist.md"),
        ("AppStore/Metadata.md", "AppStore/PrivacyNutritionLabels.md"),
        ("AppStore/Metadata.md", "AppStore/PrivacyNutritionLabels.generated.json"),
        ("AppStore/Metadata.md", "AppStore/AppStoreConnectManualSetup.md"),
        ("AppStore/Metadata.md", "AppStore/AppStoreQuestionnaires.md"),
        ("AppStore/Metadata.md", "AppStore/AppStoreConnectFields.generated.json"),
        ("AppStore/Metadata.md", "AppStore/AppStoreQuestionnaireAnswers.generated.json"),
        ("AppStore/AppStoreConnectFields.generated.json", MAC_BUNDLE_ID),
        ("AppStore/AppStoreConnectFields.generated.json", IOS_BUNDLE_ID),
        ("AppStore/AppStoreConnectFields.generated.json", SUBSCRIPTION_PRODUCT_ID),
        ("AppStore/AppStoreConnectFields.generated.json", ANNUAL_SUBSCRIPTION_PRODUCT_ID),
        ("AppStore/AppStoreConnectFields.generated.json", '"priceUSD": "7.99"'),
        ("AppStore/AppStoreConnectFields.generated.json", '"annualPriceUSD": "49.99"'),
        ("AppStore/AppStoreConnectFields.generated.json", '"duration": "ONE_MONTH"'),
        ("AppStore/AppStoreConnectFields.generated.json", '"storeKitSubscriptionPeriod": "P1M"'),
        ("AppStore/AppStoreConnectFields.generated.json", '"companionOnly": true'),
        ("AppStore/AppStoreConnectFields.generated.json", '"initiatesPurchases": false'),
        ("AppStore/BlitzRecorder.storekit", SUBSCRIPTION_DESCRIPTION),
        ("AppStore/AppStoreQuestionnaireAnswers.generated.json", '"recommendedTarget": "4+"'),
        ("AppStore/AppStoreQuestionnaireAnswers.generated.json", '"usesIDFA": false'),
        ("AppStore/AppStoreQuestionnaireAnswers.generated.json", '"tracking": false'),
        ("AppStore/AppStoreQuestionnaireAnswers.generated.json", '"madeForKids": false'),
        ("AppStore/AppStoreQuestionnaireAnswers.generated.json", '"itsAppUsesNonExemptEncryption": false'),
        ("AppStore/AppStoreQuestionnaireAnswers.generated.json", SUBSCRIPTION_PRODUCT_ID),
        ("AppStore/AppStoreQuestionnaireAnswers.generated.json", ANNUAL_SUBSCRIPTION_PRODUCT_ID),
        ("AppStore/PrivacyNutritionLabels.generated.json", '"dataUsedToTrackYou": false'),
        ("AppStore/PrivacyNutritionLabels.generated.json", '"dataLinkedToYou": true'),
        ("AppStore/PrivacyNutritionLabels.generated.json", '"dataCollected": false'),
        ("AppStore/PrivacyNutritionLabels.generated.json", '"NSPrivacyAccessedAPICategoryDiskSpace"'),
        ("AppStore/PrivacyNutritionLabels.generated.json", "Can include iPhone microphone audio in the source camera file when recording starts."),
        ("AppStore/Metadata-macOS.md", MAC_BUNDLE_ID),
        ("AppStore/Metadata-macOS.md", SUBSCRIPTION_PRODUCT_ID),
        ("AppStore/Metadata-macOS.md", ANNUAL_SUBSCRIPTION_PRODUCT_ID),
        ("AppStore/Metadata-macOS.md", "$7.99 per month"),
        ("AppStore/Metadata-macOS.md", "$49.99 per year"),
        ("AppStore/Metadata-iOS.md", IOS_BUNDLE_ID),
        ("AppStore/Metadata-iOS.md", SUBSCRIPTION_PRODUCT_ID),
        ("AppStore/Metadata-iOS.md", ANNUAL_SUBSCRIPTION_PRODUCT_ID),
        ("AppStore/Metadata-iOS.md", "$7.99 per month"),
        ("AppStore/Metadata-iOS.md", "$49.99 per year"),
        ("AppStore/ReviewNotes.md", MAC_BUNDLE_ID),
        ("AppStore/ReviewNotes.md", IOS_BUNDLE_ID),
        ("AppStore/ReviewNotes.md", SUBSCRIPTION_PRODUCT_ID),
        ("AppStore/ReviewNotes.md", ANNUAL_SUBSCRIPTION_PRODUCT_ID),
        ("AppStore/ReviewNotes.md", "$7.99 per month"),
        ("AppStore/ReviewNotes.md", "$49.99 per year"),
        ("AppStore/ReviewNotes.md", "redirects to BlitzReels login"),
        ("AppStore/DeviceQAChecklist.md", "Mac App Subscription And Export Gate"),
        ("AppStore/DeviceQAChecklist.md", "BlitzReels Included Access"),
        ("AppStore/DeviceQAChecklist.md", "iOS Companion Pairing"),
        ("AppStore/DeviceQAChecklist.md", "Remote Camera Recording"),
        ("AppStore/DeviceQAChecklist.md", "Recovery And Failure Handling"),
        ("AppStore/DeviceQAChecklist.md", "Scripts/validate-submission-artifacts.sh --strict"),
        ("AppStore/PrivacyNutritionLabels.md", MAC_BUNDLE_ID),
        ("AppStore/PrivacyNutritionLabels.md", IOS_BUNDLE_ID),
        ("AppStore/PrivacyNutritionLabels.md", "Data Used to Track You: No"),
        ("AppStore/PrivacyNutritionLabels.md", "BlitzReels sign-in returns an access token"),
        ("AppStore/PrivacyNutritionLabels.md", "Data Collected: No"),
        ("AppStore/PrivacyNutritionLabels.md", "Microphone: can include iPhone microphone audio"),
        ("AppStore/AppStoreConnectManualSetup.md", MAC_BUNDLE_ID),
        ("AppStore/AppStoreConnectManualSetup.md", IOS_BUNDLE_ID),
        ("AppStore/AppStoreConnectManualSetup.md", "BLITZRECORDER-MAC"),
        ("AppStore/AppStoreConnectManualSetup.md", "BLITZRECORDER-CAMERA-IOS"),
        ("AppStore/AppStoreConnectManualSetup.md", SUBSCRIPTION_PRODUCT_ID),
        ("AppStore/AppStoreConnectManualSetup.md", ANNUAL_SUBSCRIPTION_PRODUCT_ID),
        ("AppStore/AppStoreConnectManualSetup.md", "$7.99 per month"),
        ("AppStore/AppStoreConnectManualSetup.md", "$49.99 per year"),
        ("AppStore/AppStoreConnectManualSetup.md", "3 free exports"),
        ("AppStore/AppStoreConnectManualSetup.md", "AppStore/Metadata-macOS.md"),
        ("AppStore/AppStoreConnectManualSetup.md", "AppStore/Metadata-iOS.md"),
        ("AppStore/AppStoreConnectManualSetup.md", "AppStore/AppStoreConnectFields.generated.json"),
        ("AppStore/AppStoreConnectManualSetup.md", "AppStore/PrivacyNutritionLabels.md"),
        ("AppStore/AppStoreConnectManualSetup.md", "AppStore/PrivacyNutritionLabels.generated.json"),
        ("AppStore/AppStoreConnectManualSetup.md", "Scripts/validate-submission-artifacts.sh --strict"),
        ("AppStore/AppStoreConnectManualSetup.md", "Positive production BlitzReels entitlement token test passed."),
        ("AppStore/AppStoreConnectManualSetup.md", "AppStore/AppStoreQuestionnaires.md"),
        ("AppStore/AppStoreConnectManualSetup.md", "AppStore/AppStoreQuestionnaireAnswers.generated.json"),
        ("AppStore/AppStoreQuestionnaires.md", "Recommended rating target: `4+`"),
        ("AppStore/AppStoreQuestionnaires.md", "ITSAppUsesNonExemptEncryption"),
        ("AppStore/AppStoreQuestionnaires.md", "no non-exempt encryption"),
        ("AppStore/AppStoreQuestionnaires.md", "SHA-256 transfer digest"),
        ("AppStore/AppStoreQuestionnaires.md", "Does the app use IDFA? `No`"),
        ("AppStore/AppStoreQuestionnaires.md", "Tracking: `No`"),
        ("AppStore/AppStoreQuestionnaires.md", "Made for Kids: `No`"),
        ("AppStore/AppStoreQuestionnaires.md", "iOS companion has no in-app purchases and no paywall."),
        ("AppStore/AppStoreQuestionnaires.md", "Users are responsible for rights"),
        ("Web/blitzrecorder/index.html", "$7.99 per month"),
        ("Web/blitzrecorder/index.html", "$49.99 per year"),
        ("Web/blitzrecorder/index.html", "3 free exports"),
        ("Web/blitzrecorder/index.html", "eligible BlitzReels subscribers"),
        ("Web/blitzrecorder/terms.html", "$7.99 per month"),
        ("Web/blitzrecorder/terms.html", "$49.99 per year"),
        ("Web/blitzrecorder/terms.html", "Eligible active BlitzReels subscribers"),
        ("Web/blitzrecorder/terms.html", "support@blitzreels.com"),
        ("Web/blitzrecorder/privacy.html", "macOS Keychain"),
        ("Web/blitzrecorder/privacy.html", "support@blitzreels.com"),
        ("Web/blitzrecorder/support.html", "support@blitzreels.com"),
        ("AppStore/BlitzReelsEntitlementContract.md", "Sign-In Redirect"),
        ("AppStore/BlitzReelsEntitlementContract.md", "must reject arbitrary"),
        ("AppStore/BlitzReelsEntitlementContract.md", "BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE=true"),
        ("AppStore/BlitzReelsEntitlementContract.md", "BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE=false"),
        ("AppStore/Screenshots.md", "02-plan-popover.png"),
        ("AppStore/Screenshots.md", "03-iphone-camera-controls.png"),
        ("Scripts/validate-launch-readiness.sh", "Scripts/app-store-connect-readiness.py --dry-run"),
        ("Scripts/validate-submission-artifacts.sh", "Scripts/app-store-connect-readiness.py --dry-run"),
        ("Scripts/validate-submission-artifacts.sh", "02-plan-popover.png"),
        ("Scripts/validate-submission-artifacts.sh", "03-iphone-camera-controls.png"),
        ("Scripts/validate-submission-artifacts.sh", "check_url_contains"),
        ("Scripts/validate-submission-artifacts.sh", "eligible BlitzReels subscribers"),
        ("Scripts/validate-submission-artifacts.sh", "macOS Keychain"),
        ("Scripts/validate-submission-artifacts.sh", "StoreKit"),
        ("Scripts/release-status.sh", "Scripts/preflight-app-store-local.sh"),
        ("Scripts/release-status.sh", "Scripts/collect-release-evidence.sh"),
        ("Scripts/capture-app-store-screenshots.sh", "BLITZRECORDER_SCREENSHOT_VARIANT"),
        ("Scripts/capture-app-store-screenshots.sh", "02-plan-popover.png"),
        ("Scripts/capture-app-store-screenshots.sh", "03-iphone-camera-controls.png"),
        ("Scripts/validate-submission-artifacts.sh", "validate_export_options_plist"),
        ("Scripts/validate-submission-artifacts.sh", "require_export_output"),
        ("Scripts/validate-submission-artifacts.sh", "--connect-timeout 10 --max-time 25"),
        ("Scripts/validate-submission-artifacts.sh", "build/AppStoreExports/macOS-export-options.plist"),
        ("Scripts/validate-submission-artifacts.sh", "build/AppStoreExports/iOS-export-options.plist"),
        ("Scripts/app-store-connect-readiness.py", "verify_app_store_version"),
        ("Scripts/app-store-connect-readiness.py", "verify_uploaded_build"),
        ("Scripts/app-store-connect-readiness.py", "verify_app_info_localization"),
        ("Scripts/app-store-connect-readiness.py", "verify_version_localization"),
        ("Scripts/app-store-connect-readiness.py", "verify_subscription_group_localization"),
        ("Scripts/app-store-connect-readiness.py", "verify_subscription_metadata"),
        ("Scripts/app-store-connect-readiness.py", "processingState"),
        ("Scripts/app-store-connect-readiness.py", "appStoreVersionLocalizations"),
        ("Scripts/app-store-connect-readiness.py", "appInfoLocalizations"),
        ("Scripts/app-store-connect-readiness.py", "AppStoreConnectFields.generated.json"),
        ("Scripts/app-store-connect-readiness.py", 'SUBSCRIPTION_REFERENCE_NAME = "BlitzRecorder Pro Monthly"'),
        ("Scripts/app-store-connect-readiness.py", 'SUBSCRIPTION_DESCRIPTION = "Unlimited exports in BlitzRecorder."'),
        ("Scripts/test-app-store-connect-readiness.py", "verify_app_info_localization"),
        ("Scripts/test-app-store-connect-readiness.py", "verify_version_localization"),
        ("Scripts/test-app-store-connect-readiness.py", "verify_subscription_group_localization"),
        ("Scripts/test-app-store-connect-readiness.py", "verify_subscription_metadata"),
        ("Scripts/test-app-store-connect-readiness.py", "App Store Connect readiness fixture tests passed."),
        ("Scripts/app-store-connect-bootstrap.py", "SUBSCRIPTION_REFERENCE_NAME = readiness.SUBSCRIPTION_REFERENCE_NAME"),
        ("Scripts/app-store-connect-bootstrap.py", "SUBSCRIPTION_DISPLAY_NAME = readiness.SUBSCRIPTION_DISPLAY_NAME"),
        ("Scripts/app-store-connect-bootstrap.py", "SUBSCRIPTION_DESCRIPTION = readiness.SUBSCRIPTION_DESCRIPTION"),
        ("Scripts/app-store-connect-bootstrap.py", 'description": SUBSCRIPTION_DESCRIPTION'),
        ("Scripts/test-app-store-connect-bootstrap.py", "SUBSCRIPTION_REFERENCE_NAME"),
        ("Scripts/test-app-store-connect-bootstrap.py", "SUBSCRIPTION_DISPLAY_NAME"),
        ("Scripts/test-app-store-connect-bootstrap.py", "SUBSCRIPTION_DESCRIPTION"),
        ("Scripts/test-app-store-connect-bootstrap.py", "App Store Connect bootstrap fixture tests passed."),
        ("Scripts/preflight-app-store-local.sh", "Scripts/test-app-store-connect-readiness.py"),
        ("Scripts/preflight-app-store-local.sh", "Scripts/test-app-store-connect-bootstrap.py"),
        ("Scripts/release-status.sh", "Scripts/test-app-store-connect-readiness.py"),
        ("Scripts/release-status.sh", "Scripts/test-app-store-connect-bootstrap.py"),
        ("Scripts/collect-release-evidence.sh", "Scripts/test-app-store-connect-readiness.py"),
        ("Scripts/collect-release-evidence.sh", "Scripts/test-app-store-connect-bootstrap.py"),
        ("Sources/BlitzRecorderApp/UI/MainView.swift", "BLITZRECORDER_SCREENSHOT_VARIANT"),
        ("Sources/BlitzRecorderApp/UI/MainView.swift", "Subscribe $49.99 / year"),
        ("Scripts/collect-release-evidence.sh", "Scripts/validate-launch-readiness.sh"),
        ("Scripts/collect-release-evidence.sh", "Scripts/preflight-app-store-local.sh"),
        ("Scripts/collect-release-evidence.sh", "Scripts/validate-entitlement-endpoint.sh"),
        ("Scripts/collect-release-evidence.sh", "BLITZRECORDER_INACTIVE_ENTITLEMENT_TOKEN"),
        ("Scripts/collect-release-evidence.sh", "BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE=true"),
        ("Scripts/collect-release-evidence.sh", "BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE=false"),
        ("Scripts/collect-release-evidence.sh", "build/release-evidence.md"),
        ("Scripts/collect-release-evidence.sh", "AppStore/AppStoreQuestionnaires.md"),
        ("Scripts/validate-entitlement-endpoint.sh", "BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE"),
        ("Scripts/prepare-app-store-review-package.sh", "AppStoreConnectFields.generated.json"),
        ("Scripts/prepare-app-store-review-package.sh", "AppStoreQuestionnaireAnswers.generated.json"),
        ("Scripts/prepare-app-store-review-package.sh", "PrivacyNutritionLabels.generated.json"),
        ("Scripts/prepare-app-store-review-package.sh", "Scripts/generate-app-store-connect-fields.py"),
        ("Scripts/prepare-app-store-review-package.sh", "Scripts/generate-app-store-questionnaire-answers.py"),
        ("Scripts/prepare-app-store-review-package.sh", "Scripts/generate-app-store-privacy-labels.py"),
        ("Scripts/generate-app-store-connect-fields.py", 'SUBSCRIPTION_PERIOD = "ONE_MONTH"'),
        ("Scripts/generate-app-store-connect-fields.py", "--check"),
        ("Scripts/generate-app-store-questionnaire-answers.py", "--check"),
        ("Scripts/generate-app-store-privacy-labels.py", "--check"),
        ("Scripts/validate-storekit-local.sh", SUBSCRIPTION_DESCRIPTION),
        ("Scripts/validate-launch-readiness.sh", "Scripts/generate-app-store-connect-fields.py --check"),
        ("Scripts/validate-launch-readiness.sh", "Scripts/generate-app-store-questionnaire-answers.py --check"),
        ("Scripts/validate-launch-readiness.sh", "Scripts/generate-app-store-privacy-labels.py --check"),
    ]

    for relative_path, expected in contains_checks:
        failures += check_text_contains(root, relative_path, expected)

    for relative_path, unexpected in [
        ("Web/blitzrecorder/terms.html", "intended as launch copy"),
        ("Web/blitzrecorder/privacy.html", "intended as product copy"),
        ("Web/blitzrecorder/support.html", "For launch"),
        ("Web/blitzrecorder/support.html", "support inbox or help desk"),
    ]:
        failures += check_text_excludes(root, relative_path, unexpected)
    failures += check_storekit_configuration(root)

    print(f"Expected macOS bundle ID: {MAC_BUNDLE_ID}")
    print(f"Expected iOS bundle ID: {IOS_BUNDLE_ID}")
    print(f"Expected subscription group: {SUBSCRIPTION_GROUP_NAME}")
    print(f"Expected subscription product: {SUBSCRIPTION_PRODUCT_ID}")
    print(f"Expected annual subscription product: {ANNUAL_SUBSCRIPTION_PRODUCT_ID}")
    print(f"Expected subscription period: {SUBSCRIPTION_PERIOD}")
    print(f"Expected USA price: {EXPECTED_PRICE_USD}")
    print(f"Expected annual USA price: {EXPECTED_ANNUAL_PRICE_USD}")
    print(f"Expected app version/build: {EXPECTED_MARKETING_VERSION} / {EXPECTED_BUILD_NUMBER}")
    return 1 if failures else 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Verify BlitzRecorder App Store Connect readiness.")
    parser.add_argument("--dry-run", action="store_true", help="Validate local expected values without calling Apple.")
    parser.add_argument("--api-base", default=API_BASE, help="App Store Connect API base URL.")
    parser.add_argument("--price-territory", default="USA", help="Territory code used to verify customer price.")
    parser.add_argument("--expected-price", default=EXPECTED_PRICE_USD, help="Expected customer price in the territory.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(__file__).resolve().parents[1]
    local_status = check_local_files(root)
    if args.dry_run:
        print("Dry run complete; live App Store Connect records were not queried.")
        return local_status

    if local_status != 0:
        return local_status
    return check_live(args)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ReadinessError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
