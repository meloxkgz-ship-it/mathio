#!/usr/bin/env python3
"""Verify Mathio's String Catalog before shipping new languages.

The check is intentionally stricter than Xcode's compiler:

* every declared target locale must have every key
* every localized value must preserve printf-style placeholders
* every localized value must be non-empty

Usage:
  python3 docs/aso/scripts/verify_xcstrings.py
  python3 docs/aso/scripts/verify_xcstrings.py --locales de,fr,es,it,pt-BR
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
CATALOG = ROOT / "iOS/Mathio/Mathio/Localizable.xcstrings"
PLACEHOLDER_RE = re.compile(r"%(?:\d+\$)?(?:[-+#0]*\d*(?:\.\d+)?)?(?:ll|[hlLzjt])?[@dfiuoxXscC%]")


def placeholders(value: str) -> list[str]:
    return [m.group(0) for m in PLACEHOLDER_RE.finditer(value) if m.group(0) != "%%"]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--locales", help="Comma-separated locales to require. Defaults to locales present in the catalog.")
    args = parser.parse_args()

    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    strings: dict[str, dict] = catalog.get("strings", {})
    if args.locales:
        locales = [item.strip() for item in args.locales.split(",") if item.strip()]
    else:
        locales = sorted({lang for entry in strings.values() for lang in entry.get("localizations", {})})

    failures: list[str] = []
    for key, entry in sorted(strings.items()):
        key_placeholders = placeholders(key)
        localizations = entry.get("localizations", {})
        for locale in locales:
            unit = localizations.get(locale, {}).get("stringUnit")
            if not unit:
                failures.append(f"{locale}: missing key {key!r}")
                continue
            value = unit.get("value", "")
            if not value:
                failures.append(f"{locale}: empty value for {key!r}")
                continue
            value_placeholders = placeholders(value)
            if sorted(key_placeholders) != sorted(value_placeholders):
                failures.append(
                    f"{locale}: placeholder mismatch for {key!r}: "
                    f"source={key_placeholders} localized={value_placeholders}"
                )

    if failures:
        print(f"FAILED: {len(failures)} localization issue(s)")
        for failure in failures[:200]:
            print(f"- {failure}")
        if len(failures) > 200:
            print(f"... {len(failures) - 200} more")
        return 1

    print(f"OK: {len(strings)} keys verified for {', '.join(locales)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
