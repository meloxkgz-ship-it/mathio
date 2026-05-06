# Mathio Tests

XCTest suite for the answer normalizer.

The project ships without a test target wired up — adding one via `pbxproj`
surgery is risky to do automatically. To enable the tests:

1. Open `Mathio.xcodeproj` in Xcode.
2. **File → New → Target… → iOS → Unit Testing Bundle**.
3. Name it `MathioTests`, target Mathio.
4. Drag `MathExpressionTests.swift` from this folder into the new test target's
   Sources build phase.
5. **⌘U** to run.

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
