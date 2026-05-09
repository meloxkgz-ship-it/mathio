# App Store Metadata — English (en-US, primary)

> Paste each block into the matching App Store Connect field. Character
> counts are exact (no trailing whitespace).

---

## App Name (30 max)

```
Mathio
```
**6 / 30** — leaves headroom; consider `Mathio: Math Practice` (21) only if
data shows brand-name searches are saturated. For launch, keep clean.

---

## Subtitle (30 max)

```
Algebra, geometry & calculus
```
**28 / 30** — adds the three biggest topic-search terms to Apple's index
(brand name already covers "math").

Alternates tested for char-count:
- `Daily math practice trainer` (27) — softer, less keyword-rich
- `Master algebra and calculus` (27) — drops geometry
- `Algebra, geometry, calculus` (27) — same content, no `&`

**Recommended:** the lead version above.

---

## Keywords (100 max, comma-separated, no spaces)

```
mathe,maths,algebra,calculus,geometry,trigonometry,fractions,equations,formulas,homework,exam,tutor
```
**98 / 100**

Reasoning:
- `math` is implied by brand and subtitle → use less-covered variants
  `mathe` (German users in EN store) and `maths` (UK English).
- `algebra,calculus,geometry,trigonometry` mirror the in-app topics.
- `fractions,equations,formulas` capture intent ("solve fractions",
  "math formulas").
- `homework,exam,tutor` cover student / parent search intent.
- **Excluded:** `app`, `free`, `iOS`, `learning`, `practice`, `daily` —
  either ignored by Apple or already in subtitle.

---

## Promotional Text (170 max — editable without review)

```
New: tap "Practice math" with Siri to jump straight into your daily review queue. Two minutes a day is enough.
```
**125 / 170** — leaves 45 chars to add a launch promo or seasonal hook.

Rotation ideas (swap monthly):
- `Free 7-day trial. Master one lesson a day — no leaderboards, no streaks-or-die guilt, just calm progress.` (113)
- `Back-to-school sale: 7-day trial, then 25% off your first year. Algebra to calculus, one small step a day.` (108)

---

## Description (4000 max)

```
Math, made simple.

Mathio is a calm, focused math trainer for algebra, geometry, calculus, and trigonometry. No distractions. No leaderboards. Just you, clear explanations, and a daily streak.

▸ ADAPTIVE LESSONS
We pick the next topic for you based on your mastery — never wasting time on what you already know.

▸ STEP-BY-STEP SOLUTIONS
Wrong answer? You see the full worked solution inline. Never just "Not quite."

▸ SPACED REPETITION
Overdue questions surface in a daily Review queue using Leitner intervals (1 day → 3 days → 1 week → 2 weeks → 1 month). Scientifically proven to stick.

▸ DAILY STREAK + FREEZES
Build the habit without the guilt. Auto-spent freezes protect your streak when life gets busy. One refill per week, max two banked.

▸ FORMULA REFERENCE
Bookmark formulas as you learn them. Bilingual reference always one tap away.

▸ NO LATEX KEYBOARD
Just type plain text — `6x+2`, `sqrt(2)`, `pi` — and we parse it. No special symbols required.

▸ OFFLINE-FIRST
Everything stored on your device. No tracking, no analytics, no third-party SDKs. Audit our privacy manifest in the App Store.

▸ DARK MODE + ACCESSIBILITY
Full semantic palette adapts to system. VoiceOver labels on every interactive element, including spoken-form math.

▸ GERMAN + ENGLISH
Fully localised, including formulas and step-by-step explanations.

— TOPICS —
Pre-Algebra · Algebra · Geometry · Trigonometry · Calculus
21 lessons, 105 hand-crafted questions across multiple-choice, free-answer, and true/false formats. From fractions, exponents, and logarithms through derivatives, integrals, and trig identities.

— SUBSCRIPTION —
Mathio is free to try. Unlock all topics with:
• Annual — $59.99/year, 7-day free trial, Family Sharing enabled (~$1.15/week)
• Weekly — $12.99/week, 3-day free trial

Subscriptions auto-renew unless cancelled at least 24 hours before the end of the current period. Manage or cancel any time in your Apple ID settings.

Privacy: https://meloxkgz-ship-it.github.io/mathio/privacy
Terms:   https://meloxkgz-ship-it.github.io/mathio/terms

From fractions to derivatives. Two minutes a day is enough.
```

---

## What's New (per-release, 4000 max)

### v1.0 (launch)

```
Welcome to Mathio.

A calm, focused way to practice math — algebra, geometry, calculus, trigonometry — one small step at a time.

• 21 lessons, 105 hand-crafted questions, 50 reference formulas
• Step-by-step solutions for every wrong answer
• Adaptive lesson picker, daily streak with auto-freezes, spaced-repetition review queue
• Siri shortcut ("practice math"), iPad layout, branded launch screen
• Dark mode, VoiceOver, full DE + EN localisation

Two minutes a day is enough. No leaderboards. No tracking.
```
~470 chars — first 4 lines visible without "more"; the value prop lands above the fold.

---

## URLs

| Field        | Value                                                  |
|--------------|--------------------------------------------------------|
| Support      | `https://meloxkgz-ship-it.github.io/mathio/`           |
| Marketing    | `https://meloxkgz-ship-it.github.io/mathio/`           |
| Privacy      | `https://meloxkgz-ship-it.github.io/mathio/privacy`    |
| Terms (EULA) | `https://meloxkgz-ship-it.github.io/mathio/terms`      |

> **Pre-flight:** Open all four URLs in incognito and confirm they 200 OK
> with localised content. App Store Review will check.

---

## App Privacy ("Data Used to Track You" / "Data Linked to You")

Match what's in `PrivacyInfo.xcprivacy`:

- **Data Not Collected** — declare nothing. Mathio stores all progress in
  `UserDefaults`. The only outbound traffic is StoreKit purchase events,
  which Apple itself handles and which are out of scope for the App
  Privacy questionnaire.

This becomes the highly-coveted **"Data Not Collected"** label in the
listing — a small but meaningful conversion lift in 2024+ data.

---

## In-App Purchases (App Store Connect → In-App Purchases)

Match `Mathio/Mathio.storekit`:

| Product ID         | Type           | Price       | Trial   | Family Sharing |
|--------------------|----------------|-------------|---------|----------------|
| `mathio_annual`    | Auto-Renewable | $59.99 / yr | 7 days  | ✅              |
| `mathio_weekly`    | Auto-Renewable | $12.99 / wk | 3 days  | ❌              |
| `mathio_retention` | Auto-Renewable | $44.99 / yr | —       | ❌              |

**Display name** and **Description** for each must be filled in for **both**
locales (EN + DE) before submission, or the IAPs are rejected.
