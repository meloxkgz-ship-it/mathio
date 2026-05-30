#!/usr/bin/env python3
"""Verify Mathio's String Catalog before shipping new languages.

The check is intentionally stricter than Xcode's compiler:

* every declared target locale must have every key
* every localized value must preserve printf-style placeholders
* every localized value must be non-empty
* old premium-roadmap count claims must not linger in the catalog
* learning-review copy must not be translated as App Store ratings/reviews

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
STALE_MARKETING_RE = re.compile(
    r"\b(?:[1-8]\d|9[0-7])\s+lessons\s+across\b|"
    r"\bAll\s+(?:[1-8]\d|9[0-7])\s+lessons\s+and\s+(?:[1-4]\d{2})\s+guided questions\b|"
    r"\b(?:[1-8]\d|9[0-7])\s+Lektionen\s+in\b|"
    r"\bAlle\s+(?:[1-8]\d|9[0-7])\s+Lektionen\s+und\s+(?:[1-4]\d{2})\s+gef[üu]hrte[n]?\s+(?:Fragen|Aufgaben)\b",
    re.IGNORECASE,
)
LEARNING_REVIEW_TERMS = ("review", "reviews")
APP_REVIEW_KEY_EXCEPTIONS = (
    "app review",
    "quick rating",
    "rate mathio",
    "reviewer",
    "send feedback",
    "enjoying mathio",
    "unlocked for review",
)
APP_REVIEW_TRANSLATION_RE: dict[str, re.Pattern[str]] = {
    "de": re.compile(r"\bReviews?\b|\bBewertungen?\b|\bbewerten\b", re.IGNORECASE),
    "es": re.compile(r"\breseñas?\b|\bvaloraciones?\b|\bvalorar\b", re.IGNORECASE),
    "fr": re.compile(r"\bavis\b|\bcritiques?\b|\bnotes?\b|\bnoter\b", re.IGNORECASE),
    "it": re.compile(r"\brecension[ei]\b|\bvalutazion[ei]\b|\bvalutare\b", re.IGNORECASE),
    "pt-BR": re.compile(r"\bcoment[aá]rios?\b|\bavalia[cç][aã]o\b|\bavalia[cç][õo]es\b|\bavaliar\b", re.IGNORECASE),
}
UNTRANSLATED_VALUE_BLOCKLIST = {
    "No relationship",
}
GERMAN_UI_MIX_RE = re.compile(
    r"\b(?:Session|Sessions|Roadmap|Drill|Freezes)\b|Wiederholungsqueue",
    re.IGNORECASE,
)
GERMAN_UI_MIX_EXCEPTIONS = (
    "App Store",
    "RevenueCat",
)


def placeholders(value: str) -> list[str]:
    return [m.group(0) for m in PLACEHOLDER_RE.finditer(value) if m.group(0) != "%%"]


def is_learning_review_key(key: str) -> bool:
    lowered = key.lower()
    return (
        any(term in lowered for term in LEARNING_REVIEW_TERMS)
        and not any(exception in lowered for exception in APP_REVIEW_KEY_EXCEPTIONS)
    )


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
        if STALE_MARKETING_RE.search(key):
            failures.append(f"stale marketing count in source key {key!r}")
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
            if locale != "en" and value == key and value in UNTRANSLATED_VALUE_BLOCKLIST:
                failures.append(f"{locale}: untranslated value for {key!r}")
            if STALE_MARKETING_RE.search(value):
                failures.append(f"{locale}: stale marketing count for {key!r}: {value!r}")
            if (
                locale == "de"
                and GERMAN_UI_MIX_RE.search(value)
                and not any(exception in value for exception in GERMAN_UI_MIX_EXCEPTIONS)
            ):
                failures.append(f"{locale}: English UI term in German translation for {key!r}: {value!r}")
            if is_learning_review_key(key):
                app_review_re = APP_REVIEW_TRANSLATION_RE.get(locale)
                if app_review_re and app_review_re.search(value):
                    failures.append(f"{locale}: learning review mistranslated as App Store review for {key!r}: {value!r}")
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
