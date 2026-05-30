#!/usr/bin/env bash
# Build a signed App Store .ipa for Mathio and upload it to App Store Connect.
#
# This is the headless equivalent of "Product → Archive → Distribute App" in
# Xcode. Run from anywhere — the script jumps to the project on its own.
#
# Side effect: a fresh .xcarchive lands in /tmp/Mathio.xcarchive and gets
# uploaded to App Store Connect. The first upload of a new bundle ID also
# **creates the App Store Connect app record** automatically — there is no
# separate "create app" action; just upload the build and Apple registers it.
#
# Pre-conditions:
#   - Xcode Command Line Tools installed.
#   - Apple Distribution cert in the keychain (verify with:
#       security find-identity -v -p codesigning | grep "Apple Distribution")
#   - An active App Store Connect Agreements + Banking + Tax setup
#     (otherwise upload succeeds but the app stays in "Prepare for Submission"
#     forever).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$REPO_ROOT/iOS/Mathio"

ARCHIVE_PATH="/tmp/Mathio.xcarchive"
EXPORT_PATH="/tmp/Mathio-export"
PLIST="$REPO_ROOT/docs/aso/scripts/export-options-local.plist"
ASC="${ASC:-/opt/homebrew/bin/asc}"
PROFILE="${PROFILE:-industrietrainer}"
APP_ID="${APP_ID:-6767033115}"

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
hr()   { printf -- '%.0s—' {1..60}; printf '\n'; }

bold "[1/2] Archive Release build"
hr

rm -rf "$ARCHIVE_PATH"
xcodebuild archive \
  -scheme Mathio \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  -configuration Release \
  DEVELOPMENT_TEAM=T3BRJDPUGM \
  | xcbeautify --renderer terminal 2>/dev/null || true

if [[ ! -d "$ARCHIVE_PATH" ]]; then
  echo "Archive failed — check the output above." >&2
  exit 1
fi

bold "[2/2] Export + upload to App Store Connect"
hr

rm -rf "$EXPORT_PATH"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$PLIST" \
  -allowProvisioningUpdates

"$ASC" --profile "$PROFILE" builds upload \
  --app "$APP_ID" \
  --ipa "$EXPORT_PATH/Mathio.ipa" \
  --wait

bold "Done. Build is in App Store Connect. Check processing in the TestFlight tab."
