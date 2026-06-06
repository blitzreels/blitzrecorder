#!/usr/bin/env python3
"""Update BlitzRecorder release version/build references."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def replace(path: str, pattern: str, replacement: str) -> None:
    file_path = ROOT / path
    text = file_path.read_text()
    updated, count = re.subn(pattern, replacement, text)
    if count == 0:
        raise SystemExit(f"error: no replacement made in {path}")
    file_path.write_text(updated)


def replace_if_present(path: str, pattern: str, replacement: str) -> None:
    file_path = ROOT / path
    text = file_path.read_text()
    updated, _ = re.subn(pattern, replacement, text)
    file_path.write_text(updated)


def main() -> None:
    parser = argparse.ArgumentParser(description="Update release version and build number.")
    parser.add_argument("version", help="Marketing version, for example 0.1.1")
    parser.add_argument("build", help="Build number, for example 2")
    args = parser.parse_args()

    if not re.fullmatch(r"\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?", args.version):
        raise SystemExit("error: version must look like 0.1.1")
    if not re.fullmatch(r"\d+", args.build):
        raise SystemExit("error: build must be a positive integer")

    replace("project.yml", r'MARKETING_VERSION: "[^"]+"', f'MARKETING_VERSION: "{args.version}"')
    replace("project.yml", r'CURRENT_PROJECT_VERSION: "[^"]+"', f'CURRENT_PROJECT_VERSION: "{args.build}"')

    shell_constants = [
        "Scripts/preflight-app-store-local.sh",
        "Scripts/validate-submission-artifacts.sh",
    ]
    for path in shell_constants:
        replace(path, r'EXPECTED_MARKETING_VERSION="[^"]+"', f'EXPECTED_MARKETING_VERSION="{args.version}"')
        replace(path, r'EXPECTED_BUILD_NUMBER="[^"]+"', f'EXPECTED_BUILD_NUMBER="{args.build}"')

    replace_if_present(
        "Scripts/app-store-connect-readiness.py",
        r'EXPECTED_MARKETING_VERSION = "[^"]+"',
        f'EXPECTED_MARKETING_VERSION = "{args.version}"',
    )
    replace_if_present(
        "Scripts/app-store-connect-readiness.py",
        r'EXPECTED_BUILD_NUMBER = "[^"]+"',
        f'EXPECTED_BUILD_NUMBER = "{args.build}"',
    )
    replace_if_present(
        "Scripts/validate-launch-readiness.sh",
        r'expected_marketing_version="[^"]+"',
        f'expected_marketing_version="{args.version}"',
    )
    replace_if_present(
        "Scripts/validate-launch-readiness.sh",
        r'expected_build_number="[^"]+"',
        f'expected_build_number="{args.build}"',
    )
    replace_if_present("Scripts/prepare-app-store-review-package.sh", r'VERSION="[^"]+"', f'VERSION="{args.version}"')
    replace_if_present("Scripts/prepare-app-store-review-package.sh", r'BUILD="[^"]+"', f'BUILD="{args.build}"')
    replace(
        "Web/blitzrecorder/lib/release.ts",
        r'FALLBACK_VERSION = "[^"]+"',
        f'FALLBACK_VERSION = "{args.version}"',
    )
    replace_if_present(
        "Scripts/collect-release-evidence.sh",
        r'Version/build: \\`[^`]+\\`',
        f'Version/build: \\`{args.version} / {args.build}\\`',
    )

    print(f"Updated BlitzRecorder version to {args.version} build {args.build}")


if __name__ == "__main__":
    main()
