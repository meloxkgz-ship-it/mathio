import Foundation

#if DEBUG
/// Populates the answered cache with realistic-looking practice history.
/// Activated by `MATHIO_SEED_ACTIVITY=1` env var; called once at app launch.
/// Stripped from release builds.
enum SeedActivity {
    static func runIfRequested(into store: Store) {
        guard ProcessInfo.processInfo.environment["MATHIO_SEED_ACTIVITY"] == "1" else { return }
        let cal = Calendar.current
        let now = Date.now

        // Mark a healthy slice of questions as mastered across days. The
        // distribution is back-loaded so the heatmap shows recent intensity
        // and the streak feels earned.
        let questions = Curriculum.topics.flatMap { $0.lessons.flatMap(\.questions) }

        // Days back, count of question IDs to "answer" on that day.
        let plan: [(daysBack: Int, count: Int)] = [
            (0, 8), (1, 6), (2, 9), (3, 4), (4, 7), (6, 5), (7, 6), (9, 3),
            (10, 8), (12, 4), (14, 6), (15, 5), (18, 3), (21, 4), (24, 5),
            (28, 6), (32, 4), (40, 3), (50, 5), (60, 2), (70, 3), (80, 4)
        ]

        var seeded: [String: AnsweredEntry] = [:]
        var i = 0
        for (daysBack, count) in plan {
            let day = cal.date(byAdding: .day, value: -daysBack, to: now)!
            let dayStart = cal.date(bySettingHour: 19, minute: 30, second: 0, of: day)!
            for _ in 0..<count where i < questions.count {
                let q = questions[i]
                seeded[q.id] = AnsweredEntry(
                    attempts: 1, correct: 1,
                    lastAt: dayStart, lastCorrect: dayStart, streakCorrect: 1
                )
                i += 1
            }
            if i >= questions.count { break }
        }

        if let data = try? JSONEncoder().encode(seeded) {
            UserDefaults.standard.set(data, forKey: "mathio.answered.v2")
        }
    }
}
#endif
