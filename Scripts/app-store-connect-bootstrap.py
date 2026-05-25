#!/usr/bin/env python3
"""Bootstrap App Store Connect resources for BlitzRecorder.

Default mode is a dry run. Pass --apply to create missing resources that the
App Store Connect API can create safely:

  - Bundle IDs
  - Subscription group for the Mac app record
  - Monthly subscription product
  - en-US subscription group and subscription localizations

App records still need to be created in App Store Connect first. Apple's app
record flow requires account-level choices that should stay manual.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
READINESS_PATH = ROOT / "Scripts/app-store-connect-readiness.py"


def load_readiness_module() -> Any:
    spec = importlib.util.spec_from_file_location("app_store_connect_readiness", READINESS_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {READINESS_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


readiness = load_readiness_module()

MAC_BUNDLE_ID = readiness.MAC_BUNDLE_ID
IOS_BUNDLE_ID = readiness.IOS_BUNDLE_ID
SUBSCRIPTION_PRODUCT_ID = readiness.SUBSCRIPTION_PRODUCT_ID
SUBSCRIPTION_GROUP_NAME = readiness.SUBSCRIPTION_GROUP_NAME
SUBSCRIPTION_REFERENCE_NAME = readiness.SUBSCRIPTION_REFERENCE_NAME
SUBSCRIPTION_DISPLAY_NAME = readiness.SUBSCRIPTION_DISPLAY_NAME
SUBSCRIPTION_DESCRIPTION = readiness.SUBSCRIPTION_DESCRIPTION
SUBSCRIPTION_LOCALE = readiness.SUBSCRIPTION_LOCALE
SUBSCRIPTION_PERIOD = readiness.SUBSCRIPTION_PERIOD
EXPECTED_PRICE_USD = readiness.EXPECTED_PRICE_USD


class BootstrapError(RuntimeError):
    pass


class MutableAppStoreConnectClient(readiness.AppStoreConnectClient):
    def request_json(self, method: str, path: str, payload: dict[str, Any] | None = None) -> dict[str, Any]:
        url = f"{self.api_base}{path}"
        body = None if payload is None else json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(
            url,
            data=body,
            method=method,
            headers={
                "Authorization": f"Bearer {self.token}",
                "Accept": "application/json",
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                text = response.read().decode("utf-8")
                return json.loads(text) if text else {}
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            raise BootstrapError(f"{method} {url} failed with HTTP {error.code}: {detail}") from error

    def post(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        return self.request_json("POST", path, payload)


def credentials_token() -> str:
    key_id = readiness.os.environ.get("ASC_KEY_ID")
    issuer_id = readiness.os.environ.get("ASC_ISSUER_ID")
    if not key_id or not issuer_id:
        raise BootstrapError("Set ASC_KEY_ID and ASC_ISSUER_ID.")

    key_path, temp_dir = readiness.private_key_path_from_env()
    try:
        return readiness.make_jwt(key_id, issuer_id, key_path)
    finally:
        if temp_dir is not None:
            temp_dir.cleanup()


def announce(action: str, apply: bool) -> None:
    prefix = "create" if apply else "would create"
    print(f"• {prefix} {action}")


def find_bundle_id(client: MutableAppStoreConnectClient, identifier: str) -> dict[str, Any] | None:
    bundle_ids = client.get_all("/v1/bundleIds", {"filter[identifier]": identifier, "limit": "200"})
    for item in bundle_ids:
        if item.get("attributes", {}).get("identifier") == identifier:
            return item
    return None


def ensure_bundle_id(
    client: MutableAppStoreConnectClient,
    *,
    identifier: str,
    name: str,
    platform: str,
    apply: bool,
) -> dict[str, Any] | None:
    existing = find_bundle_id(client, identifier)
    if existing:
        print(f"✓ bundle ID exists: {identifier} ({existing.get('id')})")
        return existing

    announce(f"bundle ID {identifier} ({platform})", apply)
    if not apply:
        return None

    response = client.post(
        "/v1/bundleIds",
        {
            "data": {
                "type": "bundleIds",
                "attributes": {
                    "identifier": identifier,
                    "name": name,
                    "platform": platform,
                },
            }
        },
    )
    item = response.get("data")
    print(f"✓ created bundle ID: {identifier} ({item.get('id')})")
    return item


def find_app(client: MutableAppStoreConnectClient, bundle_id: str) -> dict[str, Any] | None:
    apps = client.get_all("/v1/apps", {"limit": "200"})
    for item in apps:
        if item.get("attributes", {}).get("bundleId") == bundle_id:
            return item
    return None


def find_subscription_group(
    client: MutableAppStoreConnectClient,
    app_id: str,
    reference_name: str,
) -> dict[str, Any] | None:
    groups = client.get_all(f"/v1/apps/{app_id}/subscriptionGroups", {"limit": "200"})
    for group in groups:
        if group.get("attributes", {}).get("referenceName") == reference_name:
            return group
    return None


def ensure_subscription_group(
    client: MutableAppStoreConnectClient,
    *,
    app_id: str,
    apply: bool,
) -> dict[str, Any] | None:
    existing = find_subscription_group(client, app_id, SUBSCRIPTION_GROUP_NAME)
    if existing:
        print(f"✓ subscription group exists: {SUBSCRIPTION_GROUP_NAME} ({existing.get('id')})")
        return existing

    announce(f"subscription group {SUBSCRIPTION_GROUP_NAME}", apply)
    if not apply:
        return None

    response = client.post(
        "/v1/subscriptionGroups",
        {
            "data": {
                "type": "subscriptionGroups",
                "attributes": {"referenceName": SUBSCRIPTION_GROUP_NAME},
                "relationships": {
                    "app": {
                        "data": {
                            "type": "apps",
                            "id": app_id,
                        }
                    }
                },
            }
        },
    )
    item = response.get("data")
    print(f"✓ created subscription group: {SUBSCRIPTION_GROUP_NAME} ({item.get('id')})")
    return item


def ensure_group_localization(
    client: MutableAppStoreConnectClient,
    *,
    group_id: str,
    apply: bool,
) -> None:
    localizations = client.get_all(f"/v1/subscriptionGroups/{group_id}/subscriptionGroupLocalizations")
    if any(item.get("attributes", {}).get("locale") == SUBSCRIPTION_LOCALE for item in localizations):
        print(f"✓ subscription group {SUBSCRIPTION_LOCALE} localization exists")
        return

    announce(f"subscription group {SUBSCRIPTION_LOCALE} localization", apply)
    if not apply:
        return

    client.post(
        "/v1/subscriptionGroupLocalizations",
        {
            "data": {
                "type": "subscriptionGroupLocalizations",
                "attributes": {
                    "locale": SUBSCRIPTION_LOCALE,
                    "name": SUBSCRIPTION_GROUP_NAME,
                },
                "relationships": {
                    "subscriptionGroup": {
                        "data": {
                            "type": "subscriptionGroups",
                            "id": group_id,
                        }
                    }
                },
            }
        },
    )
    print(f"✓ created subscription group {SUBSCRIPTION_LOCALE} localization")


def find_subscription(
    client: MutableAppStoreConnectClient,
    group_id: str,
    product_id: str,
) -> dict[str, Any] | None:
    subscriptions = client.get_all(
        f"/v1/subscriptionGroups/{group_id}/subscriptions",
        {"filter[productId]": product_id, "limit": "200"},
    )
    for subscription in subscriptions:
        if subscription.get("attributes", {}).get("productId") == product_id:
            return subscription
    return None


def ensure_subscription(
    client: MutableAppStoreConnectClient,
    *,
    group_id: str,
    apply: bool,
) -> dict[str, Any] | None:
    existing = find_subscription(client, group_id, SUBSCRIPTION_PRODUCT_ID)
    if existing:
        print(f"✓ subscription product exists: {SUBSCRIPTION_PRODUCT_ID} ({existing.get('id')})")
        return existing

    announce(f"subscription product {SUBSCRIPTION_PRODUCT_ID}", apply)
    if not apply:
        return None

    response = client.post(
        "/v1/subscriptions",
        {
            "data": {
                "type": "subscriptions",
                "attributes": {
                    "name": SUBSCRIPTION_REFERENCE_NAME,
                    "productId": SUBSCRIPTION_PRODUCT_ID,
                    "subscriptionPeriod": SUBSCRIPTION_PERIOD,
                    "familySharable": False,
                    "reviewNote": "Unlocks unlimited exports and renders in BlitzRecorder after 3 free exports.",
                    "groupLevel": 1,
                    "availableInAllTerritories": True,
                },
                "relationships": {
                    "group": {
                        "data": {
                            "type": "subscriptionGroups",
                            "id": group_id,
                        }
                    }
                },
            }
        },
    )
    item = response.get("data")
    print(f"✓ created subscription product: {SUBSCRIPTION_PRODUCT_ID} ({item.get('id')})")
    return item


def ensure_subscription_localization(
    client: MutableAppStoreConnectClient,
    *,
    subscription_id: str,
    apply: bool,
) -> None:
    localizations = client.get_all(f"/v1/subscriptions/{subscription_id}/subscriptionLocalizations")
    if any(item.get("attributes", {}).get("locale") == SUBSCRIPTION_LOCALE for item in localizations):
        print(f"✓ subscription {SUBSCRIPTION_LOCALE} localization exists")
        return

    announce(f"subscription {SUBSCRIPTION_LOCALE} localization", apply)
    if not apply:
        return

    client.post(
        "/v1/subscriptionLocalizations",
        {
            "data": {
                "type": "subscriptionLocalizations",
                "attributes": {
                    "locale": SUBSCRIPTION_LOCALE,
                    "name": SUBSCRIPTION_DISPLAY_NAME,
                    "description": SUBSCRIPTION_DESCRIPTION,
                },
                "relationships": {
                    "subscription": {
                        "data": {
                            "type": "subscriptions",
                            "id": subscription_id,
                        }
                    }
                },
            }
        },
    )
    print(f"✓ created subscription {SUBSCRIPTION_LOCALE} localization")


def print_manual_steps() -> None:
    print()
    print("Manual App Store Connect steps that remain outside this script:")
    print(f"- Create the macOS app record for {MAC_BUNDLE_ID} if it is missing.")
    print(f"- Create the iOS companion app record for {IOS_BUNDLE_ID} if it is missing.")
    print(f"- Configure subscription pricing to ${EXPECTED_PRICE_USD}/month in USA and comparable App Store territories.")
    print("- Add screenshots, privacy nutrition labels, review notes, and submit the apps/IAP for review.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Bootstrap BlitzRecorder App Store Connect resources.")
    parser.add_argument("--apply", action="store_true", help="Create missing API-manageable resources.")
    parser.add_argument("--api-base", default=readiness.API_BASE, help="App Store Connect API base URL.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.apply:
        print("Dry run. Pass --apply to create missing API-manageable resources.")
        print(f"Expected macOS bundle ID: {MAC_BUNDLE_ID}")
        print(f"Expected iOS bundle ID: {IOS_BUNDLE_ID}")
        print(f"Expected subscription group: {SUBSCRIPTION_GROUP_NAME}")
        print(f"Expected subscription product: {SUBSCRIPTION_PRODUCT_ID}")
        print(f"Expected period/price: {SUBSCRIPTION_PERIOD} / ${EXPECTED_PRICE_USD} USA")
        print_manual_steps()
        return 0

    token = credentials_token()
    client = MutableAppStoreConnectClient(token=token, api_base=args.api_base)

    ensure_bundle_id(
        client,
        identifier=MAC_BUNDLE_ID,
        name="BlitzRecorder",
        platform="MAC_OS",
        apply=True,
    )
    ensure_bundle_id(
        client,
        identifier=IOS_BUNDLE_ID,
        name="BlitzRecorder Camera",
        platform="IOS",
        apply=True,
    )

    mac_app = find_app(client, MAC_BUNDLE_ID)
    ios_app = find_app(client, IOS_BUNDLE_ID)
    if mac_app:
        print(f"✓ macOS app record exists: {MAC_BUNDLE_ID} ({mac_app.get('id')})")
    else:
        print(f"pending: create the macOS app record manually for {MAC_BUNDLE_ID}", file=sys.stderr)

    if ios_app:
        print(f"✓ iOS companion app record exists: {IOS_BUNDLE_ID} ({ios_app.get('id')})")
    else:
        print(f"pending: create the iOS companion app record manually for {IOS_BUNDLE_ID}", file=sys.stderr)

    if not mac_app:
        print_manual_steps()
        return 1

    group = ensure_subscription_group(client, app_id=mac_app["id"], apply=True)
    if group:
        ensure_group_localization(client, group_id=group["id"], apply=True)
        subscription = ensure_subscription(client, group_id=group["id"], apply=True)
        if subscription:
            ensure_subscription_localization(client, subscription_id=subscription["id"], apply=True)

    print_manual_steps()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (BootstrapError, readiness.ReadinessError, RuntimeError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
