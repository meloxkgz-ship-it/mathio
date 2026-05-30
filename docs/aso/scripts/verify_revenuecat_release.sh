#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE="${1:-}"
ENV_KEY="${REVENUECAT_API_KEY:-}"
BUILT_KEY=""
CHECK_ASC_LOCALIZATIONS="${CHECK_ASC_LOCALIZATIONS:-0}"
CHECK_LOCAL_STOREKIT="${CHECK_LOCAL_STOREKIT:-1}"
APP_ID="${ASC_APP_ID:-6767033115}"
SUBSCRIPTION_GROUP_ID="${MATHIO_SUBSCRIPTION_GROUP_ID:-22071889}"
SUBSCRIPTION_IDS="${MATHIO_SUBSCRIPTION_IDS:-6767033716 6767033995 6767033879}"
REQUIRED_SUBSCRIPTION_LOCALES="${MATHIO_REQUIRED_SUBSCRIPTION_LOCALES:-en-US de-DE es-ES fr-FR it pt-BR}"

if [[ "$APP_BUNDLE" == "--asc-localizations" ]]; then
  CHECK_ASC_LOCALIZATIONS=1
  APP_BUNDLE=""
fi

if [[ -n "$APP_BUNDLE" ]]; then
  INFO_PLIST="$APP_BUNDLE/Info.plist"
  if [[ ! -f "$INFO_PLIST" ]]; then
    echo "Info.plist not found at $INFO_PLIST" >&2
    exit 1
  fi

  BUILT_KEY="$(/usr/libexec/PlistBuddy -c 'Print :RevenueCatAPIKey' "$INFO_PLIST" 2>/dev/null || true)"
fi

KEY="${ENV_KEY:-$BUILT_KEY}"

if [[ -z "$KEY" ]]; then
  if [[ "$CHECK_ASC_LOCALIZATIONS" == "1" && -z "$APP_BUNDLE" && -z "$ENV_KEY" ]]; then
    echo "RevenueCat release key check skipped; no app bundle or REVENUECAT_API_KEY was provided."
  else
  echo "RevenueCatAPIKey is missing. Set REVENUECAT_API_KEY or pass a built .app bundle." >&2
  exit 1
  fi
fi

if [[ -n "$KEY" && "$KEY" != appl_* ]]; then
  echo "RevenueCatAPIKey must be an iOS public SDK key starting with appl_." >&2
  exit 1
fi

if [[ -n "$KEY" ]]; then
  if [[ "$KEY" == *'$('* || "$KEY" == *REPLACE* || "$KEY" == *your_public_key_here* ]]; then
    echo "RevenueCatAPIKey still looks like a placeholder." >&2
    exit 1
  fi
fi

if [[ -n "$APP_BUNDLE" && -n "$ENV_KEY" ]]; then
  if [[ "$BUILT_KEY" != "$ENV_KEY" ]]; then
    echo "Built app RevenueCatAPIKey does not match REVENUECAT_API_KEY." >&2
    exit 1
  fi
fi

if [[ -n "$KEY" ]]; then
  echo "RevenueCat release key check passed."
fi

if [[ "$CHECK_LOCAL_STOREKIT" == "1" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  python3 "$SCRIPT_DIR/verify_storekit_localizations.py"
fi

if [[ "$CHECK_ASC_LOCALIZATIONS" != "1" ]]; then
  exit 0
fi

if ! command -v asc >/dev/null 2>&1; then
  echo "asc CLI is required for subscription localization checks." >&2
  exit 1
fi

python3 - "$APP_ID" "$SUBSCRIPTION_GROUP_ID" "$SUBSCRIPTION_IDS" "$REQUIRED_SUBSCRIPTION_LOCALES" <<'PY'
from __future__ import annotations

import json
import subprocess
import sys

_app_id, group_id, subscription_ids_raw, required_raw = sys.argv[1:5]
subscription_ids = subscription_ids_raw.split()
required = set(required_raw.split())


def asc_json(*args: str) -> dict:
    output = subprocess.check_output(["asc", *args, "--output", "json", "--paginate"], text=True)
    return json.loads(output)


def locales(payload: dict) -> set[str]:
    return {
        item.get("attributes", {}).get("locale", "")
        for item in payload.get("data", [])
        if item.get("attributes", {}).get("locale")
    }


failures: list[str] = []
group_locales = locales(
    asc_json("subscriptions", "groups", "localizations", "list", "--group-id", group_id)
)
missing_group = required - group_locales
if missing_group:
    failures.append(f"group {group_id} missing locales: {', '.join(sorted(missing_group))}")

for subscription_id in subscription_ids:
    subscription_locales = locales(
        asc_json("subscriptions", "localizations", "list", "--subscription-id", subscription_id)
    )
    missing_subscription = required - subscription_locales
    if missing_subscription:
        failures.append(
            f"subscription {subscription_id} missing locales: {', '.join(sorted(missing_subscription))}"
        )

if failures:
    print("RevenueCat/App Store subscription localization check failed.", file=sys.stderr)
    for failure in failures:
        print(f"- {failure}", file=sys.stderr)
    sys.exit(1)

print(
    "RevenueCat/App Store subscription localization check passed "
    f"for {len(subscription_ids)} subscriptions and {len(required)} locales."
)
PY
