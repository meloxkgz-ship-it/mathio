#!/usr/bin/env python3
"""Verify local StoreKit subscription metadata has all supported locales."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
STOREKIT = ROOT / "iOS/Mathio/Mathio/Mathio.storekit"
DEFAULT_LOCALES = ("en_US", "de_DE", "es_ES", "fr_FR", "it_IT", "pt_BR")
DESCRIPTION_LIMIT = 55


def localization_map(items: list[dict]) -> dict[str, dict]:
    return {item.get("locale", ""): item for item in items if item.get("locale")}


def verify_block(label: str, items: list[dict], required: set[str]) -> list[str]:
    failures: list[str] = []
    by_locale = localization_map(items)
    missing = required - set(by_locale)
    if missing:
        failures.append(f"{label} missing locales: {', '.join(sorted(missing))}")

    for locale in sorted(required & set(by_locale)):
        item = by_locale[locale]
        display_name = item.get("displayName", "")
        description = item.get("description", "")
        if not display_name:
            failures.append(f"{label} {locale} has an empty displayName")
        if not description:
            failures.append(f"{label} {locale} has an empty description")
        if len(description) > DESCRIPTION_LIMIT:
            failures.append(
                f"{label} {locale} description is {len(description)} chars; "
                f"max is {DESCRIPTION_LIMIT}"
            )
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--locales",
        default=",".join(DEFAULT_LOCALES),
        help="Comma-separated StoreKit locales to require.",
    )
    args = parser.parse_args()
    required = {item.strip() for item in args.locales.split(",") if item.strip()}

    storekit = json.loads(STOREKIT.read_text(encoding="utf-8"))
    failures: list[str] = []

    for group in storekit.get("subscriptionGroups", []):
        group_id = group.get("id", "<unknown>")
        failures.extend(
            verify_block(f"group {group_id}", group.get("localizations", []), required)
        )
        for subscription in group.get("subscriptions", []):
            product_id = subscription.get("productID", "<unknown>")
            failures.extend(
                verify_block(
                    f"subscription {product_id}",
                    subscription.get("localizations", []),
                    required,
                )
            )

    if failures:
        print(f"FAILED: {len(failures)} StoreKit localization issue(s)")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print(f"OK: StoreKit subscription metadata verified for {', '.join(sorted(required))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
