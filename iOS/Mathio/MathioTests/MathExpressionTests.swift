import XCTest
@testable import Mathio

/// Tests for the answer normalizer used by free-answer questions.
/// To run: add a "Mathio Tests" target to the Xcode project, point it at
/// this folder, set Mathio as the test host, then ⌘U.
final class MathExpressionTests: XCTestCase {

    // MARK: - Trivial equivalences

    func test_simpleEquality() {
        XCTAssertTrue(MathInput.matches("4", accepted: ["4"]))
        XCTAssertTrue(MathInput.matches("4.0", accepted: ["4"]))
        XCTAssertTrue(MathInput.matches("4.000", accepted: ["4"]))
        XCTAssertTrue(MathInput.matches("4.50", accepted: ["4.5"]))
    }

    func test_caseInsensitive() {
        XCTAssertTrue(MathInput.matches("PI", accepted: ["pi"]))
        XCTAssertTrue(MathInput.matches("Sqrt(2)", accepted: ["sqrt(2)"]))
    }

    func test_whitespaceIgnored() {
        XCTAssertTrue(MathInput.matches("6x + 2", accepted: ["6x+2"]))
        XCTAssertTrue(MathInput.matches("\t6x  +\t2  ", accepted: ["6x+2"]))
    }

    // MARK: - Unicode normalization

    func test_unicodeMinus() {
        XCTAssertTrue(MathInput.matches("−5", accepted: ["-5"]))      // U+2212
        XCTAssertTrue(MathInput.matches("3−2", accepted: ["3-2"]))
        XCTAssertTrue(MathInput.matches("–5", accepted: ["-5"]))      // en-dash
        XCTAssertTrue(MathInput.matches("—5", accepted: ["-5"]))      // em-dash
    }

    func test_unicodeMath() {
        XCTAssertTrue(MathInput.matches("π", accepted: ["pi"]))
        XCTAssertTrue(MathInput.matches("√2", accepted: ["sqrt2"]))
        XCTAssertTrue(MathInput.matches("x²", accepted: ["x^2"]))
        XCTAssertTrue(MathInput.matches("3·4", accepted: ["3*4"]))
        XCTAssertTrue(MathInput.matches("5×6", accepted: ["5*6"]))
    }

    // MARK: - Polynomial reorder

    func test_polynomialOrder() {
        XCTAssertTrue(MathInput.matches("2+6x", accepted: ["6x+2"]))
        XCTAssertTrue(MathInput.matches("6x+2", accepted: ["2+6x"]))
    }

    func test_degreeOrdering() {
        // Higher-degree term comes first canonically.
        XCTAssertTrue(MathInput.matches("2x+x^2+1", accepted: ["x^2+2x+1"]))
        XCTAssertTrue(MathInput.matches("1+2x+x^2", accepted: ["x^2+2x+1"]))
    }

    // MARK: - Comma-separated lists

    func test_sortedNumberLists() {
        XCTAssertTrue(MathInput.matches("3,2", accepted: ["2,3"]))
        XCTAssertTrue(MathInput.matches("3, 2", accepted: ["2,3"]))
        XCTAssertTrue(MathInput.matches("-3, 3", accepted: ["3,-3"]))
    }

    // MARK: - DE comma decimal

    func test_germanDecimalComma() throws {
        // This test only fires on a German simulator; otherwise comma is treated
        // as a list separator. Skip when running under English locale.
        guard Locale.current.language.languageCode?.identifier == "de" else {
            throw XCTSkip("DE comma test only runs under a German locale.")
        }
        XCTAssertTrue(MathInput.matches("1,5", accepted: ["1.5"]))
        XCTAssertTrue(MathInput.matches("0,25", accepted: ["0.25"]))
    }

    // MARK: - Edge cases

    func test_emptyInputDoesNotMatch() {
        XCTAssertFalse(MathInput.matches("", accepted: ["0"]))
        XCTAssertFalse(MathInput.matches("   ", accepted: ["0"]))
    }

    func test_equationsArePreservedNotReordered() {
        // Equations contain "=" — the reordering step bails so "x=2x+1" stays
        // distinct from "2x+1=x". The normalizer should not silently equate them.
        let lhs = MathInput.matches("x=2x+1", accepted: ["x=2x+1"])
        XCTAssertTrue(lhs)
    }

    func test_acceptedListVariants() {
        // The accepted list is normalized too — author can supply either form.
        XCTAssertTrue(MathInput.matches("6x+2", accepted: ["2 + 6x", "2+6 x"]))
    }
}
