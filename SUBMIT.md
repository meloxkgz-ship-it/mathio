# Mathio — final 3 manual steps to live in the App Store

Code is launch-ready. Screenshots are captured (12 PNGs, EN + DE × 6 targets,
1320 × 2868 in `docs/screenshots/`). All 699 string-catalog keys translated.
What's left is **3 steps that need your hands**, because Apple gates each
one behind 2-factor authentication tied to your Apple ID — no CLI tool can
bypass that, including `asc`.

Total time: ~25 minutes. After step 3 the binary is uploaded and you can
hit **Submit for Review** in App Store Connect.

---

## Step 1 — Create the App Store Connect API key (browser, ~2 min)

This unlocks the `asc` CLI for everything else.

1. Open **https://appstoreconnect.apple.com/access/integrations/api** while
   signed in as the account holder.
2. Click **+** → name it `Mathio CLI` → role **App Manager**
   (Admin works too if you have it).
3. Click **Generate**, then **download the .p8 file immediately** —
   Apple shows it exactly once.
4. Note the **Key ID** (10 chars, e.g. `ABCD1234EF`) and the
   **Issuer ID** at the top of the page (UUID-shaped).

Then in your terminal:

```bash
mkdir -p ~/.asc
mv ~/Downloads/AuthKey_*.p8 ~/.asc/AuthKey_Mathio.p8

asc auth login \
  --name Mathio \
  --key-id   <KEY_ID_FROM_STEP_4> \
  --issuer-id <ISSUER_ID> \
  --private-key ~/.asc/AuthKey_Mathio.p8

asc auth switch --name Mathio
asc auth status         # should print "Mathio" as default
asc apps list           # should show your existing apps
```

If `asc apps list` succeeds, you can close this section and move to step 2.

> **Tip:** the existing keychain entry `industrietrainer` is unrelated and
> still works for that other project — `asc auth switch` toggles between
> them.

---

## Step 2 — Archive + upload the binary (Xcode GUI, ~10 min)

The archive needs your Distribution code-signing identity, which is on
your Mac (cert `iPhone Distribution: Filippos Kagkiouzls (T3BRJDPUGM)`).
The CLI path works too — both options below.

### Option A — Xcode GUI (recommended for v1.0)

1. Open the project: `open iOS/Mathio/Mathio.xcodeproj`
2. Top bar: change destination to **Any iOS Device (arm64)**.
3. Menu **Product → Archive**.
4. When the **Organizer** opens with the new archive selected, click
   **Distribute App** → **App Store Connect** → **Upload**.
5. Accept the defaults (manage versioning, automatic signing).
6. Wait for "Upload Successful". The build appears in **TestFlight** on
   App Store Connect within ~10 min after Apple processes it.

### Option B — CLI

```bash
cd iOS/Mathio

# 1) Archive (~5 min)
xcodebuild archive \
  -scheme Mathio \
  -destination "generic/platform=iOS" \
  -archivePath /tmp/Mathio.xcarchive \
  -configuration Release \
  DEVELOPMENT_TEAM=T3BRJDPUGM

# 2) Export for App Store
cat > /tmp/export-options.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>T3BRJDPUGM</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath /tmp/Mathio.xcarchive \
  -exportPath /tmp/Mathio-export \
  -exportOptionsPlist /tmp/export-options.plist \
  -allowProvisioningUpdates
```

The `destination=upload` line tells xcodebuild to push directly to
App Store Connect after exporting — no Transporter step needed.

---

## Step 3 — Push metadata + screenshots via `asc` (~10 min)

Once step 1 (API key) + step 2 (binary uploaded) are both done, this is
fully scripted. From the repo root:

