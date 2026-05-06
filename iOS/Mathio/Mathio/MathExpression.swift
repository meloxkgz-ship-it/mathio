import Foundation

// MARK: - Answer normalization
//
// Goal: a user typing "6x + 2", "2 + 6x", "2+6x", "6·x+2" all match
// the canonical "6x+2". This is a string-level normalizer (no algebra solver).
// Authors list the canonical forms; the normalizer makes input forgiving.

enum MathInput {

    /// Compare a user answer to a list of accepted canonical strings.
    static func matches(_ user: String, accepted: [String]) -> Bool {
        let n = normalize(user)
        guard !n.isEmpty else { return false }
        return accepted.map(normalize).contains(n)
    }

    /// Reduce a math-ish string to a comparable canonical form.
    static func normalize(_ s: String) -> String {
        var out = s.lowercased()

        // Replace common synonyms.
        let replacements: [(String, String)] = [
            ("²", "^2"), ("³", "^3"), ("⁴", "^4"), ("⁵", "^5"), ("⁶", "^6"),
            ("·", "*"), ("×", "*"), ("∙", "*"),
            ("π", "pi"),
            ("√", "sqrt"),
            ("∫", "int"),
            ("≤", "<="), ("≥", ">="),
            ("−", "-"),               // Unicode minus → ASCII hyphen
            ("–", "-"), ("—", "-"),   // en-dash, em-dash
            (" ", ""),
            ("\t", "")
        ]
        for (k, v) in replacements { out = out.replacingOccurrences(of: k, with: v) }

        // Locale-aware decimal: DE typing "1,5" is meant as "1.5". A bare comma
        // between digits, with no other commas elsewhere, is a decimal mark.
        out = normalizeDECommaDecimal(out)

        // Tidy any decimal numbers: 4.0 → 4 ; 4.50 → 4.5 ; 12.000 → 12.
        out = canonicalizeNumbers(in: out)

        // Sort comma-separated lists numerically when all items are numbers.
        if out.contains(",") {
            let parts = out.split(separator: ",").map(String.init)
            if parts.allSatisfy({ Double($0) != nil }) {
                let sorted = parts.compactMap(Double.init).sorted()
                out = sorted.map(formatNumber).joined(separator: ",")
            }
        }

        // Reorder a single-variable polynomial like "2+6x" → "6x+2"
        // by sorting "+" terms with x before constants.
        out = reorderTerms(out)

        return out
    }

    /// Convert German-style "1,5" decimals to "1.5" — but only if the string
    /// looks like a single number (or pair like "2,3"). Multi-comma lists like
    /// "2,3,5" stay as-is so they remain a comma-separated answer list.
    private static func normalizeDECommaDecimal(_ s: String) -> String {
        guard Locale.current.language.languageCode?.identifier == "de" else { return s }
        // Single comma between digits with no other comma: treat as decimal.
        let pattern = #"^(\d+),(\d+)$"#
        if let re = try? NSRegularExpression(pattern: pattern),
           re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil {
            return s.replacingOccurrences(of: ",", with: ".")
        }
        return s
    }

    /// Replace every `[0-9]+(\.[0-9]+)?` token with its canonical Decimal form.
    /// "4.0" → "4", "4.500" → "4.5", "0.5" → "0.5".
    private static func canonicalizeNumbers(in s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"\d+\.\d+"#) else { return s }
        let ns = s as NSString
        let matches = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
        var result = s
        for m in matches.reversed() {
            guard let range = Range(m.range, in: result) else { continue }
            let token = String(result[range])
            if let d = Double(token) {
                result.replaceSubrange(range, with: formatNumber(d))
            }
        }
        return result
    }

    private static func formatNumber(_ d: Double) -> String {
        if d == d.rounded() { return String(Int(d)) }
        // Strip insignificant trailing zeros: 4.50 → 4.5
        var s = String(d)
        while s.contains(".") && s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// Splits on top-level "+" and reorders so that variable-bearing terms
    /// come first, constants last. Negative terms keep their sign.
    private static func reorderTerms(_ s: String) -> String {
        // Bail early for equations / inequalities — semantics differ.
        if s.contains("=") || s.contains("<") || s.contains(">") { return s }

        var terms: [(sign: Character, body: String)] = []
        var current = ""
        var sign: Character = "+"
        var depth = 0

        for ch in s {
            if ch == "(" {
                depth += 1; current.append(ch); continue
            }
            if ch == ")" {
                depth -= 1; current.append(ch); continue
            }
            if depth == 0 && (ch == "+" || ch == "-") && !current.isEmpty {
                terms.append((sign, current))
                current = ""
                sign = ch
            } else if depth == 0 && (ch == "+" || ch == "-") {
                // leading sign — capture, then keep building
                sign = ch
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { terms.append((sign, current)) }
        guard terms.count > 1 else { return s }

        // Sort variable terms by descending degree (x^2 before x), then
        // alphabetically. Constants last in original numeric order.
        let withVars = terms.filter { $0.body.contains(where: \.isLetter) }
        let constants = terms.filter { !$0.body.contains(where: \.isLetter) }
        let sortedVars = withVars.sorted {
            let lDeg = degree(of: $0.body), rDeg = degree(of: $1.body)
            if lDeg != rDeg { return lDeg > rDeg }
            return $0.body < $1.body
        }
        let ordered = sortedVars + constants

        var rebuilt = ""
        for (i, t) in ordered.enumerated() {
            if i == 0 {
                if t.sign == "-" { rebuilt.append("-") }
            } else {
                rebuilt.append(t.sign)
            }
            rebuilt.append(t.body)
        }
        return rebuilt
    }

    /// Best-effort degree extraction: finds the highest "^N" exponent in a term;
    /// returns 1 if a letter is present without an explicit exponent, else 0.
    private static func degree(of term: String) -> Int {
        guard term.contains(where: \.isLetter) else { return 0 }
        guard let re = try? NSRegularExpression(pattern: #"\^(-?\d+)"#) else { return 1 }
        let ns = term as NSString
        let matches = re.matches(in: term, range: NSRange(location: 0, length: ns.length))
        var maxDeg = 1
        for m in matches {
            if m.numberOfRanges >= 2 {
                let r = m.range(at: 1)
                if let range = Range(r, in: term), let n = Int(term[range]) {
                    maxDeg = max(maxDeg, n)
                }
            }
        }
        return maxDeg
    }
}
