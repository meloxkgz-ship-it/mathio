# Mathio v1.0 — App Store submission status

> Live state in App Store Connect, generated 2026-05-10. App ID `6767033115`,
> Version 1.0 ID `ac449eb6-8d4e-4495-b260-70cff8b94699`,
> Build ID `77ada56f-dd97-4a48-bdfe-788cada26e62` (state `VALID`, attached).
>
> Re-run readiness check any time:
>
> ```bash
> PROFILE=industrietrainer asc --profile "$PROFILE" \
>   validate --app 6767033115 --version 1.0 --output table
> ```

## ✅ Already pushed (verified `asc validate` blocking=0)

| Resource | Detail |
|---|---|
| **App record** | `Mathio: Math Practice` / bundle `com.kgz.Mathio` |
| **Build** | uploaded by `archive.sh`, processed `VALID` in <5 min, attached to v1.0 |
| **Subtitle EN** | `Algebra, geometry & calculus` |
| **Subtitle DE** | `Algebra, Analysis & Geometrie` |
| **Description** | EN 2115 chars / DE 2346 chars (`docs/aso/{en-US,de-DE}/description.txt`) |
| **Keywords EN** | `mathe,maths,algebra,calculus,geometry,trigonometry,fractions,equations,formulas,homework,exam,tutor` (98/100) |
| **Keywords DE** | `mathe,üben,algebra,analysis,geometrie,trigonometrie,bruchrechnen,gleichung,formeln,abitur,klausur` (97/100) |
| **Promotional text** | EN + DE (Siri quick-launch hook) |
| **Support / Marketing URL** | `https://meloxkgz-ship-it.github.io/mathio/` (200 OK) |
| **Privacy / Terms URLs** | `https://meloxkgz-ship-it.github.io/mathio/{privacy,terms}` (both 200 OK) |
| **Screenshots** | 12 PNGs (EN + DE × 6 each), 1320 × 2868, slot `APP_IPHONE_67` (= 6.9-inch) |
| **Copyright** | `2026 Filippos Kagkiouzis` |
| **Age rating** | all 22 fields `NONE`/`false` (`asc age-rating edit --all-none` — math practice, zero adult content) |
| **App Review contact** | Filippos Kagkiouzis · meloxkgz@icloud.com · +4915731317011 |
| **Reviewer notes** | 7-tap-on-version-label premium override path, written verbatim into the review detail |

## ⚠️ Three things you finish in the browser (~5 min)

### 1. Subscriptions — fill metadata + add to submission

`asc validate` lists three non-blocking warnings about subscriptions, but
Apple **does** require all three to be submitted alongside the app version
on a first release. Per Apple: *"first-time subscriptions must be submitted
via the app version page in App Store Connect (not the API)"*.

Open https://appstoreconnect.apple.com/apps/6767033115/distribution
→ section **In-App Purchases and Subscriptions** → for each:

| Product | State | What to do |
|---|---|---|
| `mathio_annual` (`6767033716`) | `READY_TO_SUBMIT` | click "Add to next submission" |
| `mathio_weekly` (`6767033995`) | `MISSING_METADATA` | add EN + DE display name & description, confirm pricing + availability, then "Add to next submission" |
| `mathio_retention` (`6767033879`) | `MISSING_METADATA` | same as weekly |

EN/DE display names and descriptions are in
`docs/aso/de-DE/metadata.md` (bottom table, "In-App-Käufe (DE-Texte)").

### 2. App Privacy — confirm published

`asc validate` flags `privacy.publish_state.unverified` because the Privacy
Manifest publish state isn't readable via the public API. Open
https://appstoreconnect.apple.com/apps/6767033115/appPrivacy and confirm
the page shows **Published** (it should — the manifest is in the binary).

### 3. Submit for review

Once steps 1 + 2 are green, on the App Store version page click
**Add for Review** → review the summary → **Submit for Review**.

The review timer (24-48 h typical for first-time apps) starts then. You
can watch progress with:

```bash
asc --profile industrietrainer review status --app 6767033115
```

## What everything was changed by

Every CLI mutation that landed today is reproducible:

```bash
PROFILE=industrietrainer
APP=6767033115
VID=ac449eb6-8d4e-4495-b260-70cff8b94699
BID=77ada56f-dd97-4a48-bdfe-788cada26e62

# Listing copy + screenshots — re-run end-to-end:
PROFILE=$PROFILE bash docs/aso/scripts/submit.sh --no-submit

# Individual fixes:
asc --profile $PROFILE versions update      --version-id $VID --copyright "2026 Filippos Kagkiouzis"
asc --profile $PROFILE versions attach-build --version-id $VID --build $BID
asc --profile $PROFILE age-rating edit       --app $APP        --all-none
asc --profile $PROFILE review details-create --version-id $VID \
  --contact-first-name Filippos --contact-last-name Kagkiouzis \
  --contact-email meloxkgz@icloud.com --contact-phone +4915731317011 \
  --notes "<7-tap reviewer instructions>"
```

If you ever want to redo this from scratch (e.g. a 1.1 release), the
scripts in `docs/aso/scripts/` cover the full path:

| Script | What it does |
|---|---|
| `screenshots.sh` | Capture 6 PNGs in a given locale via simctl + MATHIO_PREVIEW |
| `sync_xcstrings.py` | Self-checking DE-translation sync — fails the run if any UI prose is unlocalised |
| `archive.sh` | xcodebuild archive + IPA upload to App Store Connect |
| `submit.sh` | Push metadata + screenshots, gated SUBMIT prompt for review enqueue |
| `export-options.plist` | Distribution + signing config used by `archive.sh` |
