# Keyword Research — Mathio

Working notes behind the keyword choices in `en-US/metadata.md` and
`de-DE/metadata.md`. Update before each major release.

## Apple's algorithm — fast recap

1. **Match sources Apple indexes:** App Name, Subtitle, Keywords field,
   In-App Purchase names, In-App Event metadata. **Description is *not*
   indexed for search** since 2017.
2. **Stemming is partial:** singular/plural sometimes hit, conjugations
   rarely. Use the most-typed form.
3. **Localisation matters:** the keyword field is per-locale. The DE
   field competes only against other DE-locale apps.
4. **Apple ignores** these as keywords because they are added implicitly
   to every English app: `app`, `apps`, `iOS`, `iPhone`, `iPad`, `Apple`,
   `free`. Don't waste characters on them.
5. **Don't repeat.** A token in App Name + Subtitle is already indexed.
   Repeating it in Keywords is wasted slots — Apple deduplicates.

## Direct competitors (mapped 2026-05)

| App                         | Subtitle                              | Notes                                         |
|-----------------------------|---------------------------------------|-----------------------------------------------|
| **Brilliant**               | Learn by doing                        | Premium, gamified, broad STEM                 |
| **Math Zen**                | Calm math practice                    | Closest spirit-cousin; minimal UI             |
| **Photomath**               | Math problem solver                   | Camera-OCR solver, very different UX          |
| **Khan Academy**            | Free online learning                  | Free, broad-stroke; not a daily-trainer       |
| **Math Riddles & Puzzles**  | Brain teasers for adults              | Casual, not curriculum                        |
| **Quick Math+**             | Mental math practice                  | Arithmetic only — different audience          |

**Mathio's wedge:** "Brilliant's calm cousin" — focused on K-12 / early
college math curriculum (not lateral thinking puzzles), opinionated about
spaced repetition, no leaderboards, no LaTeX.

## Keyword candidates (EN)

Sorted by estimated descending search volume × intent fit:

| Term            | Volume | Fit | Used? | Notes                                         |
|-----------------|--------|-----|-------|-----------------------------------------------|
| math            | ★★★★★  | ★★★ | impl. | In subtitle implicitly via topic words        |
| algebra         | ★★★★   | ★★★ | ✅    | Core topic                                    |
| calculus        | ★★★    | ★★★ | ✅    | Core topic                                    |
| geometry        | ★★★    | ★★★ | ✅    | Core topic                                    |
| trigonometry    | ★★     | ★★★ | ✅    | Core topic                                    |
| fractions       | ★★★    | ★★  | ✅    | Pre-algebra anchor; high parent-search        |
| equations       | ★★★    | ★★★ | ✅    | Strong intent ("solve equations")             |
| formulas        | ★★★    | ★★  | ✅    | Formula reference is a real feature           |
| homework        | ★★★★   | ★★  | ✅    | Student/parent searches                       |
| exam            | ★★★    | ★★  | ✅    | SAT/ACT/AP prep adjacency                     |
| tutor           | ★★★    | ★★  | ✅    | High commercial intent                        |
| maths           | ★★★    | ★★★ | ✅    | UK English variant — Apple does *not* stem    |
| mathe           | ★★     | ★★  | ✅    | DE users searching in EN store                |
| brilliant       | ★★★    | ★★★ | ✗     | Trademark — *do not* use, Apple rejects       |
| photomath       | ★★★★   | ★★  | ✗     | Trademark — *do not* use                      |
| solver          | ★★★    | ★   | ✗     | Mismatched expectation: we're a trainer       |
| daily           | ★★     | ★★  | ✗     | Reserved for promotional text                 |
| practice        | ★★★    | ★★★ | impl. | Already in app description — Apple soft match |
| learning        | ★★★    | ★★  | ✗     | Too generic; better in subtitle if at all     |

**Final string** (98/100):
```
mathe,maths,algebra,calculus,geometry,trigonometry,fractions,equations,formulas,homework,exam,tutor
```

## Keyword candidates (DE)

| Term            | Volume | Fit | Used? | Notes                                          |
|-----------------|--------|-----|-------|------------------------------------------------|
| mathe           | ★★★★★  | ★★★ | ✅    | Highest-volume DE term in education            |
| üben            | ★★★★   | ★★★ | ✅    | Imperative form most-typed by students         |
| algebra         | ★★★    | ★★★ | ✅    | Same                                           |
| analysis        | ★★     | ★★★ | ✅    | DE term for calculus — *do* use                |
| geometrie       | ★★★    | ★★★ | ✅    | Same                                           |
| trigonometrie   | ★★     | ★★★ | ✅    | Same                                           |
| bruchrechnen    | ★★★    | ★★  | ✅    | Strong parent-search ("Brüche üben")           |
| gleichung       | ★★     | ★★  | ✅    | "Gleichung lösen"                              |
| formeln         | ★★     | ★★  | ✅    | Formula reference                              |
| abitur          | ★★★    | ★★  | ✅    | High-intent (Abitur prep)                      |
| klausur         | ★★★    | ★★  | ✅    | Same                                           |
| nachhilfe       | ★★★★   | ★   | ✗     | Spielt eine andere Erwartung — wir sind Drill  |
| schule          | ★★★★   | ★   | ✗     | Zu generisch                                   |
| kostenlos       | ★★★★   | ★   | ✗     | Apple ignoriert „free"-Äquivalente             |
| differential    | ★      | ★★★ | ✗     | Niedriges Volumen, Zeichen schade              |

**Final string** (97/100):
```
mathe,üben,algebra,analysis,geometrie,trigonometrie,bruchrechnen,gleichung,formeln,abitur,klausur
```

## Iteration plan

- **Week 2 post-launch:** open App Store Connect → App Analytics →
  Sources → Search. Identify the top 5 search terms driving impressions.
  Swap underperformers (lowest weight slots) for those terms.
- **Month 2:** check competitor subtitle changes; reconsider whether the
  current subtitle still wins on impressions. A/B is not natively
  supported by Apple — change once, observe 2 weeks, decide.
- **Month 3:** evaluate adding a third secondary category (Apple allows
  one primary + one secondary — pick **Productivity** or swap for
  **Reference** if formula-reference traffic dominates).

## Things to **never** put in the keyword field

- Other app names (`brilliant`, `khan`, `photomath`) — App Review rejects.
- Apple's own platforms (`iPad`, `Apple Watch`) — auto-indexed.
- The word `app`, `application`, `iOS`, `Apple`, `for-iPhone` — ignored.
- Plurals when Apple already stems (it usually doesn't, but `math`/`maths`
  is a known case where it does *not* stem — both are valid).
- Punctuation other than commas. No emoji. No hashtags.
