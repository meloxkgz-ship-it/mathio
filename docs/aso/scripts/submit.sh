#!/usr/bin/env bash
# End-to-end App Store Connect metadata + screenshots + submission for Mathio.
#
# Pre-conditions:
#   - `asc auth login` already done with a valid API key (run
#     `asc auth status` to confirm "Mathio" is the active profile).
#   - `archive.sh` already uploaded a build that App Store Connect has
#     finished processing (visible under TestFlight or under the version's
#     Build picker — usually 5–15 min after upload).
#
# What this does, in order:
#   1. Resolve the App Store Connect app ID from the bundle ID.
#   2. Pick the latest 1.0 version (or create one if it doesn't exist yet).
#   3. Push EN + DE app-info localisations (subtitle).
#   4. Push EN + DE version localisations (description, keywords,
#      promotional text, what's new).
#   5. Upload all 12 screenshots to the iPhone 6.9-inch slot.
#   6. (Manual confirm) submit the version for review.
#
# Use --dry-run to print the planned actions without mutating App Store
# Connect.

set -euo pipefail

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then DRY_RUN=1; fi

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$REPO_ROOT"

BUNDLE="com.kgz.Mathio"
TARGET_VERSION="1.0"
PROFILE="Mathio"

bold()  { printf "\033[1m%s\033[0m\n" "$*"; }
say()   { printf "  → %s\n" "$*"; }
do_run(){
  if [[ $DRY_RUN -eq 1 ]]; then
    printf "  \033[2m[dry] %s\033[0m\n" "$*"
  else
    eval "$@"
  fi
}

bold "[0/6] Verify asc auth"
asc auth status --profile "$PROFILE" >/dev/null \
  || { echo "Run: asc auth login --name Mathio …" >&2; exit 1; }
say "profile '$PROFILE' is healthy"
echo

bold "[1/6] Resolve App Store Connect app ID"
APP_JSON=$(asc apps list --profile "$PROFILE" --filter-bundle-id "$BUNDLE" 2>/dev/null || true)
APP_ID=$(echo "$APP_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['data'][0]['id'] if d.get('data') else '')")
if [[ -z "$APP_ID" ]]; then
  echo "App with bundle ID '$BUNDLE' not found in App Store Connect." >&2
  echo "Did you run docs/aso/scripts/archive.sh first?" >&2
  exit 1
fi
say "app ID: $APP_ID"
echo

bold "[2/6] Resolve target version"
VER_JSON=$(asc versions list --profile "$PROFILE" --app "$APP_ID" 2>/dev/null || true)
VERSION_ID=$(echo "$VER_JSON" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for v in d.get('data', []):
    if v['attributes'].get('versionString')=='$TARGET_VERSION':
        print(v['id']); break")
if [[ -z "$VERSION_ID" ]]; then
  say "creating new version $TARGET_VERSION"
  do_run "asc versions create --profile $PROFILE --app $APP_ID --version $TARGET_VERSION --platform IOS"
  VER_JSON=$(asc versions list --profile "$PROFILE" --app "$APP_ID")
  VERSION_ID=$(echo "$VER_JSON" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for v in d.get('data', []):
    if v['attributes'].get('versionString')=='$TARGET_VERSION':
        print(v['id']); break")
fi
say "version ID: $VERSION_ID"
echo

bold "[3/6] App-info localisation (subtitle, EN + DE)"
do_run "asc localizations update --profile $PROFILE --app $APP_ID --type app-info --locale en-US \
  --subtitle 'Algebra, geometry & calculus' --output table"
do_run "asc localizations update --profile $PROFILE --app $APP_ID --type app-info --locale de-DE \
  --subtitle 'Algebra, Analysis & Geometrie' --output table"
echo

bold "[4/6] Version localisation (description, keywords, promo, what's-new)"

do_run "asc localizations update --profile $PROFILE --version $VERSION_ID --locale en-US \
  --description \"\$(cat docs/aso/en-US/description.txt)\" \
  --keywords 'mathe,maths,algebra,calculus,geometry,trigonometry,fractions,equations,formulas,homework,exam,tutor' \
  --promotional-text 'New: tap \"Practice math\" with Siri to jump straight into your daily review queue. Two minutes a day is enough.' \
  --whats-new \"\$(cat docs/aso/en-US/whats-new.txt)\" \
  --support-url 'https://meloxkgz-ship-it.github.io/mathio/' \
  --marketing-url 'https://meloxkgz-ship-it.github.io/mathio/' \
  --output table"

do_run "asc localizations update --profile $PROFILE --version $VERSION_ID --locale de-DE \
  --description \"\$(cat docs/aso/de-DE/description.txt)\" \
  --keywords 'mathe,üben,algebra,analysis,geometrie,trigonometrie,bruchrechnen,gleichung,formeln,abitur,klausur' \
  --promotional-text 'Neu: Sag \"Hey Siri, Mathe üben\" und du landest direkt in deiner heutigen Wiederholungs-Liste. Zwei Minuten am Tag genügen.' \
  --whats-new \"\$(cat docs/aso/de-DE/whats-new.txt)\" \
  --support-url 'https://meloxkgz-ship-it.github.io/mathio/' \
  --marketing-url 'https://meloxkgz-ship-it.github.io/mathio/' \
  --output table"
echo

bold "[5/6] Screenshots — iPhone 6.9-inch (12 PNGs total)"
# Fan-out across locales: docs/screenshots/<locale>/iphone/*.png.
do_run "asc screenshots upload --profile $PROFILE \
  --app $APP_ID --version-id $VERSION_ID \
  --path docs/screenshots --device-type IPHONE_69 \
  --replace --output table"
echo

bold "[6/6] Submit for review"
echo "  Reviewer notes are in SUBMIT.md — paste them into App Store Connect"
echo "  before the next step. (asc submit doesn't write that field.)"
echo
read -p "  Type SUBMIT to enqueue version $TARGET_VERSION for App Review: " confirm
if [[ "$confirm" != "SUBMIT" ]]; then
  echo "  Aborted at the submit gate. Re-run when you're ready."
  exit 0
fi

do_run "asc submit create --profile $PROFILE --app $APP_ID --version-id $VERSION_ID --confirm"

bold "Done."
echo "App Review timer starts when the submission lands. Watch the queue at"
echo "  https://appstoreconnect.apple.com → My Apps → Mathio → App Store"
