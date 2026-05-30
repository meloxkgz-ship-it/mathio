import XCTest
@testable import Mathio

final class StoreRetentionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        clearMathioDefaults()
    }

    override func tearDown() {
        clearMathioDefaults()
        super.tearDown()
    }

    func testReviewPlanShowsTomorrowAfterFirstCorrectPass() {
        let store = Store()
        let lesson = Curriculum.linearEquations

        lesson.questions.prefix(3).forEach { question in
            store.record(questionId: question.id, correct: true)
        }

        let plan = store.reviewPlan(for: lesson, now: .now)

        XCTAssertEqual(plan.tomorrow, 3)
        XCTAssertEqual(plan.week, 3)
    }

    func testReviewPlanIgnoresFreshMissesBecauseTheyAreDueNow() {
        let store = Store()
        let lesson = Curriculum.linearEquations
        let question = lesson.questions[0]

        store.record(questionId: question.id, correct: false)

        let plan = store.reviewPlan(for: lesson, now: .now)

        XCTAssertEqual(plan.tomorrow, 0)
        XCTAssertEqual(plan.week, 0)
    }

    func testReviewPlanMovesQuestionsOutOfTomorrowAfterRepeatedCorrectAnswers() {
        let store = Store()
        let lesson = Curriculum.linearEquations
        let question = lesson.questions[0]

        store.record(questionId: question.id, correct: true)
        store.record(questionId: question.id, correct: true)
        store.record(questionId: question.id, correct: true)

        let plan = store.reviewPlan(for: lesson, now: .now)

        XCTAssertEqual(plan.tomorrow, 0)
        XCTAssertEqual(plan.week, 1)
    }

    private func clearMathioDefaults() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("mathio.") {
            defaults.removeObject(forKey: key)
        }
    }
}
