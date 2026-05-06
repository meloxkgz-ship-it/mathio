import SwiftUI

// MARK: - Palette
//
// Semantic colors that adapt to dark mode. Brand hues stay warm in both modes
// — a dark-cream-to-deep-warm shift, not a sterile gray flip. Numbers are
// color-blind-friendly (no red/green pair for state — we always pair with
// icons that disambiguate).

private extension Color {
    /// Build a dynamic color that responds to the current trait's user interface style.
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
    }
}

enum Palette {
    // Surfaces
    static let background      = Color.dynamic(
        light: Color(red: 0.984, green: 0.969, blue: 0.945),  // #FBF7F1
        dark:  Color(red: 0.071, green: 0.063, blue: 0.055)   // #12100E
    )
    static let surface         = Color.dynamic(
        light: .white,
        dark:  Color(red: 0.110, green: 0.098, blue: 0.086)
    )
    static let surfaceMuted    = Color.dynamic(
        light: Color(red: 0.969, green: 0.953, blue: 0.925),
        dark:  Color(red: 0.149, green: 0.133, blue: 0.114)
    )

    // Type
    static let ink             = Color.dynamic(
        light: Color(red: 0.078, green: 0.067, blue: 0.055),
        dark:  Color(red: 0.973, green: 0.957, blue: 0.929)
    )
    static let inkSoft         = Color.dynamic(
        light: Color(red: 0.298, green: 0.275, blue: 0.247),
        dark:  Color(red: 0.812, green: 0.788, blue: 0.745)
    )
    static let inkFaint        = Color.dynamic(
        light: Color(red: 0.612, green: 0.580, blue: 0.529),
        dark:  Color(red: 0.580, green: 0.553, blue: 0.510)
    )
    static let hairline        = Color.dynamic(
        light: Color(red: 0.902, green: 0.875, blue: 0.835),
        dark:  Color(red: 0.196, green: 0.173, blue: 0.149)
    )

    // Brand — same in both modes (warm hues read fine on dark)
    static let terracotta      = Color(red: 0.769, green: 0.373, blue: 0.180)
    static let terracottaSoft  = Color.dynamic(
        light: Color(red: 0.945, green: 0.847, blue: 0.788),
        dark:  Color(red: 0.349, green: 0.180, blue: 0.094)
    )
    static let amber           = Color(red: 0.961, green: 0.851, blue: 0.498)
    static let amberSoft       = Color.dynamic(
        light: Color(red: 0.984, green: 0.937, blue: 0.804),
        dark:  Color(red: 0.357, green: 0.298, blue: 0.165)
    )

    // Topic accents — solid hues; same in both modes
    static let algebra      = Color(red: 0.851, green: 0.490, blue: 0.247)
    static let calculus     = Color(red: 0.388, green: 0.561, blue: 0.812)
    static let geometry     = Color(red: 0.388, green: 0.643, blue: 0.451)
    static let precalc      = Color(red: 0.580, green: 0.475, blue: 0.788)
    static let stats        = Color(red: 0.788, green: 0.396, blue: 0.584)
    static let trig         = Color(red: 0.875, green: 0.706, blue: 0.349)

    // State
    static let success      = Color(red: 0.275, green: 0.580, blue: 0.353)
    static let warning      = Color(red: 0.851, green: 0.522, blue: 0.157)
    static let error        = Color(red: 0.812, green: 0.318, blue: 0.263)
}

// MARK: - Typography

extension Font {
    static let displayXL = Font.system(size: 44, weight: .bold, design: .serif)
    static let displayL  = Font.system(size: 34, weight: .bold, design: .serif)
    static let displayM  = Font.system(size: 28, weight: .bold, design: .serif)
    static let titleL    = Font.system(size: 22, weight: .semibold, design: .serif)
    static let titleM    = Font.system(size: 19, weight: .semibold, design: .default)
    static let bodyL     = Font.system(size: 17, weight: .regular, design: .default)
    static let bodyM     = Font.system(size: 15, weight: .regular, design: .default)
    static let label     = Font.system(size: 13, weight: .medium, design: .default)
    static let caption   = Font.system(size: 12, weight: .regular, design: .default)
    static let mathBody  = Font.system(size: 22, weight: .regular, design: .serif)
    static let mathLarge = Font.system(size: 28, weight: .regular, design: .serif)
}

// MARK: - Card

struct Card<Content: View>: View {
    var padding: CGFloat = 20
    var background: Color = Palette.surface
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Palette.hairline, lineWidth: 0.5)
            )
    }
}

// MARK: - Buttons

struct PrimaryButton: View {
    let title: LocalizedStringResource
    var icon: String? = nil
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: { if enabled { action() } }) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon) }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(enabled ? Color.white : Color.white.opacity(0.7))
            .background(enabled ? Palette.ink : Palette.inkFaint)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: enabled)
        .disabled(!enabled)
    }
}

struct SecondaryButton: View {
    let title: LocalizedStringResource
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(title).fontWeight(.medium)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(Palette.ink)
            .background(Palette.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Round icon button used for header actions. Includes accessibility label.
struct IconButton: View {
    let symbol: String
    let label: LocalizedStringResource
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(width: 40, height: 40)
                .background(Palette.surfaceMuted)
                .clipShape(Circle())
        }
        .accessibilityLabel(Text(label))
    }
}

// MARK: - Progress

