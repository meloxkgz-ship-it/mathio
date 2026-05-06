import SwiftUI

// MARK: - Calendar heatmap
//
// GitHub-style activity grid: 7 rows (weekdays) × N weeks. Cells colored by
// number of correct answers on that day. Pure SwiftUI, no Charts dependency.

struct CalendarHeatmap: View {
    let activity: [Date: Int]   // localized date keys (start-of-day) → correct count
    var weeks: Int = 12         // ~3 months
    var cellSize: CGFloat = 14
    var spacing: CGFloat = 3

    private var cal: Calendar { Calendar.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                weekdayLabels
                grid
            }
            legend
        }
    }

    // MARK: - Grid

    private var grid: some View {
        let columns = days.chunked(into: 7)
        return HStack(alignment: .top, spacing: spacing) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                VStack(spacing: spacing) {
                    ForEach(column, id: \.self) { day in
                        cell(for: day)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(for day: Date) -> some View {
        let count = activity[cal.startOfDay(for: day)] ?? 0
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color(for: count))
            .frame(width: cellSize, height: cellSize)
            .accessibilityLabel(Text(label(day, count)))
    }

    private func color(for count: Int) -> Color {
        switch count {
        case 0:      return Palette.surfaceMuted
        case 1...2:  return Palette.terracotta.opacity(0.30)
        case 3...5:  return Palette.terracotta.opacity(0.55)
        case 6...9:  return Palette.terracotta.opacity(0.78)
        default:     return Palette.terracotta
        }
    }

    private func label(_ day: Date, _ count: Int) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.locale = .current
        return "\(f.string(from: day)): \(count) correct"
    }

    // MARK: - Days (oldest first, 7×weeks total)

    private var days: [Date] {
        let today = cal.startOfDay(for: .now)
        let totalDays = weeks * 7
        // Anchor end on today, move back totalDays - 1.
        return (0..<totalDays).reversed().compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: today)
        }
    }

    // MARK: - Decoration

    private var weekdayLabels: some View {
        let symbols = cal.shortWeekdaySymbols
        return VStack(alignment: .trailing, spacing: spacing) {
            ForEach(0..<7) { i in
                Text(symbols[i].first.map(String.init) ?? "")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.inkFaint)
                    .frame(width: 14, height: cellSize)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("Less").font(.caption).foregroundStyle(Palette.inkFaint)
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(legendColor(for: i))
                    .frame(width: 10, height: 10)
            }
            Text("More").font(.caption).foregroundStyle(Palette.inkFaint)
        }
    }

    private func legendColor(for step: Int) -> Color {
        switch step {
        case 0: return Palette.surfaceMuted
        case 1: return Palette.terracotta.opacity(0.30)
        case 2: return Palette.terracotta.opacity(0.55)
        case 3: return Palette.terracotta.opacity(0.78)
        default: return Palette.terracotta
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
