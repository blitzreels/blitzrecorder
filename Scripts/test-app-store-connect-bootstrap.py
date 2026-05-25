#!/usr/bin/env python3
"""Fixture tests for the App Store Connect bootstrap payloads."""

from __future__ import annotations

import importlib.util
import io
import sys
from contextlib import redirect_stdout
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "Scripts" / "app-store-connect-bootstrap.py"


def load_bootstrap_module() -> Any:
    spec = importlib.util.spec_from_file_location("app_store_connect_bootstrap", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {MODULE_PATH.relative_to(ROOT)}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


bootstrap = load_bootstrap_module()


class FakeClient:
    def __init__(self) -> None:
        self.posts: list[tuple[str, dict[str, Any]]] = []

    def get_all(self, path: str, query: dict[str, str] | None = None) -> list[dict[str, Any]]:
        _ = path
        _ = query
        return []

    def post(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        self.posts.append((path, payload))
        resource_type = payload["data"]["type"]
        return {"data": {"id": f"{resource_type}-fixture", "type": resource_type}}


def quiet_call(callable_: Any, *args: Any, **kwargs: Any) -> Any:
    with redirect_stdout(io.StringIO()):
        return callable_(*args, **kwargs)


def posted_payload(client: FakeClient, path: str) -> dict[str, Any]:
    matches = [payload for posted_path, payload in client.posts if posted_path == path]
    if not matches:
        raise AssertionError(f"missing POST {path}")
    return matches[-1]


def assert_equal(label: str, actual: Any, expected: Any) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: got {actual!r}, expected {expected!r}")


def test_subscription_payloads() -> None:
    client = FakeClient()

    quiet_call(bootstrap.ensure_group_localization, client, group_id="group", apply=True)
    quiet_call(bootstrap.ensure_subscription, client, group_id="group", apply=True)
    quiet_call(bootstrap.ensure_subscription_localization, client, subscription_id="sub", apply=True)

    group_localization = posted_payload(client, "/v1/subscriptionGroupLocalizations")
    group_attributes = group_localization["data"]["attributes"]
    assert_equal("group locale", group_attributes["locale"], bootstrap.SUBSCRIPTION_LOCALE)
    assert_equal("group display name", group_attributes["name"], bootstrap.SUBSCRIPTION_GROUP_NAME)

    subscription = posted_payload(client, "/v1/subscriptions")
    subscription_attributes = subscription["data"]["attributes"]
    assert_equal("subscription reference name", subscription_attributes["name"], bootstrap.SUBSCRIPTION_REFERENCE_NAME)
    assert_equal("subscription product id", subscription_attributes["productId"], bootstrap.SUBSCRIPTION_PRODUCT_ID)
    assert_equal("subscription period", subscription_attributes["subscriptionPeriod"], bootstrap.SUBSCRIPTION_PERIOD)

    localization = posted_payload(client, "/v1/subscriptionLocalizations")
    localization_attributes = localization["data"]["attributes"]
    assert_equal("subscription locale", localization_attributes["locale"], bootstrap.SUBSCRIPTION_LOCALE)
    assert_equal("subscription display name", localization_attributes["name"], bootstrap.SUBSCRIPTION_DISPLAY_NAME)
    assert_equal("subscription description", localization_attributes["description"], bootstrap.SUBSCRIPTION_DESCRIPTION)


def main() -> int:
    test_subscription_payloads()
    print("App Store Connect bootstrap fixture tests passed.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
