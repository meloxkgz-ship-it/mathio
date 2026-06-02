# Mathio Growth & ASO Research — 2026-06

Scope: acquire more users who are likely to keep using Mathio, not just one-time homework solvers.

## Current Store State

Source: pulled from App Store Connect for `1.0.10` on 2026-06-02.

| Locale | Name | Subtitle | Keywords | Usage |
| --- | --- | --- | --- | --- |
| en-US | Mathio: Math Practice | Algebra, geometry & calculus | `mathe,maths,algebra,calculus,geometry,trigonometry,fractions,equations,formulas,homework,exam,tutor` | 99/100 |
| de-DE | Mathio: Mathe lernen | Algebra, Analysis & Geometrie | `mathe,üben,algebra,analysis,geometrie,trigonometrie,bruchrechnen,gleichung,formeln,abitur,klausur` | 97/100 |

## Immediate ASO Finding

The keyword fields are full, but not fully efficient.

Apple indexes App Name and Subtitle, and the subtitle limit is 30 characters according to Apple's App Store Connect reference. Because of that, repeating subtitle/name tokens in the keyword field wastes keyword budget.

Current wasted terms:

- en-US: `algebra`, `calculus`, `geometry` are already in the subtitle.
- de-DE: `mathe` is already in the name; `algebra`, `analysis`, `geometrie` are already in the subtitle.

This creates the cleanest next opportunity: replace duplicate terms with high-intent long-term-learning terms.

## Market Pattern

The math category splits into two search pools:

1. Solver/homework traffic: `math solver`, `photomath`, `homework helper`, `ai tutor`, `scan`, `answer`.
2. Practice/mastery traffic: `math practice`, `algebra practice`, `calculus practice`, `exam prep`, `fractions practice`, `mental math`.

Mathio should not try to look like a camera solver. The better wedge is:

> A calm practice and exam-prep trainer with spaced repetition, step-by-step solutions, and long-term learning paths.

This is more likely to attract users who want to stay for weeks or months.

## Competitor Signals

### US Store

Observed App Store search samples:

| Query | Top visible pattern | Implication for Mathio |
| --- | --- | --- |
| `math practice` | mental math, grade practice, Khan, brain training | Compete through "practice", "problems", "mental", "daily" |
| `algebra practice` | Algebra Touch, Khan, Algebra 1, College Algebra | Strong intent; already covered by subtitle, so use keyword space elsewhere |
| `calculus practice` | Dogl Calculus, Khan, Brilliant, AP Calculus apps | Add AP/SAT/ACT/precalculus only if we support the promise visibly |
| `math exam prep` | ALEKS, TSI, ACT, Math Zen, GRE | Exam-specific terms convert, but require screenshot/copy support |
| `math tutor` | Khan, Math Tutor DVD, StudyPug, Studdy, Photomath | "Tutor" has intent, but users may expect live/AI help |
| `fractions practice` | fraction drills, visual fraction apps, grade apps | Good lower-competition wedge for foundations |

Apple App Store competitor examples:

- Brilliant positions around math/coding tutoring, personalization, and interactive understanding, with 30K ratings at 4.7.
- Photomath owns scan/solve/step-by-step homework behavior, with 733K ratings at 4.8.
- Khan Academy owns free broad learning and practice, with 100K+ ratings.
- IXL owns K-12 curriculum breadth and parent/teacher trust, with 197K ratings.
- Math Zen is a small but very close positioning competitor around exam prep and drill.

### German Store

Observed App Store search samples:

| Query | Top visible pattern | Implication for Mathio |
| --- | --- | --- |
| `mathe lernen` | ANTON, Studyflix, MatheWiki, Knowunity, Kopfrechnen apps | Broad, high volume, high competition |
| `mathe üben` | FastMath, ANTON, Studyflix, MatheWiki, König der Mathematik | "üben" and "Kopfrechnen" are important |
| `abitur mathe` | MatxMate, ANTON, sofatutor, SchulLV, StudySmarter | High-intent; needs Abitur-specific landing/screenshot |
| `bruchrechnen` | Bruchrechner, Bruch-Herausforderung, Photomath | Strong narrow wedge; Mathio has content fit |
| `analysis mathe` | CAS/solver apps and Mathway | Searcher often expects calculator/solver; handle carefully |
| `geometrie lernen` | geometry tools and quiz apps | Add only if screenshots show real geometry practice |

## Recommended Keyword Experiments

These should be tested in a new version after `1.0.10` review completes. Do not change metadata while the current version is waiting for review unless we intentionally cancel/resubmit.

### en-US Option A — Practice + Exam Breadth

Replace current keywords with:

```text
maths,mathe,trigonometry,fractions,equations,formulas,homework,exam,tutor,sat,act,stats,problems
```

Length: 96/100.

Why:

- Frees duplicated `algebra`, `calculus`, `geometry`.
- Adds `sat`, `act`, `stats`, `problems`.
- Combines with title/subtitle into phrases like `math problems`, `math tutor`, `math exam`, `algebra problems`, `calculus exam`, `geometry problems`, `math practice`.

Risk:

- `sat`/`act` need explicit support in screenshot/copy. Current description says SAT-style prep, but the app should expose this more clearly if we index it.

### en-US Option B — Safer Curriculum Depth

```text
maths,mathe,trigonometry,fractions,equations,formulas,homework,exam,tutor,precalculus,statistics,act
```

Length: 100/100.

