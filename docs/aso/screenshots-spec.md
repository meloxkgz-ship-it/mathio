# Screenshots & App Preview Spec

## Required device sizes (App Store Connect, 2026)

Apple now accepts a **single set of 6.9-inch iPhone screenshots** for all
iPhones (auto-downscaled). For best presentation, ship two sizes:

| Display name           | Pixel size   | Device class                                    |
|------------------------|--------------|-------------------------------------------------|
| 6.9" iPhone (required) | 1290 × 2796  | iPhone 16/17 Pro Max — covers all newer iPhones |
| 6.5" iPhone (legacy)   | 1242 × 2688  | iPhone 11 Pro Max — only if explicitly uploaded |
| 13" iPad Pro           | 2064 × 2752  | Required if app is iPad-compatible (we are: `TARGETED_DEVICE_FAMILY=1,2`) |

> The current `docs/screenshots/*.png` files are 1320 × 2868. Scale to
> **1290 × 2796** for the 6.9" iPhone slot (Apple validates exact size).

## Screenshots to ship — 6 per locale

Order matters. The first **2** are the *only* ones visible on the search
results page; the rest unlock when the user opens the listing.

| # | Slot                | What it shows                                         | Caption (EN, ≤24 chars)         | Caption (DE, ≤24 chars)         |
|---|---------------------|-------------------------------------------------------|---------------------------------|---------------------------------|
| 1 | Hero / value prop   | Home screen with daily-streak ring at full focus      | `Math, made simple.`            | `Mathe. Einfach gemacht.`       |
| 2 | Differentiator      | Wrong-answer step-by-step solution view               | `Never just "Not quite."`       | `Nie nur „Leider falsch."`      |
| 3 | Topic breadth       | Topic list (algebra → calculus etc.)                  | `5 topics. 14 lessons.`         | `5 Themen. 14 Lektionen.`       |
| 4 | Habit / streak      | Calendar heatmap on Stats view                        | `Build a calm habit.`           | `Eine ruhige Gewohnheit.`       |
| 5 | Feature: review     | Review queue with overdue questions                   | `Spaced repetition.`            | `Verteiltes Üben.`              |
| 6 | Closer (paywall ok) | Paywall with annual plan highlighted, trial visible   | `Free 7-day trial.`             | `7 Tage gratis testen.`         |

> Screenshot 6 may show the paywall **only** if the trial CTA is visible
> and the price disclosure is legible — Apple Review checks this against
> 3.1.2.

## Caption styling (in-image text — *not* App Store Connect captions)

- Top-of-screen banner, not bottom — the bottom is cropped on search.
- 56–72 pt SF Pro Display Bold (or your in-app `font-display`).
- Cream background `#FBF7F1` for light / `#12100E` for dark, matching
  `LaunchBackground.colorset`. Pick one and stick with it across the set
  for visual consistency.
- Caption **must not** repeat the App Name. Apple's reviewer guidelines
  flag this as redundant.

## Generating the screenshots (DEBUG-only env-var route)

`MathioApp.swift` already has a `MATHIO_PREVIEW=...` debug routing. Use
it to capture clean shots from the simulator:

```bash
# 1) Boot iPhone 17 Pro Max simulator
xcrun simctl boot "iPhone 17 Pro Max"

# 2) Build with the right env var, install, then launch:
xcodebuild -scheme Mathio -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcrun simctl install booted ~/Library/Developer/Xcode/DerivedData/Mathio-*/Build/Products/Debug-iphonesimulator/Mathio.app

# 3) Launch each preview target and screenshot:
for target in home lesson practice paywall stats formulas; do
  xcrun simctl launch --terminate-running-process booted \
    --setenv MATHIO_PREVIEW="$target" com.kgz.Mathio
  sleep 2
  xcrun simctl io booted screenshot \
    "docs/screenshots/en-US/$target-6.9.png"
done

# 4) Repeat with -lang de -locale de_DE for the DE set:
xcrun simctl spawn booted launchctl setenv AppleLanguages "(de)"
# then re-run the loop, output to docs/screenshots/de-DE/
```

## App Preview video (optional, +~15% conversion)

- 15–30 seconds, **no audio narration** required (auto-muted on listing).
- Same device sizes as screenshots.
- File format: `.mp4` or `.mov`, H.264, ≤500 MB.
- Storyboard:
  1. Brand frame (1s) — Mathio mark on cream
  2. Topic select → first lesson tap (3s)
  3. Practice question, type answer, correct (4s)
  4. Wrong answer → step-by-step solution unfolds (6s)
  5. Stats heatmap with growing streak (3s)
  6. End frame: brand mark + "Free 7-day trial" (3s)

> Recording with `xcrun simctl io booted recordVideo`. Edit out cursor
> moves; the App Store validator rejects videos with a visible cursor.
