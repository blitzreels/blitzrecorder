#!/usr/bin/env python3
"""Sync local generated evidence into the human App Store release worksheet."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GENERATED = ROOT / "AppStore" / "ReleaseEvidence.generated.md"
WORKSHEET = ROOT / "AppStore" / "ReleaseEvidence.md"
REVIEW_PACKAGE_MANIFEST = ROOT / "build" / "AppStoreReviewPackage" / "BlitzRecorder-0.1.0-build-1" / "Manifest.md"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def parse_generated(markdown: str) -> tuple[str, dict[str, dict[str, str]]]:
    generated_at = re.search(r"^Generated: (.+)$", markdown, re.MULTILINE)
    sections: dict[str, dict[str, str]] = {}
    current: str | None = None

    for line in markdown.splitlines():
        if line.startswith("### "):
            current = line[4:].strip()
            sections[current] = {}
            continue
        if current is None or not line.startswith("- "):
            continue
        key, _, value = line[2:].partition(": ")
        if key and value:
            sections[current][key] = value

    return (generated_at.group(1) if generated_at else "unknown"), sections


def command_evidence(sections: dict[str, dict[str, str]], label: str) -> str:
    section = sections.get(label, {})
    status = section.get("Status", "missing")
    log = clean_code(section.get("Log"))
    reason = section.get("Reason")
    if status == "passed" and log:
        return f"passed (`{log}`)"
    if status == "pending" and reason:
        return f"pending ({reason})"
    if status == "failed" and log:
        return f"failed (`{log}`)"
    return status


def first_matching_line(log_path: str | None, pattern: str, fallback: str) -> str:
    if not log_path:
        return fallback
    resolved = ROOT / clean_code(log_path)
    if not resolved.exists():
        return fallback
    regex = re.compile(pattern)
    for line in resolved.read_text(encoding="utf-8", errors="replace").splitlines():
        if regex.search(line):
            return normalize_log_line(line)
    return fallback


def normalize_log_line(line: str) -> str:
    clean = line.strip()
    if clean.startswith("✓ "):
        return f"passed ({clean[2:]})"
    return clean


def test_summary(log_path: str | None) -> str:
    if not log_path:
        return "pending"
    clean_log_path = clean_code(log_path)
    resolved = ROOT / clean_log_path
    if not resolved.exists():
        return "pending"

    text = resolved.read_text(encoding="utf-8", errors="replace")
    matches = re.findall(r"Executed (\d+) tests, with (\d+) failures", text)
    if not matches:
        return f"passed (`{clean_log_path}`)"
    count, failures = max(((int(count), int(failures)) for count, failures in matches), key=lambda item: item[0])
    return f"{count} tests, {failures} failures (`{clean_log_path}`)"


def review_package_summary() -> str:
    if not REVIEW_PACKAGE_MANIFEST.exists():
        return "pending"
    return f"prepared (`{REVIEW_PACKAGE_MANIFEST.relative_to(ROOT)}`)"


def clean_code(value: str | None) -> str | None:
    if value is None:
        return None
    return value.strip().strip("`")


def replace_section(markdown: str, title: str, next_title: str, body: str) -> str:
    pattern = re.compile(
        rf"(^## {re.escape(title)}\n.*?^Evidence:\n\n)(.*?)(?=^## {re.escape(next_title)}\n)",
        re.MULTILINE | re.DOTALL,
    )
    replacement = rf"\1{body.rstrip()}\n\n"
    updated, count = pattern.subn(replacement, markdown)
    if count != 1:
        raise SystemExit(f"Unable to update section: {title}")
    return updated


def main() -> None:
    generated = read(GENERATED)
    generated_at, sections = parse_generated(generated)

    local_preflight_log = sections.get("Local Build/Test Preflight", {}).get("Log")
    submission_log = sections.get("Submission Artifacts", {}).get("Log")

    local_body = f"""Synced from `AppStore/ReleaseEvidence.generated.md` generated {generated_at}.

