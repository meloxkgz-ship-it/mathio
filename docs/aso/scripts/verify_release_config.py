#!/usr/bin/env python3
"""Verify Xcode and ASC helper scripts agree on the next release train."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
PROJECT = ROOT / "iOS/Mathio/Mathio.xcodeproj/project.pbxproj"
SUBMIT = ROOT / "docs/aso/scripts/submit.sh"


def unique_values(pattern: str, text: str) -> set[str]:
    return set(re.findall(pattern, text))


def main() -> int:
    project = PROJECT.read_text(encoding="utf-8")
    submit = SUBMIT.read_text(encoding="utf-8")
    failures: list[str] = []

    marketing_versions = unique_values(r"MARKETING_VERSION = ([^;]+);", project)
    build_numbers = unique_values(r"CURRENT_PROJECT_VERSION = ([^;]+);", project)
    app_marketing_versions = marketing_versions - {"1.0"}
    app_build_numbers = build_numbers - {"1"}

    submit_version_match = re.search(r'TARGET_VERSION="\$\{TARGET_VERSION:-([^}]+)\}"', submit)
    submit_build_match = re.search(r'TARGET_BUILD="\$\{TARGET_BUILD:-([^}]+)\}"', submit)
    submit_version = submit_version_match.group(1) if submit_version_match else ""
    submit_build = submit_build_match.group(1) if submit_build_match else ""

    if len(app_marketing_versions) != 1:
        failures.append(f"app MARKETING_VERSION must be singular, got {sorted(app_marketing_versions)}")
    if len(app_build_numbers) != 1:
        failures.append(f"app CURRENT_PROJECT_VERSION must be singular, got {sorted(app_build_numbers)}")
    if submit_version and app_marketing_versions and submit_version not in app_marketing_versions:
        failures.append(
            f"submit TARGET_VERSION {submit_version} does not match Xcode {sorted(app_marketing_versions)}"
        )
    if submit_build and app_build_numbers and submit_build not in app_build_numbers:
        failures.append(
            f"submit TARGET_BUILD {submit_build} does not match Xcode {sorted(app_build_numbers)}"
        )

    if failures:
        print(f"FAILED: {len(failures)} release config issue(s)")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print(f"OK: release config aligned at {submit_version} build {submit_build}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
