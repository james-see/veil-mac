import Foundation

/// Deterministic layer, ported from rampart/src/heuristics.ts.
/// Digit runs (digits joined by single space/dash/dot) are classified by length + validator:
/// 16/15/14 + Luhn → CREDIT_CARD, 9 + SSN rules → SSN. Text-shaped rules: EMAIL, URL, IPv4/IPv6/MAC.
/// Veil addition (not in Rampart, where PHONE is model-only): NANP phone numbers.
public enum Heuristics {
    private static let digitRun = try! NSRegularExpression(pattern: #"\d(?:[ .-]?\d)*"#)

    private struct TextRule { let label: PiiLabel; let regex: NSRegularExpression }
    private static func r(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }

    private static let textRules: [TextRule] = [
        TextRule(label: .email, regex: r(#"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"#)),
        TextRule(label: .url, regex: r(#"\bhttps?://[^\s<>"'\])}]+"#)),
        TextRule(label: .url, regex: r(#"\bwww\.[A-Za-z0-9.-]+\.[A-Za-z]{2,}(?:/[^\s<>"'\])}]*)?"#)),
        TextRule(label: .ipAddress, regex: r(#"\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b"#)),
        TextRule(label: .ipAddress, regex: r(
            #"(?<![:.\w])(?:(?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}|(?:[0-9A-Fa-f]{1,4}:){1,7}:|(?:[0-9A-Fa-f]{1,4}:){1,6}:[0-9A-Fa-f]{1,4}|(?:[0-9A-Fa-f]{1,4}:){1,5}(?::[0-9A-Fa-f]{1,4}){1,2}|(?:[0-9A-Fa-f]{1,4}:){1,4}(?::[0-9A-Fa-f]{1,4}){1,3}|(?:[0-9A-Fa-f]{1,4}:){1,3}(?::[0-9A-Fa-f]{1,4}){1,4}|(?:[0-9A-Fa-f]{1,4}:){1,2}(?::[0-9A-Fa-f]{1,4}){1,5}|[0-9A-Fa-f]{1,4}:(?::[0-9A-Fa-f]{1,4}){1,6}|::(?:[0-9A-Fa-f]{1,4}:){0,6}[0-9A-Fa-f]{1,4})(?![:.\w])"#)),
        TextRule(label: .ipAddress, regex: r(#"\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b"#)),
        // Veil extension: (555) 123-4567, 555-123-4567, +1 555.123.4567, 5551234567
        TextRule(label: .phone, regex: r(#"(?<![\w+])(?:\+?1[ .-]?)?(?:\(\d{3}\)\s?|\d{3}[ .-]?)\d{3}[ .-]?\d{4}(?!\w)"#)),
    ]

    public static func detect(_ raw: String) -> [Span] {
        detectDigitEntities(raw) + detectTextEntities(raw)
    }

    static func detectDigitEntities(_ raw: String) -> [Span] {
        let ns = raw as NSString
        var spans: [Span] = []
        for m in digitRun.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
            var digits = "", idx: [Int] = []
            for i in 0..<m.range.length {
                let c = ns.character(at: m.range.location + i)
                if c >= 0x30 && c <= 0x39 { digits.append(Character(UnicodeScalar(c)!)); idx.append(m.range.location + i) }
            }
            let label: PiiLabel?
            if [16, 15, 14].contains(digits.count) && isLuhnValid(digits) { label = .creditCard }
            else if digits.count == 9 && isValidSsn(digits) { label = .ssn }
            else { label = nil }
            if let label, let s = idx.first, let e = idx.last.map({ $0 + 1 }) {
                spans.append(Span(start: s, end: e, label: label, score: 1, source: .heuristic, text: ns.substring(with: NSRange(location: s, length: e - s))))
            }
        }
        return spans
    }

    static func detectTextEntities(_ raw: String) -> [Span] {
        let ns = raw as NSString
        var spans: [Span] = []
        for rule in textRules {
            for m in rule.regex.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
                let text = ns.substring(with: m.range)
                if rule.label == .phone {
                    let digits = text.filter(\.isASCIIDigitChar)
                    guard isPlausibleNanpPhone(digits) else { continue }
                }
                spans.append(Span(start: m.range.location, end: m.range.location + m.range.length,
                                  label: rule.label, score: 1, source: .heuristic, text: text))
            }
        }
        return spans
    }
}
