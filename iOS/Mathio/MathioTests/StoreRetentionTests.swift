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

    func testLearningProfileSetsRealisticWeeklyHabitTargets() {
        let createdAt = Date(timeIntervalSince1970: 0)

        let starter = LearningProfile(
            goal: .selfStudy,
            confidence: 1,
            diagnosticCorrect: 0,
            diagnosticTotal: 4,
            createdAt: createdAt
        )
        let steadyExam = LearningProfile(
            goal: .exam,
            confidence: 3,
            diagnosticCorrect: 2,
            diagnosticTotal: 4,
            createdAt: createdAt
        )
        let advancedUniversity = LearningProfile(
            goal: .university,
            confidence: 5,
            diagnosticCorrect: 4,
            diagnosticTotal: 4,
            createdAt: createdAt
        )

        XCTAssertEqual(starter.weeklyHabitTargetDays, 3)
        XCTAssertEqual(steadyExam.weeklyHabitTargetDays, 4)
        XCTAssertEqual(advancedUniversity.weeklyHabitTargetDays, 5)
    }

    func testSessionSummaryPersistsForNextLaunch() {
        let store = Store()
        let lesson = Curriculum.linearEquations

        lesson.questions.prefix(4).forEach { question in
            store.record(questionId: question.id, correct: true)
        }
        store.recordSessionCompletion(
            lesson: lesson,
            mode: "Lesson",
            correct: 4,
            total: 5,
            missed: 1,
            nextLessonTitle: "Quadratics"
        )

        let relaunched = Store()

        XCTAssertEqual(relaunched.lastSession?.lessonTitle, String(localized: lesson.title))
        XCTAssertEqual(relaunched.lastSession?.accuracy, 80)
        XCTAssertEqual(relaunched.lastSession?.nextReviewCount, 4)
        XCTAssertEqual(relaunched.lastSession?.nextLessonTitle, "Quadratics")
    }

    func testResetClearsSessionSummary() {
        let store = Store()
        let lesson = Curriculum.linearEquations

        store.recordSessionCompletion(
            lesson: lesson,
            mode: "Lesson",
            correct: 1,
            total: 5,
            missed: 4,
            nextLessonTitle: nil
        )
        store.reset()

        XCTAssertNil(Store().lastSession)
    }

    func testReviewPromptAppearsAfterFirstPerfectValueMoment() {
        let store = Store()
        let lesson = Curriculum.linearEquations

        lesson.questions.prefix(5).forEach { question in
            store.record(questionId: question.id, correct: true)
        }

        XCTAssertTrue(ReviewPromptGate.shouldOfferAfterCompletion(
            store: store,
            sessionCorrect: 5,
            questionCount: 5,
            dailyGoal: 5,
            isReview: false,
            alreadyPromptedVersion: nil,
            currentVersion: "test"
        ))
    }

    func testReviewPromptWaitsForStrongValueMoment() {
        let store = Store()
        let lesson = Curriculum.linearEquations

        lesson.questions.prefix(5).enumerated().forEach { index, question in
            store.record(questionId: question.id, correct: index < 3)
        }

        XCTAssertFalse(ReviewPromptGate.shouldOfferAfterCompletion(
            store: store,
            sessionCorrect: 3,
            questionCount: 5,
            dailyGoal: 5,
            isReview: false,
            alreadyPromptedVersion: nil,
            currentVersion: "test"
        ))
    }

    func testReviewPromptOnlyAppearsOncePerVersion() {
        let store = Store()
        let lesson = Curriculum.linearEquations

        lesson.questions.prefix(5).forEach { question in
            store.record(questionId: question.id, correct: true)
        }

        XCTAssertFalse(ReviewPromptGate.shouldOfferAfterCompletion(
            store: store,
            sessionCorrect: 5,
            questionCount: 5,
            dailyGoal: 5,
            isReview: false,
            alreadyPromptedVersion: "test",
            currentVersion: "test"
        ))
    }

    private func clearMathioDefaults() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("mathio.") {
            defaults.removeObject(forKey: key)
        }
    }
}