struct ProgressRing: View {
    let progress: Double
    var size: CGFloat = 40
    var lineWidth: CGFloat = 4
    var color: Color = Palette.terracotta

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.0001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.4), value: progress)
    }
}

struct ProgressBar: View {
    let progress: Double
    var color: Color = Palette.terracotta
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.18))
                Capsule().fill(color)
                    .frame(width: geo.size.width * max(0, min(1, progress)))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Streak badge

struct StreakBadge: View {
    let days: Int
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill").foregroundStyle(Palette.terracotta)
            Text("\(days)")
                .font(.label).fontWeight(.bold)
                .foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Palette.amberSoft)
        .clipShape(Capsule())
        .accessibilityLabel(Text("Streak: \(days) days"))
    }
}

// MARK: - Section header

struct SectionLabel: View {
    let title: LocalizedStringResource
    var body: some View {
        Text(title)
            .font(.label).textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(Palette.inkFaint)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - MathText
//
// Renders simple math expressions with serif italic variables and Unicode
// super/subscripts. Authoring tokens: {var:x}, {sup:^2}, {sub:_n},
// {sqrt:expr}, {frac:a/b}.

struct MathText: View {
    let raw: String
    var size: CGFloat = 22

    var body: some View {
        Text(attributed)
            .accessibilityLabel(Text(spokenForm))
    }

    private var attributed: AttributedString {
        var out = AttributedString()
        var s = raw[...]
        while !s.isEmpty {
            if let r = s.range(of: "{") {
                out.append(plain(String(s[s.startIndex..<r.lowerBound])))
                s = s[r.upperBound...]
                guard let end = s.range(of: "}") else {
                    out.append(plain(String(s)))
                    break
                }
                let token = String(s[s.startIndex..<end.lowerBound])
                s = s[end.upperBound...]
                out.append(render(token: token))
            } else {
                out.append(plain(String(s)))
                break
            }
        }
        return out
    }

    /// Best-effort plain-text spoken form for VoiceOver.
    private var spokenForm: String {
        var s = raw
        s = s.replacingOccurrences(of: "{var:", with: "")
        s = s.replacingOccurrences(of: "{sup:^", with: " to the ")
        s = s.replacingOccurrences(of: "{sub:_", with: " sub ")
        s = s.replacingOccurrences(of: "{sqrt:", with: " square root of ")
        s = s.replacingOccurrences(of: "{frac:", with: " fraction ")
        s = s.replacingOccurrences(of: "}", with: "")
        s = s.replacingOccurrences(of: "/", with: " over ")
        return s
    }

    private func plain(_ str: String) -> AttributedString {
        var a = AttributedString(str)
        a.font = .system(size: size, weight: .regular, design: .serif)
        a.foregroundColor = Palette.ink
        return a
    }

    private func italic(_ str: String) -> AttributedString {
        var a = AttributedString(str)
        a.font = .system(size: size, weight: .regular, design: .serif).italic()
        a.foregroundColor = Palette.ink
        return a
    }

    private func render(token: String) -> AttributedString {
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return plain("{\(token)}") }
        let kind = parts[0], value = parts[1]
        switch kind {
        case "var":
            return italic(value)
        case "sup":
            var a = AttributedString(value.unicodeSuperscript)
            a.font = .system(size: size * 0.75, weight: .regular, design: .serif)
            a.foregroundColor = Palette.ink
            a.baselineOffset = size * 0.35
            return a
        case "sub":
            var a = AttributedString(value)
            a.font = .system(size: size * 0.7, weight: .regular, design: .serif)
            a.foregroundColor = Palette.ink
            a.baselineOffset = -size * 0.18
            return a
        case "sqrt":
            return plain("√(") + italic(value) + plain(")")
        case "frac":
            let f = value.split(separator: "/", maxSplits: 1).map(String.init)
            if f.count == 2 {
                return italic(f[0]) + plain(" / ") + italic(f[1])
            }
            return plain(value)
        default:
            return plain(value)
        }
    }
}

private extension String {
    var unicodeSuperscript: String {
        let table: [Character: Character] = [
            "0":"⁰","1":"¹","2":"²","3":"³","4":"⁴","5":"⁵","6":"⁶","7":"⁷","8":"⁸","9":"⁹",
            "+":"⁺","-":"⁻","=":"⁼","(":"⁽",")":"⁾",
            "n":"ⁿ","i":"ⁱ","x":"ˣ","y":"ʸ"
        ]
        return String(self.map { table[$0] ?? $0 })
    }
}

struct MathBlock: View {
    let raw: String
    var body: some View {
        MathText(raw: raw, size: 28)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Palette.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Daily goal ring + label

struct DailyGoalView: View {
    let progress: Int
    let goal: Int
    var body: some View {
        let pct = goal > 0 ? Double(progress) / Double(goal) : 0
        let met = progress >= goal
        return HStack(spacing: 14) {
            ZStack {
                ProgressRing(progress: min(1, pct), size: 52, lineWidth: 5,
                             color: met ? Palette.success : Palette.terracotta)
                Image(systemName: met ? "checkmark" : "target")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(met ? Palette.success : Palette.terracotta)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Today")
                    .font(.label).textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(Palette.inkFaint)
                Text(met ? "Goal reached. Nice." : "\(progress) of \(goal) correct")
                    .font(.titleM)
                    .foregroundStyle(Palette.ink)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(met
            ? "Daily goal reached. \(progress) correct out of \(goal)."
            : "\(progress) of \(goal) correct today."))
    }
}
