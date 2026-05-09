# Mathio v1.0 — final state, **only Web-UI clicks left**

> Live in App Store Connect, verified at the time of this commit.
> App ID `6767033115`, Version ID `ac449eb6-8d4e-4495-b260-70cff8b94699`,
> Build ID `77ada56f-dd97-4a48-bdfe-788cada26e62`, Subscription Group
> `22071889`.

## ✅ All 28 `asc validate` blockers cleared

Latest validate snapshot:

```
errors: 0   warnings: 6   infos: 1   blocking: 0
```

Everything below was set via `asc` against the App Store Connect API:

| Resource | Detail |
|---|---|
| App record | `Mathio: Math Practice` (existed, not auto-created) |
| Build | uploaded by `archive.sh`, processed VALID in ~1 min, attached to v1.0 |
| Subtitle EN / DE | `Algebra, geometry & calculus` / `Algebra, Analysis & Geometrie` |
| Description, Keywords, Promo, Support+Marketing URL | EN + DE |
| Screenshots | 12 PNGs (EN + DE × 6 each), slot `APP_IPHONE_67` |
| Copyright | `2026 Filippos Kagkiouzis` |
| Age rating | all 22 fields `--all-none` (math practice) |
| Reviewer contact + notes | Filippos Kagkiouzis · meloxkgz@icloud.com · +4915731317011 + 7-tap unlock instructions |
| App Privacy | published (manual web step, completed) |
| **Subscription `mathio_annual`**   | `READY_TO_SUBMIT` |
| **Subscription `mathio_weekly`**   | `READY_TO_SUBMIT` (transitioned after `--review-note` set) |
| **Subscription `mathio_retention`**| `READY_TO_SUBMIT` (same) |

## ⚠️ Last 4 clicks — **must use the official Web UI**

`asc review submit` will succeed but **leaves the subscriptions out** of the
review submission. asc itself flags this:

> the following subscriptions are READY_TO_SUBMIT but are not automatically
> included in this submission

The unofficial `asc web review subscriptions attach-group` workaround uses
**private undocumented Apple endpoints** that may "violate Apple's Developer
Program License Agreement" and lead to account restrictions or termination.
Don't use it for v1.0.

The supported path:

1. Open https://appstoreconnect.apple.com/apps/6767033115/distribution
2. Scroll to the **In-App Purchases and Subscriptions** section on the
   version page. Each subscription should now show **READY TO SUBMIT** with
   an **Add to Next Submission** button — click for all three:
   - `Mathio Annual` (`mathio_annual`)
   - `Mathio Weekly` (`mathio_weekly`)
   - `Mathio Annual Retention` (`mathio_retention`)
3. Confirm the version page top reads **Add for Review** (or **Submit for
   Review** depending on cache).
4. Click **Add for Review** → review the summary modal → **Submit**.

That's it. App Review timer (24-48 h typical for a first-time submission)
starts when the request lands.

Watch progress without leaving the terminal:

```bash
asc --profile industrietrainer review status --app 6767033115
asc --profile industrietrainer review submissions-list --app 6767033115
```

## What `asc` did and how to re-do it

```bash
PROFILE=industrietrainer
APP=6767033115
VID=ac449eb6-8d4e-4495-b260-70cff8b94699
BID=77ada56f-dd97-4a48-bdfe-788cada26e62
GID=22071889
ASC=asc

# Listing copy + screenshots — re-runnable end-to-end:
PROFILE=$PROFILE bash docs/aso/scripts/submit.sh --no-submit

# Individual fixes that turned 28 blockers → 0:
$ASC --profile $PROFILE versions update      --version-id $VID --copyright "2026 Filippos Kagkiouzis"
$ASC --profile $PROFILE versions attach-build --version-id $VID --build $BID
$ASC --profile $PROFILE age-rating edit       --app $APP        --all-none
$ASC --profile $PROFILE review details-create --version-id $VID \
  --contact-first-name Filippos --contact-last-name Kagkiouzis \
  --contact-email meloxkgz@icloud.com --contact-phone +4915731317011 \
  --notes "<7-tap reviewer instructions>"

# Subscription readiness — sets review-note, transitions state to READY_TO_SUBMIT:
for SID in 6767033995 6767033879 6767033716; do
  $ASC --profile $PROFILE subscriptions update --id $SID \
    --review-note "Subscription unlocks all topics in Mathio. Reviewer can test without purchase: open app, finish onboarding, tap Settings (gear icon), tap version label at bottom 7 times - 'Premium unlocked for review' banner confirms. Premium persists across launches."
done

# Pre-submit readiness check:
$ASC --profile $PROFILE validate --app $APP --version 1.0 --output table
```

## After review starts

- The review state switches `READY_FOR_REVIEW` → `IN_REVIEW` → `PENDING_DEVELOPER_RELEASE`.
- Apple sends an email (sometimes within 24 h, sometimes 48 h, occasionally 72 h for first-time apps).
- For v1.0 with `--release-type` defaulted, you'll click **Release this version** in App Store Connect once approved.
- If rejected: `asc review show --app 6767033115` (or web UI) shows the reason. Most v1.0 rejections are about reviewer demo credentials — our 7-tap path covers that, but if anything is unclear, expand the `--notes` field via:
  ```bash
  asc --profile industrietrainer review details-update --id <DETAIL_ID> --notes "<...>"
  ```
  (DETAIL_ID printed by `details-create` earlier: `fb272b37-f2fb-40ae-8cdb-46d8d2743e5e`).
