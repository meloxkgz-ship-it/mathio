#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE="${1:-}"
ENV_KEY="${REVENUECAT_API_KEY:-}"
BUILT_KEY=""

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
  echo "RevenueCatAPIKey is missing. Set REVENUECAT_API_KEY or pass a built .app bundle." >&2
  exit 1
fi

if [[ "$KEY" != appl_* ]]; then
  echo "RevenueCatAPIKey must be an iOS public SDK key starting with appl_." >&2
  exit 1
fi

if [[ "$KEY" == *'$('* || "$KEY" == *REPLACE* || "$KEY" == *your_public_key_here* ]]; then
  echo "RevenueCatAPIKey still looks like a placeholder." >&2
  exit 1
fi

if [[ -n "$APP_BUNDLE" && -n "$ENV_KEY" ]]; then
  if [[ "$BUILT_KEY" != "$ENV_KEY" ]]; then
    echo "Built app RevenueCatAPIKey does not match REVENUECAT_API_KEY." >&2
    exit 1
  fi
fi

echo "RevenueCat release key check passed."
