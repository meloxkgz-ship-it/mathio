#!/usr/bin/env python3
"""Add machine-assisted localizations to Mathio's String Catalog.

This script is deliberately conservative:

* printf placeholders are protected before translation and restored after it
* math-only strings are copied instead of translated
* existing human translations are never overwritten unless --force is passed

Install dependency in a throwaway venv if needed:
  python3 -m venv /tmp/mathio-l10n-venv
  /tmp/mathio-l10n-venv/bin/pip install deep-translator
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

try:
    from deep_translator import GoogleTranslator
except ImportError as exc:  # pragma: no cover - setup guard
    raise SystemExit("Missing dependency: install deep-translator in the active Python environment.") from exc


ROOT = Path(__file__).resolve().parents[3]
CATALOG = ROOT / "iOS/Mathio/Mathio/Localizable.xcstrings"
PLACEHOLDER_RE = re.compile(r"%(?:\d+\$)?(?:[-+#0]*\d*(?:\.\d+)?)?(?:ll|[hlLzjt])?[@dfiuoxXscC%]")
WORD_RE = re.compile(r"[A-Za-z]{2,}")
TARGETS = {
    "es": "spanish",
    "fr": "french",
    "it": "italian",
    "pt-BR": "portuguese",
}


def placeholders(value: str) -> list[str]:
    return [m.group(0) for m in PLACEHOLDER_RE.finditer(value) if m.group(0) != "%%"]


def math_only(value: str) -> bool:
    words = WORD_RE.findall(value)
    if not words:
        return True
    # Single symbolic words are usually variables/functions inside formulas.
    return all(word in {"sin", "cos", "tan", "lim", "dx", "dy", "sqrt", "log", "ln", "abs"} for word in words)


def protect_placeholders(value: str) -> tuple[str, list[str]]:
    protected: list[str] = []

    def replace(match: re.Match[str]) -> str:
        protected.append(match.group(0))
        return f"__MATHIO_PH_{len(protected) - 1}__"

    return PLACEHOLDER_RE.sub(replace, value), protected


def restore_placeholders(value: str, protected: list[str]) -> str:
    for index, placeholder in enumerate(protected):
        token = f"__MATHIO_PH_{index}__"
        value = value.replace(token, placeholder)
        value = value.replace(token.lower(), placeholder)
    return value


def restore_value(source: str, translated: str, protected: list[str]) -> str:
    restored = restore_placeholders(translated, protected)
    if sorted(placeholders(source)) != sorted(placeholders(restored)):
        raise ValueError(f"placeholder mismatch: {source!r} -> {restored!r}")
    return restored


def translate_value(translator: GoogleTranslator, value: str) -> str:
    if math_only(value):
        return value
    protected, original_placeholders = protect_placeholders(value)
    translated = translator.translate(protected)
    return restore_value(value, translated, original_placeholders)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--locales", default="es,fr,it,pt-BR", help="Comma-separated target locales.")
    parser.add_argument("--force", action="store_true", help="Overwrite existing localizations.")
    parser.add_argument("--sleep", type=float, default=0.04, help="Delay between translation calls.")
    parser.add_argument("--batch-size", type=int, default=40, help="Batch size for translation requests.")
    args = parser.parse_args()

    requested = [item.strip() for item in args.locales.split(",") if item.strip()]
    unknown = [locale for locale in requested if locale not in TARGETS]
    if unknown:
        raise SystemExit(f"Unsupported locale(s): {', '.join(unknown)}")

    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    strings: dict[str, dict] = catalog["strings"]
    failures: list[str] = []

    for locale in requested:
        translator = GoogleTranslator(source="en", target=TARGETS[locale])
        added = 0
        reused = 0
        pending: list[tuple[str, dict, str, list[str]]] = []
        for key, entry in sorted(strings.items()):
            localizations = entry.setdefault("localizations", {})
            if not args.force and localizations.get(locale, {}).get("stringUnit", {}).get("value"):
                reused += 1
                continue
            if math_only(key):
                value = key
                localizations[locale] = {"stringUnit": {"state": "translated", "value": value}}
                added += 1
                continue
            protected, original_placeholders = protect_placeholders(key)
            pending.append((key, entry, protected, original_placeholders))

        for offset in range(0, len(pending), args.batch_size):
            batch = pending[offset : offset + args.batch_size]
            protected_values = [item[2] for item in batch]
            try:
                translated_values = translator.translate_batch(protected_values)
            except Exception:
                translated_values = []
                for source, _entry, protected, _original_placeholders in batch:
                    try:
                        translated_values.append(translator.translate(protected))
                    except Exception as exc:
                        failures.append(f"{locale}: {source!r}: {exc}")
                        translated_values.append(source)
            for (source, entry, _protected, original_placeholders), translated in zip(batch, translated_values):
                localizations = entry.setdefault("localizations", {})
                try:
                    value = restore_value(source, translated, original_placeholders)
                except Exception as exc:
                    failures.append(f"{locale}: {source!r}: {exc}")
                    value = source
                localizations[locale] = {"stringUnit": {"state": "translated", "value": value}}
                added += 1
            print(f"{locale}: {min(offset + len(batch), len(pending))}/{len(pending)} prose strings translated", flush=True)
            if args.sleep:
                time.sleep(args.sleep)
        print(f"{locale}: added {added}, reused {reused}", flush=True)

    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if failures:
        print(f"WARN: {len(failures)} fallback translation(s)")
        for failure in failures[:80]:
            print(f"- {failure}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
