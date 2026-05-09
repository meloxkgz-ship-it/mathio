#!/usr/bin/env bash
# End-to-end App Store Connect metadata + screenshots + submission for Mathio.
#
# Pre-conditions:
#   - `asc auth login` already done (run `asc auth status` to confirm).
#     The active profile must have App Manager (or Admin / Account Holder)
#     access to team T3BRJDPUGM (the team that owns com.kgz.Mathio).
#   - `archive.sh` already uploaded a build that App Store Connect has
#     finished processing — check the TestFlight tab of the app.
#
# Profile selection:
#   By default uses the asc profile named "Mathio". Override with the
#   PROFILE env var, e.g.
#       PROFILE=industrietrainer docs/aso/scripts/submit.sh --dry-run
#
# Modes:
#   --dry-run    print the planned actions, mutate nothing
#   (default)    execute, ask 'SUBMIT' before review submission
#   --no-submit  push metadata + screenshots, stop before submitting

set -euo pipefail

DRY_RUN=0
DO_SUBMIT=1
for arg in "$@"; do
  case "$arg" in
    --dry-run)   DRY_RUN=1 ;;
    --no-submit) DO_SUBMIT=0 ;;
    *) echo "unknown flag: $arg" >&2 ; exit 64 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$REPO_ROOT"

BUNDLE="com.kgz.Mathio"
TARGET_VERSION="1.0"
PROFILE="${PROFILE:-Mathio}"
ASC=/opt/homebrew/bin/asc

bold()  { printf "\033[1m%s\033[0m\n" "$*"; }
say()   { printf "  → %s\n" "$*"; }
do_run(){
  if [[ $DRY_RUN -eq 1 ]]; then
    printf "  \033[2m[dry] %s\033[0m\n" "$*"
  else
    eval "$@"
  fi
}

bold "[0/6] Verify asc auth (profile: $PROFILE)"
$ASC --profile "$PROFILE" auth status >/dev/null 2>&1 \
  || { echo "Profile '$PROFILE' missing or invalid. Run: asc auth login --name $PROFILE …" >&2; exit 1; }
say "profile '$PROFILE' is healthy"
echo

bold "[1/6] Resolve App Store Connect app ID"
APP_JSON=$($ASC --profile "$PROFILE" apps list --bundle-id "$BUNDLE" --output json 2>/dev/null || true)
APP_ID=$(echo "$APP_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['data'][0]['id'] if d.get('data') else '')")
if [[ -z "$APP_ID" ]]; then
  echo "App with bundle ID '$BUNDLE' not found in App Store Connect." >&2
  echo "Did you run docs/aso/scripts/archive.sh first?" >&2
  exit 1
fi
say "app ID: $APP_ID"
echo

