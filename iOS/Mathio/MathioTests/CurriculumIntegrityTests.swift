import XCTest
@testable import Mathio

final class CurriculumIntegrityTests: XCTestCase {

    func testCurriculumMatchesPremiumRoadmapPromise() {
        let lessonCount = Curriculum.topics.reduce(0) { $0 + $1.lessons.count }
        let questionCount = Curriculum.topics.reduce(0) { $0 + $1.questionCount }

        XCTAssertEqual(lessonCount, 95)
        XCTAssertEqual(questionCount, 475)
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
        XCTAssertEqual(topic?.lessons.count, 6)
        XCTAssertEqual(topic?.questionCount, 30)
        XCTAssertEqual(topic?.lessons.map(\.id), [
            "exam.mixed.foundations",
            "exam.algebra.sprint",
            "exam.geometry.sprint",
            "exam.data.sprint",
            "exam.word.sprint",
            "exam.strategy.sprint",
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
}
