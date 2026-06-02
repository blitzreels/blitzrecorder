#!/usr/bin/env python3
"""Sync GitHub labels from .github/labels.json."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LABELS_PATH = ROOT / ".github" / "labels.json"


def run(args: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    print("+", " ".join(args))
    return subprocess.run(args, cwd=ROOT, check=check, text=True, capture_output=True)


def repo_from_origin() -> str | None:
    result = subprocess.run(
        ["git", "remote", "get-url", "origin"],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        return None
    remote = result.stdout.strip()
    if remote.startswith("git@github.com:"):
        return remote.removeprefix("git@github.com:").removesuffix(".git")
    if remote.startswith("https://github.com/"):
        return remote.removeprefix("https://github.com/").removesuffix(".git")
    return None


def gh_json(args: list[str]) -> object:
    result = subprocess.run(args, cwd=ROOT, check=True, text=True, capture_output=True)
    return json.loads(result.stdout)


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync GitHub labels from .github/labels.json.")
    parser.add_argument("--repo", help="GitHub repo in OWNER/REPO form. Defaults to origin.")
    parser.add_argument("--apply", action="store_true", help="Apply changes. Default is dry-run.")
    args = parser.parse_args()

    repo = args.repo or repo_from_origin()
    if not repo:
        print("error: could not infer GitHub repo from origin; pass --repo OWNER/REPO", file=sys.stderr)
        return 2

    labels = json.loads(LABELS_PATH.read_text())
    existing_items = gh_json(["gh", "label", "list", "--repo", repo, "--limit", "200", "--json", "name,color,description"])
    existing = {item["name"]: item for item in existing_items}  # type: ignore[index]

    planned = 0
    for label in labels:
        name = label["name"]
        color = label["color"]
        description = label["description"]
        current = existing.get(name)
        if not current:
            cmd = ["gh", "label", "create", name, "--repo", repo, "--color", color, "--description", description]
        elif current.get("color", "").lower() != color.lower() or (current.get("description") or "") != description:
            cmd = ["gh", "label", "edit", name, "--repo", repo, "--color", color, "--description", description]
        else:
            continue

        planned += 1
        print("+", " ".join(cmd))
        if args.apply:
            subprocess.run(cmd, cwd=ROOT, check=True)

    if planned == 0:
        print("GitHub labels already match .github/labels.json.")
    elif not args.apply:
        print("Dry run only. Re-run with --apply to sync labels.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