```bash
# Find the App Store Connect app ID for Mathio (created automatically
# the first time you upload a binary with a new Bundle ID).
asc apps list --filter-bundle-id com.kgz.Mathio
# Note the appId — call it APP_ID.

APP_ID=<paste here>
VERSION=1.0
LOCALES=(en-US de-DE)

# Listing copy — copy-paste from docs/aso/<locale>/metadata.md
for L in "${LOCALES[@]}"; do
  cat docs/aso/$L/metadata.md   # pull the values manually for now
done

# Set listing fields per locale (after pasting values into env vars):
asc localizations update --app "$APP_ID" --locale en-US \
  --subtitle "Algebra, geometry & calculus" \
  --keywords "mathe,maths,algebra,calculus,geometry,trigonometry,fractions,equations,formulas,homework,exam,tutor" \
  --promotional-text "New: tap \"Practice math\" with Siri to jump straight into your daily review queue. Two minutes a day is enough." \
  --description "$(cat docs/aso/en-US/description.txt 2>/dev/null || echo 'paste from docs/aso/en-US/metadata.md')"

asc localizations update --app "$APP_ID" --locale de-DE \
  --subtitle "Algebra, Analysis & Geometrie" \
  --keywords "mathe,üben,algebra,analysis,geometrie,trigonometrie,bruchrechnen,gleichung,formeln,abitur,klausur" \
  --promotional-text "Neu: Sag \"Hey Siri, Mathe üben\" und du landest direkt in deiner heutigen Wiederholungs-Liste. Zwei Minuten am Tag genügen." \
  --description "$(cat docs/aso/de-DE/description.txt 2>/dev/null || echo 'paste from docs/aso/de-DE/metadata.md')"

# Screenshots — push all six per locale, in order, to the 6.9-inch slot.
for L in "${LOCALES[@]}"; do
  for img in docs/screenshots/$L/*.png; do
    asc screenshots upload --app "$APP_ID" --locale "$L" \
      --display-type "iPhone 6.9" --file "$img"
  done
done

# Submit (only after manual review of every field above):
asc submit create --app "$APP_ID" --version "$VERSION" --confirm
```

> **Reviewer notes**: copy this block verbatim into the **Notes for Reviewer**
> field in App Store Connect (Version → App Review Information):
>
> > Mathio has no user accounts. To test premium features without a
> > purchase:
> > 1. Open the app → finish onboarding → tap the gear icon (Settings)
> > 2. Tap the version line at the bottom of the Settings list 7 times.
> > 3. A confirmation banner shows "Premium unlocked for review" and the
> >    Subscription section now displays the active state. Premium remains
> >    unlocked across relaunches until you tap 7 more times to clear it.
> >
> > Alternatively the StoreKit configuration in the binary points at
> > Apple's sandbox environment — any sandbox tester account works for the
> > real IAP flow against `mathio_annual` / `mathio_weekly`.

---

## What you do **not** need to do

| | Why |
|---|---|
| ~~Translate UI strings~~ | All 699 keys covered in `Localizable.xcstrings` (run `python3 docs/aso/scripts/sync_xcstrings.py` from `iOS/Mathio/Mathio/` if you ever add new strings). |
| ~~Capture screenshots~~ | All 12 PNGs are in `docs/screenshots/{en-US,de-DE}/`. Re-capture only if the UI changes — script: `docs/aso/scripts/screenshots.sh`. |
| ~~Write listing copy~~ | Done — see `docs/aso/{en-US,de-DE}/metadata.md`. |
| ~~Decide keyword strategy~~ | Done — see `docs/aso/keyword-research.md`. |
| ~~Build a reviewer demo path~~ | Implemented — 7-tap on Settings version label persists premium override. |
| ~~Worry about Privacy / Terms URLs~~ | Already live at `https://meloxkgz-ship-it.github.io/mathio/{privacy,terms}`. |

---

## If something blocks

- **"asc apps list" returns empty:** Apple only creates the app record
  after the first binary upload. Do step 2 first; then come back to step 3.
- **Code-signing error in step 2:** Open Xcode → Settings → Accounts →
  click your Apple ID → **Manage Certificates** → confirm the
  "Apple Distribution" cert is there. If absent, click **+ → Apple
  Distribution** to regenerate, then retry.
- **App Review rejection on metadata:** the most common cause is missing
  IAP localisation. In App Store Connect → In-App Purchases, every product
  needs both an EN and a DE display name + description — those texts live
  outside the Xcode project; copy from `docs/aso/de-DE/metadata.md`
  bottom table.
