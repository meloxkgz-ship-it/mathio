# Mathio — App Store Optimization (ASO)

Copy-paste targets for **App Store Connect → My Apps → Mathio**.
Two locales: `en-US/` (primary) and `de-DE/` (German market).

## Field length limits (App Store Connect)

| Field              | Limit       | Notes                                                          |
|--------------------|-------------|----------------------------------------------------------------|
| App Name           | 30 chars    | Indexed by Apple Search; appears under icon                    |
| Subtitle           | 30 chars    | Indexed; second-strongest ranking signal                       |
| Keywords           | 100 chars   | Comma-separated, **no spaces after commas**, no repeats        |
| Promotional Text   | 170 chars   | Editable without review — use for time-bound messaging         |
| Description        | 4000 chars  | Not indexed for search (since 2017) — convert visitors instead |
| What's New         | 4000 chars  | Per release; first 4 lines visible without "more"              |
| Support URL        | required    | `https://meloxkgz-ship-it.github.io/mathio/`                   |
| Privacy URL        | required    | `https://meloxkgz-ship-it.github.io/mathio/privacy`            |
| Marketing URL      | optional    | `https://meloxkgz-ship-it.github.io/mathio/`                   |
| Primary Category   |             | **Education**                                                  |
| Secondary Category |             | **Productivity** (recommended) or Reference                    |
| Age Rating         |             | 4+                                                             |
| Pricing            |             | Free with In-App Purchases (Auto-Renewable Subscription)       |

## Ranking strategy

1. **App Name + Subtitle** carry the most weight in Apple's search algorithm.
   Pack the highest-volume term that is **not** already implied by the brand
   name. "Mathio" tells Apple this is about math; the subtitle should add
   **algebra / geometry / calculus** to the index.
2. **Keywords** field: never repeat words from name/subtitle, never use
   `app`/`iOS`/`free` (Apple ignores). Order by descending search volume.
3. **Localize** every field. German users do not search for "math practice".
4. **In-App Events** (App Store Connect → Events) — schedule one per month
   for ongoing visibility. E.g. "Spring Algebra Sprint", "Streak Awareness
   Week". Free, no review.
5. **Reviews flywheel:** prompt only after a 5-day streak or first lesson
   completion (already handled in app via `SKStoreReviewController`-style
   gate — verify before launch).

## Files in this folder

- `en-US/metadata.md`  — every text field, EN copy, ready to paste
- `de-DE/metadata.md`  — every text field, DE copy, ready to paste
- `keyword-research.md` — competitor mapping + reasoning for the chosen keywords
- `screenshots-spec.md` — screenshot list, captions, sizes per device
- `release-checklist.md` — final pre-submit checklist
