# Mathio Tests

XCTest suite for answer normalization and retention logic.

Run from the repository root:

```sh
xcodebuild test -scheme Mathio -project iOS/Mathio/Mathio.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17'
```

The test cases are real:

| Suite | What's covered |
|---|---|
| `simpleEquality` | "4" / "4.0" / "4.50" all match canonically |
| `caseInsensitive` | `PI` matches `pi` |
| `whitespaceIgnored` | Spaces and tabs |
| `unicodeMinus` | `−`, `–`, `—` → ASCII hyphen |
| `unicodeMath` | `π`, `√`, `²`, `·`, `×` |
| `polynomialOrder` | `2+6x` ↔ `6x+2` |
| `degreeOrdering` | `1+2x+x^2` → `x^2+2x+1` |
| `sortedNumberLists` | `3,2` matches `2,3` |
| `germanDecimalComma` | `1,5` → `1.5` (DE locale only) |
| `emptyInputDoesNotMatch` | Empty / whitespace input rejected |
| `equationsArePreservedNotReordered` | Equations not reordered around `=` |
| `acceptedListVariants` | The `accepted: [String]` list is normalized too |
| `reviewPlan` | Completion memory plan counts tomorrow/week review timing |
| `sessionSummary` | Last completed session persists for Home coach continuity and clears on reset |
| `curriculumIntegrity` | Roadmap counts, unique IDs, 5-question lessons, and Exam Review path coverage |
