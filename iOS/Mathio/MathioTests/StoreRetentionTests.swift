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

    func testWeeklyStudyPlanCombinesTodaysMissesAndTomorrowReviews() {
        let store = Store()
        let topics = [Curriculum.topics[1]]
        let lesson = Curriculum.linearEquations

        store.record(questionId: lesson.questions[0].id, correct: false)
        store.record(questionId: lesson.questions[1].id, correct: true)

        let plan = store.weeklyStudyPlan(
            in: topics,
            focusLessons: [lesson, Curriculum.quadratics],
            dailyGoal: 5,
            now: .now
        )

        XCTAssertEqual(plan.count, 7)
        XCTAssertEqual(plan[0].reviewCount, 1)
        XCTAssertEqual(plan[0].lesson?.id, lesson.id)
        XCTAssertEqual(plan[0].targetQuestions, 5)
        XCTAssertEqual(plan[1].reviewCount, 1)
        XCTAssertEqual(plan[1].lesson?.id, Curriculum.quadratics.id)
    }

    private func clearMathioDefaults() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("mathio.") {
            defaults.removeObject(forKey: key)
        }
    }
}
