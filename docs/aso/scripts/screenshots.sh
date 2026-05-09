#!/usr/bin/env bash
# Capture localized App Store screenshots from the iOS Simulator.
#
# Uses the DEBUG-only `MATHIO_PREVIEW=…` env-var routing in MathioApp.swift
# to teleport directly to a target screen, then grabs a PNG via simctl.
#
# Usage:
#   docs/aso/scripts/screenshots.sh <SIM_UDID> <LOCALE> <OUTPUT_DIR>
#
# Example:
#   docs/aso/scripts/screenshots.sh \
#     "147737C4-A9F7-4E84-A221-29C3A39E792F" \
#     "en-US" \
#     "$(pwd)/docs/screenshots/en-US"
#
# Pre-flight:
#   1. Boot the sim:    xcrun simctl boot "iPhone 17 Pro Max"
#   2. Build Debug:     cd iOS/Mathio && xcodebuild -scheme Mathio \
#                         -destination "platform=iOS Simulator,id=$SIM_UDID" \
#                         -configuration Debug -derivedDataPath /tmp/Mathio-screenshots \
#                         build CODE_SIGNING_ALLOWED=NO
#   3. Install:         xcrun simctl install $SIM_UDID \
#                         /tmp/Mathio-screenshots/Build/Products/Debug-iphonesimulator/Mathio.app
#   4. Clean status:    xcrun simctl status_bar $SIM_UDID override --time 9:41 \
#                         --batteryState charged --batteryLevel 100 \
#                         --cellularBars 4 --wifiBars 3
#
# Run this script after pre-flight. Output is six PNGs named 01-home.png …
# 06-formulas.png, sized to whatever the booted device produces (1290×2796
# on iPhone 17 Pro Max — App Store's 6.9-inch slot).

set -euo pipefail

SIM="${1:-}"
LOCALE="${2:-}"
OUT="${3:-}"
BUNDLE="com.kgz.Mathio"

if [[ -z "$SIM" || -z "$LOCALE" || -z "$OUT" ]]; then
  echo "usage: $0 <SIM_UDID> <LOCALE> <OUTPUT_DIR>" >&2
  echo "  LOCALE: en-US | de-DE" >&2
  exit 64
fi

# Map App Store locale → app language code + Apple-locale identifier.
case "$LOCALE" in
  en-US) APP_LANG="en" ; APP_LOCALE="en_US" ;;
  de-DE) APP_LANG="de" ; APP_LOCALE="de_DE" ;;
  *) echo "unsupported LOCALE: $LOCALE" >&2 ; exit 64 ;;
esac

mkdir -p "$OUT"
rm -f "$OUT"/*.png

idx=1
for target in home lesson practice paywall stats formulas; do
  printf "→ [%s] %s\n" "$LOCALE" "$target"
  xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
  sleep 0.6
  # NSUserDefaults launch-arg overrides (-AppleLanguages, -AppleLocale)
  # force the bundle's localised strings without changing simulator state.
  SIMCTL_CHILD_MATHIO_PREVIEW="$target" \
    xcrun simctl launch "$SIM" "$BUNDLE" \
    -AppleLanguages "($APP_LANG)" \
    -AppleLocale "$APP_LOCALE" >/dev/null 2>&1
  sleep 2.5
  fname=$(printf "0%d-%s.png" "$idx" "$target")
  xcrun simctl io "$SIM" screenshot --type=png "$OUT/$fname"
  idx=$((idx + 1))
done

printf "\n---sizes (%s)---\n" "$LOCALE"
for f in "$OUT"/*.png; do
  size=$(stat -f %z "$f")
  dims=$(sips -g pixelWidth -g pixelHeight "$f" 2>/dev/null | awk '/pixel/{printf "%s ", $2}')
  printf "%s: %sB  %s\n" "$(basename "$f")" "$size" "$dims"
done
