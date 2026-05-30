#!/usr/bin/env python3
"""Verify plain-text App Store metadata before pushing it with asc."""

from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LIMITS = {
    "description.txt": 4000,
    "whats-new.txt": 4000,
}
LOCALES = {"en-US", "de-DE"}


def main() -> int:
    failures: list[str] = []
    checked = 0

    for locale_dir in sorted(path for path in ROOT.iterdir() if path.is_dir() and path.name in LOCALES):
        for filename, limit in LIMITS.items():
            path = locale_dir / filename
            if not path.exists():
                failures.append(f"{locale_dir.name}: missing {filename}")
                continue
            value = path.read_text(encoding="utf-8")
            checked += 1
            if value.endswith(" ") or value.endswith("\t"):
                failures.append(f"{locale_dir.name}/{filename}: trailing whitespace at EOF")
            count = len(value.rstrip("\n"))
            if count > limit:
                failures.append(f"{locale_dir.name}/{filename}: {count} chars exceeds {limit}")
            if "\r" in value:
                failures.append(f"{locale_dir.name}/{filename}: contains CR line endings")

    if failures:
        print(f"FAILED: {len(failures)} metadata issue(s)")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print(f"OK: {checked} metadata files within App Store limits")
    return 0


if __name__ == "__main__":
    sys.exit(main())
