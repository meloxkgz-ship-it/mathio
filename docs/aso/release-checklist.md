# Mathio v1.0 — Pre-Submit Release Checklist

Run top-to-bottom before tapping **Submit for Review** in App Store Connect.

## 1 — Xcode project sanity

- [x] Bundle ID: `com.kgz.Mathio`
- [x] Marketing version: `1.0`
- [x] Build number: `1` (bump for every TestFlight upload)
- [x] iOS Deployment Target: `18.0` (intentional per README)
- [x] `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` (skips export-compliance dialog)
- [x] `INFOPLIST_KEY_LSApplicationCategoryType = public.app-category.education`
- [x] `INFOPLIST_KEY_UILaunchScreen_BackgroundColor = LaunchBackground` (cream/dark adaptive)
- [x] `TARGETED_DEVICE_FAMILY = 1,2` (iPhone + iPad)
- [x] `PrivacyInfo.xcprivacy` — `NSPrivacyTracking=false`, no collected types
- [x] `Mathio.storekit` — 3 products, intro offers, family sharing on annual
- [x] AppIcon: 1024×1024 universal (Xcode auto-generates all device sizes from this)
- [x] `URL(string:)!` force-unwraps eliminated → centralised `Links` enum

## 2 — Local build

```bash
cd "iOS/Mathio"
xcodebuild -scheme Mathio \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -configuration Release build CODE_SIGNING_ALLOWED=NO
```

- [ ] **Release** config compiles clean (Debug works; verify Release once)
- [ ] Zero warnings in Issue Navigator
- [ ] Run on physical device once — touch every flow:
  - Onboarding → Topic → Lesson → Practice (correct + wrong)
  - Review queue (after letting at least one question go overdue)
  - Streak freezes (force-set date in `UserDefaults` for QA)
  - Paywall → tap each plan → restore → cancel flow
  - Settings → daily reminder toggle → grant notification permission
  - Bookmarks → formula reference (DE + EN)

## 3 — App Store Connect — first-time setup

- [ ] **App Information**
  - Primary language: English (U.S.)
  - Bundle ID: `com.kgz.Mathio`
  - Primary category: **Education**
  - Secondary category: **Productivity**
  - Age rating questionnaire — answer No to every "frequent/intense"
- [ ] **Pricing & Availability** — Free, all territories
- [ ] **App Privacy** — declare *Data Not Collected* (matches `PrivacyInfo.xcprivacy`)
- [ ] **In-App Purchases** — create all three products
  - Cleared for Sale = ON
  - DE display name + description filled (App Review rejects empty locales)
  - Annual: enable Family Sharing
  - Submit IAPs *with* the binary (otherwise paywall stays empty in Review)

## 4 — App Store Connect — listing copy

For each locale (en-US, de-DE), paste from `docs/aso/<locale>/metadata.md`:

- [ ] App Name
- [ ] Subtitle
- [ ] Promotional Text
- [ ] Description
- [ ] What's New (skip on first version — auto-populated)
- [ ] Keywords
- [ ] Support URL
- [ ] Marketing URL
- [ ] Privacy Policy URL

## 5 — Screenshots

For each locale (en-US, de-DE), upload **6 × 6.9-inch iPhone** screenshots
in the order from `docs/aso/screenshots-spec.md`. iPad screenshots can
reuse the iPhone set (Apple downscales) but **better:** capture native
13" iPad shots since `TARGETED_DEVICE_FAMILY` includes iPad.

- [ ] EN: 6 × `1290 × 2796` PNG
- [ ] DE: 6 × `1290 × 2796` PNG
- [ ] iPad: 6 × `2064 × 2752` PNG (or skip and let Apple downscale)
- [ ] (Optional) App Preview video — both locales

## 6 — Privacy + Terms hosted pages

The pages exist in `docs/privacy.html` + `docs/terms.html` and must be
served via GitHub Pages at the URLs declared in `Links` and metadata:

- [ ] `https://meloxkgz-ship-it.github.io/mathio/privacy` — 200 OK
- [ ] `https://meloxkgz-ship-it.github.io/mathio/terms` — 200 OK
- [ ] Both pages list **subscription duration, price, auto-renew, cancel
      instructions** (App Store Review Guideline 3.1.2)
- [ ] Both pages link to each other and to the support email

## 7 — Demo account for App Review

Education apps with paid subscriptions need a demo account or a way for
Apple's reviewer to bypass the paywall. Mathio has no account system,
so we use a **review-build flag** instead (already implemented? — verify):

- [x] **Implemented:** 7-tap on the version label in Settings toggles
      `PremiumStore.reviewerOverride` (persisted in `UserDefaults` under
      `mathio.reviewer.override`). State survives relaunch, is cleared by
      tapping again 7 times, and a brief toast confirms the new state.
- [ ] Notes for Reviewer field (paste verbatim):
  > Mathio has no user accounts. To test premium features without a
  > purchase:
  > 1. Open the app → finish onboarding → tap the gear icon (Settings)
  > 2. Tap the version line at the bottom of the Settings list 7 times.
  > 3. A confirmation banner shows "Premium unlocked for review" and the
  >    Subscription section now displays the active state. Premium remains
  >    unlocked across relaunches until you tap 7 more times to clear it.
  >
  > Alternatively the StoreKit configuration in the binary points at
  > Apple's sandbox environment — any sandbox tester account works for
  > the real IAP flow against `mathio_annual` / `mathio_weekly`.

## 8 — TestFlight run-through

- [ ] Internal testers (yourself + 1 friend) — install via TestFlight
- [ ] Both testers complete onboarding without crashes
- [ ] At least one tester triggers the paywall, hits Cancel, sees the
      retention offer, dismisses it
- [ ] Daily-reminder notification fires the next morning at 19:00
- [ ] Streak survives app force-quit + cold launch
- [ ] iPad layout passes a 30-second eye-test in landscape

## 9 — Submit

- [ ] **Phased Release** = ON (7-day rollout, lets you pull a fix fast)
- [ ] **Automatically release after approval** = OFF for v1.0
      (review timing differs from your launch window — release manually)
- [ ] Add note: "First release. Demo account info in Notes for Reviewer."
- [ ] Submit for Review

## 10 — Day-of-launch

- [ ] Manually release in App Store Connect
- [ ] Verify both locales show updated metadata in App Store search within 2 hours
- [ ] Open `https://apps.apple.com/app/idXXXXXXXX` from a phone in airplane
      → online cycle and confirm the listing renders
- [ ] Post to channels (LinkedIn, IndieHackers, Hacker News Show HN if planned)
- [ ] Monitor App Store Connect → Crashes for first 48h (zero is the goal)
