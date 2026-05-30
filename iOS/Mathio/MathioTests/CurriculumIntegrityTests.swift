import XCTest
@testable import Mathio

final class CurriculumIntegrityTests: XCTestCase {

    func testCurriculumMatchesPremiumRoadmapPromise() {
        let lessonCount = Curriculum.topics.reduce(0) { $0 + $1.lessons.count }
        let questionCount = Curriculum.topics.reduce(0) { $0 + $1.questionCount }

        XCTAssertEqual(lessonCount, 100)
        XCTAssertEqual(questionCount, 500)
    }

    func testCurriculumIdsAreUnique() {
        let lessonIDs = Curriculum.topics.flatMap { $0.lessons.map(\.id) }
        let questionIDs = Curriculum.topics.flatMap { $0.lessons.flatMap { $0.questions.map(\.id) } }
        let formulaIDs = Curriculum.topics.flatMap { $0.lessons.flatMap { $0.formulas.map(\.id) } }

        XCTAssertEqual(Set(Curriculum.topics.map(\.id)).count, Curriculum.topics.count)
        XCTAssertEqual(Set(lessonIDs).count, lessonIDs.count)
        XCTAssertEqual(Set(questionIDs).count, questionIDs.count)
        XCTAssertEqual(Set(formulaIDs).count, formulaIDs.count)
    }

    func testEveryAuthoredLessonHasFiveGuidedQuestions() {
        let shortLessons = Curriculum.topics.flatMap(\.lessons)
            .filter { $0.questions.count != 5 }
            .map(\.id)

        XCTAssertTrue(shortLessons.isEmpty, "Lessons with unexpected question counts: \(shortLessons.joined(separator: ", "))")
    }

    func testExamReviewTopicIsACompleteSprintBlock() {
        let topic = Curriculum.topics.first { $0.id == "examreview" }

        XCTAssertNotNil(topic)
        XCTAssertEqual(topic?.lessons.count, 11)
        XCTAssertEqual(topic?.questionCount, 55)
        XCTAssertEqual(topic?.lessons.map(\.id), [
            "exam.mixed.foundations",
            "exam.algebra.sprint",
            "exam.geometry.sprint",
            "exam.data.sprint",
            "exam.word.sprint",
            "exam.strategy.sprint",
            "exam.mental.sprint",
            "exam.errorcheck.sprint",
            "exam.timed.triage.sprint",
            "exam.formula.recall.sprint",
            "exam.calculator.check.sprint",
        ])
    }

    func testExamPathIncludesAllExamReviewLessons() {
        let path = LearningPath.defaultPaths.first { $0.id == "exam-essentials" }
        let examLessonIDs = Curriculum.topics
            .first { $0.id == "examreview" }?
            .lessons
            .map(\.id) ?? []
        let pathLessonIDs = Set(path?.lessons.map(\.id) ?? [])

        XCTAssertNotNil(path)
        XCTAssertEqual(path?.durationDays, 21)
        XCTAssertTrue(examLessonIDs.allSatisfy { pathLessonIDs.contains($0) })
    }

    func testLongTermLearningPathsCreateMultiMonthRetentionLoops() {
        let corePath = LearningPath.defaultPaths.first { $0.id == "core-mastery-90" }
        let examPath = LearningPath.defaultPaths.first { $0.id == "exam-prep-12-week" }
        let algebraPath = LearningPath.defaultPaths.first { $0.id == "algebra-exam-45" }
        let dataPath = LearningPath.defaultPaths.first { $0.id == "data-confidence-60" }
        let moneyPath = LearningPath.defaultPaths.first { $0.id == "money-confidence-30" }

        XCTAssertNotNil(corePath)
        XCTAssertNotNil(examPath)
        XCTAssertNotNil(algebraPath)
        XCTAssertNotNil(dataPath)
        XCTAssertNotNil(moneyPath)
        XCTAssertEqual(corePath?.durationDays, 90)
        XCTAssertEqual(examPath?.durationDays, 84)
        XCTAssertEqual(algebraPath?.durationDays, 45)
        XCTAssertEqual(dataPath?.durationDays, 60)
        XCTAssertEqual(moneyPath?.durationDays, 30)
        XCTAssertTrue((corePath?.lessons.count ?? 0) >= 25)
        XCTAssertTrue((examPath?.lessons.map(\.id) ?? []).contains("exam.errorcheck.sprint"))
        XCTAssertTrue((examPath?.lessons.map(\.id) ?? []).contains("exam.timed.triage.sprint"))
        XCTAssertTrue((examPath?.lessons.map(\.id) ?? []).contains("exam.formula.recall.sprint"))
        XCTAssertTrue((examPath?.lessons.map(\.id) ?? []).contains("exam.calculator.check.sprint"))
        XCTAssertTrue((algebraPath?.lessons.map(\.id) ?? []).contains("alg.model"))
        XCTAssertTrue((dataPath?.lessons.map(\.id) ?? []).contains("stats.hypothesis"))
        XCTAssertTrue((moneyPath?.lessons.map(\.id) ?? []).contains("fin.loans"))
    }
}
