#!/usr/bin/env python3
"""Fixture tests for the App Store Connect readiness verifier."""

from __future__ import annotations

import copy
import importlib.util
import io
import sys
from contextlib import redirect_stdout
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "Scripts" / "app-store-connect-readiness.py"


def load_readiness_module() -> Any:
    spec = importlib.util.spec_from_file_location("app_store_connect_readiness", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {MODULE_PATH.relative_to(ROOT)}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


readiness = load_readiness_module()


class FakeClient:
    def __init__(self, responses: dict[str, list[dict[str, Any]]]) -> None:
        self.responses = responses

    def get_all(self, path: str, query: dict[str, str] | None = None) -> list[dict[str, Any]]:
        _ = query
        return copy.deepcopy(self.responses.get(path, []))


def localization(identifier: str, attributes: dict[str, Any]) -> dict[str, Any]:
    return {"id": identifier, "attributes": attributes}


def fixture_client(
    expected: dict[str, Any],
    *,
    mac_subtitle: str | None = None,
    ios_description: str | None = None,
    group_name: str | None = None,
    subscription_description: str | None = None,
) -> FakeClient:
    mac = expected["apps"]["macOS"]
    ios = expected["apps"]["iOS"]

    mac_info = {
        "locale": mac["primaryLocale"],
        "name": mac["appName"],
        "subtitle": mac_subtitle if mac_subtitle is not None else mac["subtitle"],
        "privacyPolicyUrl": mac["privacyPolicyUrl"],
    }
    ios_info = {
        "locale": ios["primaryLocale"],
        "name": ios["appName"],
        "subtitle": ios["subtitle"],
        "privacyPolicyUrl": ios["privacyPolicyUrl"],
    }
    mac_version = {
        "locale": mac["primaryLocale"],
        "description": mac["description"],
        "keywords": mac["keywords"],
        "promotionalText": mac["promotionalText"],
        "supportUrl": mac["supportUrl"],
        "marketingUrl": mac["marketingUrl"],
    }
    ios_version = {
        "locale": ios["primaryLocale"],
        "description": ios_description if ios_description is not None else ios["description"],
        "keywords": ios["keywords"],
        "promotionalText": ios["promotionalText"],
        "supportUrl": ios["supportUrl"],
        "marketingUrl": ios["marketingUrl"],
    }
    subscription = expected["subscription"]

    return FakeClient(
        {
            "/v1/apps/mac-app/appInfos": [{"id": "mac-info"}],
            "/v1/apps/ios-app/appInfos": [{"id": "ios-info"}],
            "/v1/appInfos/mac-info/appInfoLocalizations": [localization("mac-info-en", mac_info)],
            "/v1/appInfos/ios-info/appInfoLocalizations": [localization("ios-info-en", ios_info)],
            "/v1/appStoreVersions/mac-version/appStoreVersionLocalizations": [
                localization("mac-version-en", mac_version)
            ],
            "/v1/appStoreVersions/ios-version/appStoreVersionLocalizations": [
                localization("ios-version-en", ios_version)
            ],
            "/v1/subscriptionGroups/group/subscriptionGroupLocalizations": [
                localization(
                    "group-en",
                    {
                        "locale": readiness.SUBSCRIPTION_LOCALE,
                        "name": group_name if group_name is not None else subscription["groupDisplayName"],
                    },
                )
            ],
            "/v1/subscriptions/sub/subscriptionLocalizations": [
                localization(
                    "sub-en",
                    {
                        "locale": readiness.SUBSCRIPTION_LOCALE,
                        "name": subscription["displayName"],
                        "description": (
                            subscription_description
                            if subscription_description is not None
                            else subscription["description"]
                        ),
                    },
                )
            ],
        }
    )


def quiet_call(callable_: Any, *args: Any, **kwargs: Any) -> int:
    with redirect_stdout(io.StringIO()):
        return int(callable_(*args, **kwargs))


def assert_status(label: str, actual: int, expected: int) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: got {actual}, expected {expected}")


def test_matching_fixture(expected: dict[str, Any]) -> None:
    client = fixture_client(expected)
    mac_app = {"id": "mac-app"}
    ios_app = {"id": "ios-app"}
    mac_version = {"id": "mac-version"}
    ios_version = {"id": "ios-version"}
    subscription = {
        "id": "sub",
        "attributes": {
            "name": expected["subscription"]["referenceName"],
        },
    }

    assert_status(
        "macOS app info localization",
        quiet_call(
            readiness.verify_app_info_localization,
            client,
            app=mac_app,
            label="macOS",
            expected_app=expected["apps"]["macOS"],
        ),
        0,
    )
    assert_status(
        "iOS app info localization",
        quiet_call(
            readiness.verify_app_info_localization,
            client,
            app=ios_app,
            label="iOS companion",
            expected_app=expected["apps"]["iOS"],
        ),
        0,
    )
    assert_status(
        "macOS version localization",
        quiet_call(
            readiness.verify_version_localization,
            client,
            version=mac_version,
            label="macOS",
            expected_app=expected["apps"]["macOS"],
        ),
        0,
    )
    assert_status(
        "iOS version localization",
        quiet_call(
            readiness.verify_version_localization,
            client,
            version=ios_version,
            label="iOS companion",
            expected_app=expected["apps"]["iOS"],
        ),
        0,
    )
    assert_status(
        "subscription group localization",
        quiet_call(readiness.verify_subscription_group_localization, client, group_id="group"),
        0,
    )
    assert_status(
        "subscription metadata",
        quiet_call(readiness.verify_subscription_metadata, client, subscription=subscription),
        0,
    )


def test_mismatching_fixture(expected: dict[str, Any]) -> None:
    subscription = {
        "id": "sub",
        "attributes": {
            "name": expected["subscription"]["referenceName"],
        },
    }

    assert_status(
        "mismatched macOS subtitle",
        quiet_call(
            readiness.verify_app_info_localization,
            fixture_client(expected, mac_subtitle="Wrong subtitle"),
            app={"id": "mac-app"},
            label="macOS",
            expected_app=expected["apps"]["macOS"],
        ),
        1,
    )
    assert_status(
        "mismatched iOS description",
        quiet_call(
            readiness.verify_version_localization,
            fixture_client(expected, ios_description="Wrong description"),
            version={"id": "ios-version"},
            label="iOS companion",
            expected_app=expected["apps"]["iOS"],
        ),
        1,
    )
    assert_status(
        "mismatched subscription group display name",
        quiet_call(
            readiness.verify_subscription_group_localization,
            fixture_client(expected, group_name="Wrong group"),
            group_id="group",
        ),
        1,
    )
    assert_status(
        "mismatched subscription description",
        quiet_call(
            readiness.verify_subscription_metadata,
            fixture_client(expected, subscription_description="Wrong description"),
            subscription=subscription,
        ),
        1,
    )


def main() -> int:
    expected = readiness.expected_fields()
    test_matching_fixture(expected)
    test_mismatching_fixture(expected)
    print("App Store Connect readiness fixture tests passed.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