Why:

- Less "test prep" heavy than Option A.
- Adds `precalculus` and `statistics`, both curriculum-aligned.

Risk:

- Misses `sat` and `problems`, which appear useful from search samples.

### de-DE Option A — Practice + Exam Intent

```text
üben,trigonometrie,bruchrechnen,gleichungen,formeln,abitur,klausur,kopfrechnen,prüfung,nachhilfe
```

Length: 96/100.

Why:

- Frees duplicated `mathe`, `algebra`, `analysis`, `geometrie`.
- Adds `kopfrechnen`, `prüfung`, `nachhilfe`.
- Combines with name/subtitle into `mathe üben`, `mathe abitur`, `mathe prüfung`, `algebra gleichungen`, `analysis klausur`.

Risk:

- `nachhilfe` may imply live tutoring. Use only if screenshots/description frame Mathio as "Mathe-Nachhilfe zum Üben" or "Nachhilfe-Ergänzung", not a live tutor.

### de-DE Option B — Safer Student Practice

```text
üben,bruchrechnen,gleichungen,formeln,abitur,klausur,kopfrechnen,prüfung,schule,textaufgaben
```

Length: 92/100.

Why:

- More honest for Mathio's current product.
- Adds `textaufgaben`, which fits exam practice and school pain.
- Avoids `nachhilfe` expectation mismatch.

## Recommended App Name / Subtitle Tests

Do not run all at once. Change one major metadata surface, observe App Analytics for at least 10-14 days.

### en-US

Current:

- Name: `Mathio: Math Practice`
- Subtitle: `Algebra, geometry & calculus`

Keep the name for now. It already gives the core term `math practice`.

Potential subtitle test:

```text
Algebra, calculus, exams
```

Pros: adds `exams`, focuses high-intent learners.
Cons: loses `geometry` from subtitle, though it can remain in description/screenshots.

Alternative:

```text
Algebra, SAT & calculus
```

Pros: targets US exam intent.
Cons: too narrow unless SAT-specific content is expanded and screenshoted.

### de-DE

Current:

- Name: `Mathio: Mathe lernen`
- Subtitle: `Algebra, Analysis & Geometrie`

Potential subtitle test:

```text
Algebra, Abi & Analysis
```

Pros: adds high-intent `Abi`.
Cons: loses `Geometrie` in subtitle.

Safer subtitle:

```text
Algebra, Analysis, Abi
```

Pros: direct and searchable.
Cons: a little less polished than current copy.

## Screenshot / Conversion Recommendations

Keyword changes only help if the product page proves the promise.

Next screenshot set should include:

1. "Practice math in 2 minutes" / "Mathe in 2 Minuten üben"
2. "Fix weak spots with reviews" / "Schwachstellen gezielt wiederholen"
3. "Algebra, geometry, calculus" / "Algebra, Geometrie, Analysis"
4. "Exam sprint mode" / "Prüfungs-Sprints"
5. "Step-by-step solutions" / "Schritt-für-Schritt-Lösungen"
6. "100 lessons, 500 questions" / "100 Lektionen, 500 Aufgaben"

If we add `sat`, `act`, or `abitur`, one screenshot must explicitly show exam prep. Otherwise impressions may rise but conversion can fall.

## Product/Growth Roadmap for Better Retention Users

Priority order:

1. Add visible "Exam Prep" lanes:
   - SAT Math Basics
   - ACT Math Basics
   - Abitur Mathe Grundlagen
   - Klausur Sprint
2. Add topic-specific landing copy inside onboarding:
   - "I need homework help"
   - "I am preparing for an exam"
   - "I forgot the basics"
   - "I want daily practice"
3. Add App Store review prompt only after a value moment:
   - after 5 correct answers in one session
   - after first completed lesson
   - after first review streak
4. Add shareable progress card:
   - "I finished 7 days of Mathio"
   - "I mastered 20 algebra questions"
5. Build a small web landing page for each cluster:
   - `/math-practice`
   - `/algebra-practice`
   - `/abitur-mathe`
   - `/fractions-practice`
   - `/sat-math-practice`

## Apple Search Ads Starter Plan

Use this only after the next metadata experiment or while `1.0.10` is live.

Campaign structure:

1. Brand exact:
   - `mathio`
2. Generic exact, US:
   - `math practice`
   - `algebra practice`
   - `fractions practice`
   - `calculus practice`
   - `math exam prep`
   - `mental math`
   - `math problems`
3. Generic exact, DE:
   - `mathe lernen`
   - `mathe üben`
   - `bruchrechnen`
   - `abitur mathe`
   - `kopfrechnen`
   - `mathe klausur`
   - `textaufgaben mathe`
4. Discovery:
   - Search Match on
   - Broad match on the above core terms
   - Add exact generic keywords as negatives to avoid overlap

Apple's own Apple Ads guidance says Search Match can use App Store metadata and similar-app data for matching, and recommends using Search Match in a dedicated discovery campaign. Apple's match-type docs also distinguish broad reach from exact-match control, which maps well to this setup.

## Sources Checked

- App Store Connect metadata pull for Mathio `1.0.10`, 2026-06-02.
- Apple iTunes Search API samples for US and DE stores, 2026-06-02.
- Apple App Store Connect reference: name and subtitle limits.
- Apple Ads keyword best practices and match-type docs.
- App Store listings for Brilliant, Photomath, Khan Academy, IXL, Symbolab, and Math Zen.

