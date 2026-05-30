import Foundation
import SwiftUI

// MARK: - Domain types
//
// `LocalizedStringResource` doesn't conform to `Hashable`, so we hash these
// structs by their stable id (or, for Formula, by an authored key string).

struct Topic: Identifiable, Hashable {
    let id: String
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let icon: String          // SF Symbol
    let color: Color
    let lessons: [Lesson]

    static func == (lhs: Topic, rhs: Topic) -> Bool { lhs.id == rhs.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct Lesson: Identifiable, Hashable {
    let id: String
    let title: LocalizedStringResource
    let intro: LocalizedStringResource
    let visual: LessonVisual?
    let formulas: [Formula]
    let questions: [Question]

    init(id: String,
         title: LocalizedStringResource,
         intro: LocalizedStringResource,
         visual: LessonVisual? = nil,
         formulas: [Formula],
         questions: [Question]) {
        self.id = id
        self.title = title
        self.intro = intro
        self.visual = visual
        self.formulas = formulas
        self.questions = questions
    }

    static func == (lhs: Lesson, rhs: Lesson) -> Bool { lhs.id == rhs.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum LessonVisual: String, Hashable {
    case numberLine
    case triangle
    case parabola
    case derivativeSlope
    case unitCircle
    case barChart
    case vectorPlane
    case compoundGrowth
}

struct Formula: Hashable, Identifiable {
    let key: String
    let name: LocalizedStringResource
    let math: String                  // MathText syntax
    let explanation: LocalizedStringResource

    var id: String { key }
    static func == (lhs: Formula, rhs: Formula) -> Bool { lhs.key == rhs.key }
    func hash(into h: inout Hasher) { h.combine(key) }
}

struct Question: Identifiable, Hashable {
    let id: String
    let prompt: LocalizedStringResource
    let math: String?
    let kind: Kind
    let hint: LocalizedStringResource
    let solutionSteps: [LocalizedStringResource]

    static func == (lhs: Question, rhs: Question) -> Bool { lhs.id == rhs.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    enum Kind {
        case multipleChoice(options: [Choice], correctIndex: Int)
        case freeAnswer(accepted: [String])
        case trueFalse(answer: Bool)
    }

    struct Choice {
        let label: LocalizedStringResource
        let math: String?
    }
}

enum LearningGoal: String, Codable, CaseIterable, Identifiable {
    case school
    case exam
    case selfStudy
    case university
    case money

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .school: "School support"
        case .exam: "Exam prep"
        case .selfStudy: "Self-study"
        case .university: "University basics"
        case .money: "Everyday money math"
        }
    }

    var subtitle: LocalizedStringResource {
        switch self {
        case .school: "Homework, tests, and steady confidence"
        case .exam: "Focused practice for an upcoming test"
        case .selfStudy: "Rebuild foundations without pressure"
        case .university: "Refresh algebra, calculus, and statistics"
        case .money: "Percentages, interest, loans, and budgets"
        }
    }

    var icon: String {
        switch self {
        case .school: "graduationcap.fill"
        case .exam: "checklist.checked"
        case .selfStudy: "person.fill.checkmark"
        case .university: "function"
        case .money: "banknote.fill"
        }
    }
}

enum DiagnosticLevel: String, Codable {
    case starter
    case steady
    case advanced

    var title: LocalizedStringResource {
        switch self {
        case .starter: "Foundation reset"
        case .steady: "Steady builder"
        case .advanced: "Advanced push"
        }
    }

    var subtitle: LocalizedStringResource {
        switch self {
        case .starter: "Start with core skills and short wins."
        case .steady: "Mix new lessons with review to keep momentum."
        case .advanced: "Move faster into algebra, calculus, and stats."
        }
    }
}

struct LearningProfile: Codable, Equatable {
    var goal: LearningGoal
    var confidence: Int
    var diagnosticCorrect: Int
    var diagnosticTotal: Int
    var createdAt: Date

    var level: DiagnosticLevel {
        guard diagnosticTotal > 0 else { return confidence >= 4 ? .advanced : .starter }
        let ratio = Double(diagnosticCorrect) / Double(diagnosticTotal)
        if ratio >= 0.75 || confidence >= 5 { return .advanced }
        if ratio >= 0.45 || confidence >= 3 { return .steady }
        return .starter
    }
}

// MARK: - Persisted progress
//
// A single source of truth: per-question history. Everything else (streak,
// mastery %, daily goal, review queue) is derived. Storage = UserDefaults.

struct AnsweredEntry: Codable, Hashable {
    var attempts: Int
    var correct: Int
    var lastAt: Date            // most recent attempt
    var lastCorrect: Date?      // most recent correct attempt (nil if never)
    var streakCorrect: Int      // consecutive correct attempts; resets on a wrong answer

    /// Was the most recent attempt correct? (Heuristic — `lastCorrect == lastAt`.)
    var isMastered: Bool {
        guard let lc = lastCorrect else { return false }
        return abs(lc.timeIntervalSince(lastAt)) < 1
    }

    /// Spaced-repetition interval for the next review based on the correct streak.
    /// Leitner-box style — proven, simple, no FSRS dependency needed.
    var nextReviewInterval: TimeInterval {
        switch streakCorrect {
        case 0:  return 0                              // wrong last time → drill now
        case 1:  return 60 * 60 * 24 * 1               // 1 day
        case 2:  return 60 * 60 * 24 * 3               // 3 days
        case 3:  return 60 * 60 * 24 * 7               // 1 week
        case 4:  return 60 * 60 * 24 * 14              // 2 weeks
        default: return 60 * 60 * 24 * 30              // 1 month
        }
    }

    var nextReviewAt: Date {
        (lastCorrect ?? lastAt).addingTimeInterval(nextReviewInterval)
    }

    func isDueForReview(asOf now: Date = .now) -> Bool {
        if !isMastered { return true }      // always re-drill recent misses
        return now >= nextReviewAt
    }
}

// MARK: - Settings (persisted)

@Observable
final class UserSettings {
    private let defaults = UserDefaults.standard
    private let kDailyGoal     = "mathio.dailyGoal"
    private let kNotifications = "mathio.notifications.enabled"
    private let kReminderHour  = "mathio.notifications.hour"
    private let kTheme         = "mathio.theme"

    enum Theme: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var preferredColorScheme: ColorScheme? {
            switch self { case .system: nil; case .light: .light; case .dark: .dark }
        }
        var label: LocalizedStringResource {
            switch self { case .system: "System"; case .light: "Light"; case .dark: "Dark" }
        }
    }

    var dailyGoal: Int {
        didSet { defaults.set(dailyGoal, forKey: kDailyGoal) }
    }
    var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: kNotifications) }
    }
    var reminderHour: Int {
        didSet { defaults.set(reminderHour, forKey: kReminderHour) }
    }
    var theme: Theme {
        didSet { defaults.set(theme.rawValue, forKey: kTheme) }
    }

    init() {
        let storedGoal = defaults.integer(forKey: kDailyGoal)
        let storedReminderHour = defaults.object(forKey: kReminderHour) as? Int
        self.dailyGoal = storedGoal == 0 ? 5 : storedGoal
        self.notificationsEnabled = defaults.bool(forKey: kNotifications)
        self.reminderHour = storedReminderHour ?? 19
        self.theme = Theme(rawValue: defaults.string(forKey: kTheme) ?? "") ?? .system
    }
}