bold "[2/6] Resolve target version $TARGET_VERSION"
VER_JSON=$($ASC --profile "$PROFILE" versions list --app "$APP_ID" --output json 2>/dev/null || true)
VERSION_ID=$(echo "$VER_JSON" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for v in d.get('data', []):
    if v['attributes'].get('versionString')=='$TARGET_VERSION':
        print(v['id']); break")
if [[ -z "$VERSION_ID" ]]; then
  say "creating new version $TARGET_VERSION"
  do_run "$ASC --profile $PROFILE versions create --app $APP_ID --version $TARGET_VERSION --platform IOS"
  VER_JSON=$($ASC --profile "$PROFILE" versions list --app "$APP_ID" --output json)
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
do_run "$ASC --profile $PROFILE localizations update \
  --app $APP_ID --type app-info --locale en-US \
  --subtitle 'Algebra, geometry & calculus' --output table"
do_run "$ASC --profile $PROFILE localizations update \
  --app $APP_ID --type app-info --locale de-DE \
  --subtitle 'Algebra, Analysis & Geometrie' --output table"
echo

bold "[4/6] Version localisation (description, keywords, promo, what's-new)"

# Read the listing copy from plain-text so it round-trips through the CLI
# without markdown contamination.
EN_DESC=$(cat docs/aso/en-US/description.txt)
DE_DESC=$(cat docs/aso/de-DE/description.txt)
EN_NEW=$(cat  docs/aso/en-US/whats-new.txt)
DE_NEW=$(cat  docs/aso/de-DE/whats-new.txt)

# Each `eval` invocation rebuilds the command string with the heredoc
# expanded — that's why we use `do_run "$ASC … '$EN_DESC'"` instead of
# leaving the cat-substitution inline.

if [[ $DRY_RUN -eq 1 ]]; then
  printf "  \033[2m[dry] localizations update --version %s --locale en-US (description %s chars, what's-new %s chars)\033[0m\n" \
    "$VERSION_ID" "${#EN_DESC}" "${#EN_NEW}"
  printf "  \033[2m[dry] localizations update --version %s --locale de-DE (description %s chars, what's-new %s chars)\033[0m\n" \
    "$VERSION_ID" "${#DE_DESC}" "${#DE_NEW}"
else
  $ASC --profile "$PROFILE" localizations update \
    --version "$VERSION_ID" --locale en-US \
    --description "$EN_DESC" \
    --keywords 'mathe,maths,algebra,calculus,geometry,trigonometry,fractions,equations,formulas,homework,exam,tutor' \
    --promotional-text 'New: tap "Practice math" with Siri to jump straight into your daily review queue. Two minutes a day is enough.' \
    --whats-new "$EN_NEW" \
    --support-url   'https://meloxkgz-ship-it.github.io/mathio/' \
    --marketing-url 'https://meloxkgz-ship-it.github.io/mathio/' \
    --output table

  $ASC --profile "$PROFILE" localizations update \
    --version "$VERSION_ID" --locale de-DE \
    --description "$DE_DESC" \
    --keywords 'mathe,üben,algebra,analysis,geometrie,trigonometrie,bruchrechnen,gleichung,formeln,abitur,klausur' \
    --promotional-text 'Neu: Sag "Hey Siri, Mathe üben" und du landest direkt in deiner heutigen Wiederholungs-Liste. Zwei Minuten am Tag genügen.' \
    --whats-new "$DE_NEW" \
    --support-url   'https://meloxkgz-ship-it.github.io/mathio/' \
    --marketing-url 'https://meloxkgz-ship-it.github.io/mathio/' \
    --output table
fi
echo

bold "[5/6] Screenshots — iPhone 6.9-inch (12 PNGs total)"
# Fan-out across locales: docs/screenshots/<locale>/iphone/*.png.
do_run "$ASC --profile $PROFILE screenshots upload \
  --app $APP_ID --version-id $VERSION_ID \
  --path docs/screenshots --device-type IPHONE_69 \
  --replace --output table"
echo

if [[ $DO_SUBMIT -eq 0 ]]; then
  bold "Stopped before review submission (--no-submit)."
  echo "Run \`asc review submit --app $APP_ID --version-id $VERSION_ID --confirm\` when ready."
  exit 0
fi

bold "[6/6] Submit for review"
echo "  Reviewer notes are in SUBMIT.md — paste them into App Store Connect"
echo "  → Version → App Review Information **before** confirming below."
echo "  (asc review submit doesn't write that field.)"
echo

# Find the latest processed build.
BUILD_JSON=$($ASC --profile "$PROFILE" builds list --app "$APP_ID" --output json 2>/dev/null || true)
BUILD_ID=$(echo "$BUILD_JSON" | python3 -c "
import json,sys
d=json.load(sys.stdin)
# Filter to processed builds, take the newest version-string match.
def proc(b): return b['attributes'].get('processingState')=='VALID'
for b in sorted(d.get('data', []), key=lambda x: x['attributes'].get('uploadedDate',''), reverse=True):
    if proc(b) and b['attributes'].get('version')=='1':
        print(b['id']); break")
if [[ -z "$BUILD_ID" ]]; then
  echo "  No processed build found yet. Wait 5-15 min after archive.sh." >&2
  echo "  Re-run with --no-submit first if you want to push metadata now and submit later." >&2
  exit 1
fi
say "build ID to attach: $BUILD_ID"

read -p "  Type SUBMIT to enqueue version $TARGET_VERSION for App Review: " confirm
if [[ "$confirm" != "SUBMIT" ]]; then
  echo "  Aborted at the submit gate. Re-run when you're ready."
  exit 0
fi

do_run "$ASC --profile $PROFILE review submit \
  --app $APP_ID --version-id $VERSION_ID --build $BUILD_ID --confirm"

bold "Done."
echo "App Review timer starts when the submission lands. Watch it at"
echo "  https://appstoreconnect.apple.com → My Apps → Mathio → App Store"
