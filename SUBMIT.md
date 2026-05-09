# Mathio — final 3 manual steps to live in the App Store

Code is launch-ready. Screenshots are captured (12 PNGs, EN + DE × 6 targets,
1320 × 2868 in `docs/screenshots/{en-US,de-DE}/iphone/`). All 699 string-
catalog keys translated. Two listing pages (privacy, terms) are live and
returning 200 OK on GitHub Pages.

What's left is **3 steps that need your hands**, because Apple gates each one
behind 2-factor authentication tied to your Apple ID — no CLI tool can bypass
that, including `asc`. After step 3 the binary is uploaded and the review
clock starts.

Total time: ~20 minutes.

---

## Step 1 — App Store Connect API key (browser, ~3 min)

This unlocks the `asc` CLI for everything that follows.

1. Open **https://appstoreconnect.apple.com/access/integrations/api** while
   signed in as the account holder.
2. Click **+** → name it `Mathio CLI` → role **App Manager**.
3. Click **Generate**, then **download the .p8 file immediately** —
   Apple shows it exactly once.
4. Note the **Key ID** (10 chars) and the **Issuer ID** (UUID at the top
   of the page).

```bash
# Stash the .p8 somewhere stable
mkdir -p ~/.asc
mv ~/Downloads/AuthKey_*.p8 ~/.asc/AuthKey_Mathio.p8

# Register with asc, then make it the default profile
asc auth login \
  --name      Mathio \
  --key-id    <KEY_ID> \
  --issuer-id <ISSUER_ID> \
  --private-key ~/.asc/AuthKey_Mathio.p8

asc auth switch --name Mathio
asc auth status     # shows "Mathio" as default → ready
```

> The unrelated `industrietrainer` profile in your keychain stays intact;
> `asc auth switch` toggles between them.

---

## Step 2 — Build + upload the binary (one command, ~10 min)

```bash
docs/aso/scripts/archive.sh
```

This runs `xcodebuild archive` against the existing `iPhone Distribution:
Filippos Kagkiouzls (T3BRJDPUGM)` cert in your keychain, then exports +
uploads via the bundled `export-options.plist`. The first upload of bundle
ID `com.kgz.Mathio` **also creates the App Store Connect app record** —
you don't need a separate "create app" step.

If you'd rather use the GUI: open `iOS/Mathio/Mathio.xcodeproj`, target
`Any iOS Device (arm64)`, **Product → Archive**, then **Distribute App →
App Store Connect → Upload**.

Wait until the new build appears in App Store Connect's **TestFlight** tab
(usually 5–15 min after the upload completes). That confirms Apple has
finished processing it; only then is step 3 useful.

---

## Step 3 — Push metadata + screenshots + submit (one command, ~3 min)

```bash
docs/aso/scripts/submit.sh --dry-run    # see what it would do, mutates nothing
docs/aso/scripts/submit.sh              # for real
```

Six numbered phases with progress output:

```
[0/6] Verify asc auth
[1/6] Resolve App Store Connect app ID
[2/6] Resolve target version (creates 1.0 if absent)
[3/6] App-info localisation (subtitle, EN + DE)
[4/6] Version localisation (description, keywords, promo, what's-new)
[5/6] Screenshots — iPhone 6.9-inch (12 PNGs)
[6/6] Submit for review                 ← stops, asks "type SUBMIT"
```

Type **SUBMIT** at the prompt to enqueue the version for App Review.
Anything else aborts safely.

> Before submitting, paste the **Notes for Reviewer** block (below) into
> App Store Connect → Version → App Review Information. `asc submit` does
> not write that field.

### Verbatim Notes for Reviewer

```
Mathio has no user accounts. To test premium features without a purchase:
1. Open the app → finish onboarding → tap the gear icon (Settings)
2. Tap the version line at the bottom of the Settings list 7 times.
3. A confirmation banner shows "Premium unlocked for review" and the
   Subscription section now displays the active state. Premium remains
   unlocked across relaunches until you tap 7 more times to clear it.

Alternatively the StoreKit configuration in the binary points at Apple's
sandbox environment — any sandbox tester account works for the real IAP
flow against `mathio_annual` / `mathio_weekly`.
```

---

## What does **not** need your time

| | Where it lives |
|---|---|
| UI translations | `Localizable.xcstrings` — 699 keys, 100% DE coverage. Adding new strings? Run `python3 docs/aso/scripts/sync_xcstrings.py` from `iOS/Mathio/Mathio/` — it fails the build if a new prose string lacks a German translation. |
| Screenshots | `docs/screenshots/{en-US,de-DE}/iphone/*.png` — 12 PNGs at 1320 × 2868. Re-capture with `docs/aso/scripts/screenshots.sh <SIM_UDID> <LOCALE> <OUTPUT_DIR>`. |
| Listing copy | `docs/aso/{en-US,de-DE}/{description,whats-new}.txt` — read by `submit.sh`. |
| Subtitle / keywords | Hard-coded in `submit.sh` (length-validated against Apple's 30 / 100-char limits). |
| Privacy / Terms hosting | Live at `https://meloxkgz-ship-it.github.io/mathio/{privacy,terms}` — both 200 OK. |
| Reviewer demo path | 7-tap on Settings version label, persisted via `mathio.reviewer.override` in `UserDefaults`. |
| Privacy manifest | `iOS/Mathio/Mathio/PrivacyInfo.xcprivacy` — declares no tracking, no collected data types. Yields the "Data Not Collected" badge in the listing. |
| App Icon | `iOS/Mathio/Mathio/Assets.xcassets/AppIcon.appiconset/Icon-1024.png` — 1024 × 1024 RGB, no alpha, App-Store-spec compliant. |

---

## If something breaks

- **`asc apps list` returns empty:** Apple only creates the app record after
  the first binary upload. Do step 2 first; come back to step 3.
- **Code-signing error in step 2:** Open Xcode → Settings → Accounts →
  click your Apple ID → **Manage Certificates** → confirm the
  "Apple Distribution" cert is there. If absent, click **+ → Apple
  Distribution** to regenerate, retry `archive.sh`.
- **`submit.sh` fails at step 3 or 4 with "version not found":** the build
  from step 2 is still processing on Apple's side. Wait until it shows up
  in the App Store Connect TestFlight tab, then re-run.
- **App Review rejects metadata:** the most common cause is missing IAP
  localisation. In App Store Connect → In-App Purchases, every product
  needs both an EN and a DE display name + description (the bottom table
  in `docs/aso/de-DE/metadata.md` has copy-paste DE values).