// MARK: - Store

@Observable
final class Store {
    private let defaults = UserDefaults.standard
    private let kAnswered      = "mathio.answered.v2"
    private let kStreakDay     = "mathio.streak.last"
    private let kStreakCount   = "mathio.streak.count"
    private let kOnboarded     = "mathio.onboarded"
    private let kBookmarks     = "mathio.bookmarks"
    private let kFreezes       = "mathio.streak.freezes"
    private let kFreezeRefill  = "mathio.streak.freezeRefillDate"
    private let kDailyCorrect  = "mathio.dailyCorrect.v1"
    private let kLearningProfile = "mathio.learningProfile.v1"

    static let maxFreezes = 2

    private(set) var answered: [String: AnsweredEntry] = [:]
    private(set) var streakDays: Int = 0
    private(set) var bookmarks: Set<String> = []
    private(set) var dailyCorrect: [String: Int] = [:]
    private(set) var learningProfile: LearningProfile?
    /// Available "streak freezes" — auto-spent if a day is missed. Refills weekly.
    private(set) var streakFreezes: Int = 2
    var hasOnboarded: Bool

    init() {
        self.hasOnboarded = defaults.bool(forKey: kOnboarded)

        if let data = defaults.data(forKey: kAnswered),
           let decoded = try? JSONDecoder().decode([String: AnsweredEntry].self, from: data) {
            self.answered = decoded
        }
        self.streakDays = defaults.integer(forKey: kStreakCount)
        if let bm = defaults.array(forKey: kBookmarks) as? [String] {
            self.bookmarks = Set(bm)
        }
        if let data = defaults.data(forKey: kDailyCorrect),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            self.dailyCorrect = decoded
        }
        if let data = defaults.data(forKey: kLearningProfile),
           let decoded = try? JSONDecoder().decode(LearningProfile.self, from: data) {
            self.learningProfile = decoded
        }
        // Default freezes if never set (defaults.integer returns 0 for unset).
        if defaults.object(forKey: kFreezes) == nil {
            self.streakFreezes = Self.maxFreezes
            defaults.set(self.streakFreezes, forKey: kFreezes)
        } else {
            self.streakFreezes = defaults.integer(forKey: kFreezes)
        }
        refillFreezesIfDue()
        bumpStreakIfNeeded()
    }

    // MARK: Recording

    func record(questionId: String, correct: Bool) {
        var entry = answered[questionId] ?? AnsweredEntry(
            attempts: 0, correct: 0, lastAt: .now,
            lastCorrect: nil, streakCorrect: 0
        )
        entry.attempts += 1
        entry.lastAt = .now
        if correct {
            entry.correct += 1
            entry.lastCorrect = .now
            entry.streakCorrect += 1
            dailyCorrect[Self.dayKey(for: .now), default: 0] += 1
        } else {
            entry.streakCorrect = 0
        }
        answered[questionId] = entry
        bumpStreakIfNeeded(touch: true)
        persistAnswered()
        persistDailyCorrect()
    }

    func completeOnboarding() {
        hasOnboarded = true
        defaults.set(true, forKey: kOnboarded)
    }

    func saveLearningProfile(goal: LearningGoal, confidence: Int,
                             diagnosticCorrect: Int, diagnosticTotal: Int) {
        learningProfile = LearningProfile(
            goal: goal,
            confidence: confidence,
            diagnosticCorrect: diagnosticCorrect,
            diagnosticTotal: diagnosticTotal,
            createdAt: .now
        )
        persistLearningProfile()
    }

    /// Wipe all answer history + streak. Onboarding flag is preserved.
    func reset() {
        answered = [:]
        streakDays = 0
        streakFreezes = Self.maxFreezes
        dailyCorrect = [:]
        defaults.removeObject(forKey: kAnswered)
        defaults.removeObject(forKey: kStreakCount)
        defaults.removeObject(forKey: kStreakDay)
        defaults.removeObject(forKey: kDailyCorrect)
        defaults.set(Self.maxFreezes, forKey: kFreezes)
        defaults.removeObject(forKey: kFreezeRefill)
    }

    // MARK: Bookmarks (formula reference)

    func toggleBookmark(_ key: String) {
        if bookmarks.contains(key) { bookmarks.remove(key) }
        else                       { bookmarks.insert(key) }
        defaults.set(Array(bookmarks), forKey: kBookmarks)
    }

    func isBookmarked(_ key: String) -> Bool { bookmarks.contains(key) }

    // MARK: Mastery (unified definition)
    //
    // A question is mastered if its most recent attempt was correct AND its
    // correct streak ≥ 1. This makes both topic and lesson mastery a simple
    // average of mastered booleans across questions.

    private func masteryScore(for question: Question) -> Double {
        guard let e = answered[question.id], e.attempts > 0 else { return 0 }
        return e.isMastered ? 1.0 : 0.0
    }

    func mastery(for lesson: Lesson) -> Double {
        guard !lesson.questions.isEmpty else { return 0 }
        let total = lesson.questions.reduce(0.0) { $0 + masteryScore(for: $1) }
        return total / Double(lesson.questions.count)
    }

    func mastery(for topic: Topic) -> Double {
        let qs = topic.lessons.flatMap(\.questions)
        guard !qs.isEmpty else { return 0 }
        let total = qs.reduce(0.0) { $0 + masteryScore(for: $1) }
        return total / Double(qs.count)
    }

    // MARK: Adaptive next-up

    /// Lowest-mastery, accessible lesson. For free users, prefers free lessons
    /// (first per topic). Returns nil if everything is fully mastered.
    func nextLesson(in topics: [Topic], premium: Bool) -> (Topic, Lesson)? {
        // Build a list of (topic, lesson, mastery, free)
        let candidates: [(Topic, Lesson, Double, Bool)] = topics.flatMap { topic in
            topic.lessons.enumerated().map { idx, lesson in
                (topic, lesson, mastery(for: lesson), idx == 0)
            }
        }
        let unfinished = candidates.filter { $0.2 < 1.0 }
        guard !unfinished.isEmpty else { return nil }

        let pool: [(Topic, Lesson, Double, Bool)]
        if premium {
            pool = unfinished
        } else {
            // Prefer free, fall back to whatever's lowest if all free are done.
            let free = unfinished.filter(\.3)
            pool = free.isEmpty ? unfinished : free
        }
        let best = pool.min { $0.2 < $1.2 }!
        return (best.0, best.1)
    }

    // MARK: Spaced-repetition review queue

    /// Questions whose next-review interval has elapsed AND that have been
    /// attempted at least once. New (never-attempted) questions are NOT in
    /// this queue — they belong to the lesson flow.
    func reviewQueue(in topics: [Topic], limit: Int = 10) -> [Question] {
        let all = topics.flatMap { $0.lessons.flatMap(\.questions) }
        let now = Date.now
        return all.compactMap { q -> (Question, Date)? in
            guard let entry = answered[q.id], entry.attempts > 0,
                  entry.isDueForReview(asOf: now) else { return nil }
            return (q, entry.nextReviewAt)
        }
        .sorted { $0.1 < $1.1 }   // oldest-due first
        .prefix(limit)
        .map(\.0)
    }

    // MARK: Daily goal progress

    /// Number of correct answers today.
    func correctToday() -> Int {
        dailyCorrect[Self.dayKey(for: .now), default: 0]
    }

    /// Daily activity histogram for the heatmap. Counts the number of
    /// correct answers completed on each day.
    func dailyActivity() -> [Date: Int] {
        dailyCorrect.reduce(into: [:]) { result, item in
            guard let date = Self.dayDate(from: item.key) else { return }
            result[date] = item.value
        }
    }

    // MARK: Streak (with freeze)

    /// Refill one freeze every 7 days, up to the cap.
    private func refillFreezesIfDue() {
        let cal = Calendar.current
        let now = Date.now
        let last = defaults.object(forKey: kFreezeRefill) as? Date
            ?? cal.date(byAdding: .day, value: -7, to: now)!
        guard let days = cal.dateComponents([.day], from: last, to: now).day,
              days >= 7 else { return }
        let toAdd = days / 7
        streakFreezes = min(Self.maxFreezes, streakFreezes + toAdd)
        defaults.set(streakFreezes, forKey: kFreezes)
        defaults.set(now, forKey: kFreezeRefill)
    }

    private func bumpStreakIfNeeded(touch: Bool = false) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let last = defaults.object(forKey: kStreakDay) as? Date

        if touch {
            if let last, cal.isDate(last, inSameDayAs: today) { return }
            if let last, let daysGap = cal.dateComponents([.day], from: last, to: today).day {
                if daysGap == 1 {
                    streakDays += 1
                } else if daysGap >= 2, daysGap - 1 <= streakFreezes {
                    // Spend one freeze per missed day to bridge the gap.
                    let used = daysGap - 1
                    streakFreezes -= used
                    streakDays += 1
                    defaults.set(streakFreezes, forKey: kFreezes)
                } else {
                    streakDays = 1
                }
            } else {
                streakDays = 1
            }
            defaults.set(streakDays, forKey: kStreakCount)
            defaults.set(today, forKey: kStreakDay)
        } else {
            // On launch: clear streak only if the gap exceeds available freezes.
            guard let last,
                  let daysGap = cal.dateComponents([.day], from: last, to: today).day else { return }
            if daysGap > 1 + streakFreezes {
                streakDays = 0
                defaults.set(0, forKey: kStreakCount)
            }
        }
    }

    // MARK: Persistence

    private func persistAnswered() {
        if let data = try? JSONEncoder().encode(answered) {
            defaults.set(data, forKey: kAnswered)
        }
    }

    private func persistDailyCorrect() {
        if let data = try? JSONEncoder().encode(dailyCorrect) {
            defaults.set(data, forKey: kDailyCorrect)
        }
    }

    private func persistLearningProfile() {
        if let data = try? JSONEncoder().encode(learningProfile) {
            defaults.set(data, forKey: kLearningProfile)
        }
    }

    private static func dayKey(for date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func dayDate(from key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        guard let date = Calendar.current.date(from: components) else { return nil }
        return Calendar.current.startOfDay(for: date)
    }
}
