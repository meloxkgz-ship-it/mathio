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
    let formulas: [Formula]
    let questions: [Question]

    static func == (lhs: Lesson, rhs: Lesson) -> Bool { lhs.id == rhs.id }
    func hash(into h: inout Hasher) { h.combine(id) }
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
    var theme: Theme {
        didSet { defaults.set(theme.rawValue, forKey: kTheme) }
    }

    init() {
        let storedGoal = defaults.integer(forKey: kDailyGoal)
        self.dailyGoal = storedGoal == 0 ? 5 : storedGoal
        self.notificationsEnabled = defaults.bool(forKey: kNotifications)
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

    static let maxFreezes = 2

    private(set) var answered: [String: AnsweredEntry] = [:]
    private(set) var streakDays: Int = 0
    private(set) var bookmarks: Set<String> = []
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
        } else {
            entry.streakCorrect = 0
        }
        answered[questionId] = entry
        bumpStreakIfNeeded(touch: true)
        persistAnswered()
    }

    func completeOnboarding() {
        hasOnboarded = true
        defaults.set(true, forKey: kOnboarded)
    }

    /// Wipe all answer history + streak. Onboarding flag is preserved.
    func reset() {
        answered = [:]
        streakDays = 0
        streakFreezes = Self.maxFreezes
        defaults.removeObject(forKey: kAnswered)
        defaults.removeObject(forKey: kStreakCount)
        defaults.removeObject(forKey: kStreakDay)
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
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return answered.values.filter { entry in
            guard let lc = entry.lastCorrect else { return false }
            return cal.isDate(lc, inSameDayAs: today)
        }.count
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
}