- `Scripts/preflight-app-store-local.sh`: {command_evidence(sections, "Local Build/Test Preflight")}
- `Scripts/validate-launch-readiness.sh`: {command_evidence(sections, "Launch Readiness")}
- `Scripts/test-app-store-connect-readiness.py`: {command_evidence(sections, "App Store Connect Verifier Fixtures")}
- `Scripts/test-app-store-connect-bootstrap.py`: {command_evidence(sections, "App Store Connect Bootstrap Fixtures")}
- `Scripts/app-store-connect-readiness.py --dry-run`: {command_evidence(sections, "App Store Connect Dry Run")}
- `Scripts/validate-storekit-local.sh`: {command_evidence(sections, "StoreKit Local Configuration")}
- `Scripts/validate-submission-artifacts.sh`: {command_evidence(sections, "Submission Artifacts")}
- Generated evidence report `AppStore/ReleaseEvidence.generated.md`: generated {generated_at}
- Review package manifest: {review_package_summary()}
- Test count/result: {test_summary(local_preflight_log)}
"""

    public_checks = [
        ("Landing page HTTP 200", r"https://www\.blitzreels\.com/blitzrecorder returns HTTP 200"),
        ("Privacy policy HTTP 200", r"https://www\.blitzreels\.com/blitzrecorder/privacy returns HTTP 200"),
        ("Terms HTTP 200", r"https://www\.blitzreels\.com/blitzrecorder/terms returns HTTP 200"),
        ("Support HTTP 200", r"https://www\.blitzreels\.com/blitzrecorder/support returns HTTP 200"),
        ("Landing page pricing copy", r"https://www\.blitzreels\.com/blitzrecorder contains \$4\.99 per month"),
        ("Landing page free quota copy", r"https://www\.blitzreels\.com/blitzrecorder contains 3 free exports"),
        ("Landing page BlitzReels copy", r"https://www\.blitzreels\.com/blitzrecorder contains eligible BlitzReels subscribers"),
        ("Privacy page Keychain copy", r"https://www\.blitzreels\.com/blitzrecorder/privacy contains macOS Keychain"),
        ("Privacy page StoreKit copy", r"https://www\.blitzreels\.com/blitzrecorder/privacy contains StoreKit"),
        ("Terms page pricing copy", r"https://www\.blitzreels\.com/blitzrecorder/terms contains \$4\.99 per month"),
        (
            "Terms page included access copy",
            r"https://www\.blitzreels\.com/blitzrecorder/terms contains Eligible active BlitzReels subscribers",
        ),
        ("Support page contact copy", r"https://www\.blitzreels\.com/blitzrecorder/support contains support@blitzreels\.com"),
        ("Unauthenticated sign-in redirects to BlitzReels login", r"sign-in\?return_to=blitzrecorder://auth/blitzreels redirects to /login"),
        ("Invalid sign-in callback returns HTTP 400", r"sign-in\?return_to=https://example\.com returns HTTP 400"),
        ("Unauthenticated entitlement endpoint returns HTTP 401", r"/api/blitzrecorder/entitlement returns HTTP 401"),
    ]
    clean_submission_log = clean_code(submission_log)
    public_lines = [f"Synced from `{clean_submission_log}` generated {generated_at}."]
    for label, pattern in public_checks:
        line = first_matching_line(submission_log, pattern, "pending")
        public_lines.append(f"- {label}: {line}")
    public_body = "\n".join(public_lines) + "\n"

    worksheet = read(WORKSHEET)
    worksheet = replace_section(worksheet, "Local Build Evidence", "Public URL Evidence", local_body)
    worksheet = replace_section(worksheet, "Public URL Evidence", "App Store Connect Evidence", public_body)

    entitlement_body = f"""- StoreKit local configuration test: {command_evidence(sections, "StoreKit Local Configuration")}
- StoreKit sandbox subscription test: pending
- Restore purchases test: pending
- Positive BlitzReels entitlement response with `"active": true`: {command_evidence(sections, "Positive BlitzReels Entitlement Token Check")}
- Negative BlitzReels entitlement response with `"active": false`: {command_evidence(sections, "Negative BlitzReels Entitlement Token Check")}
"""
    worksheet = replace_section(worksheet, "Subscription And Entitlement Evidence", "Device QA Evidence", entitlement_body)
    WORKSHEET.write_text(worksheet, encoding="utf-8")
    print(f"Release evidence worksheet updated: {WORKSHEET.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
