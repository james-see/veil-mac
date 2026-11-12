import Foundation

/// Rampart's id2label (config.json, BertForTokenClassification, 35 labels).
public let rampartId2Label: [String] = [
    "O", "B-GIVEN_NAME", "I-GIVEN_NAME", "B-SURNAME", "I-SURNAME", "B-EMAIL", "I-EMAIL", "B-PHONE", "I-PHONE",
    "B-URL", "I-URL", "B-TAX_ID", "I-TAX_ID", "B-BANK_ACCOUNT", "I-BANK_ACCOUNT", "B-ROUTING_NUMBER", "I-ROUTING_NUMBER",
    "B-GOVERNMENT_ID", "I-GOVERNMENT_ID", "B-PASSPORT", "I-PASSPORT", "B-DRIVERS_LICENSE", "I-DRIVERS_LICENSE",
    "B-BUILDING_NUMBER", "I-BUILDING_NUMBER", "B-STREET_NAME", "I-STREET_NAME", "B-SECONDARY_ADDRESS", "I-SECONDARY_ADDRESS",
    "B-CITY", "I-CITY", "B-STATE", "I-STATE", "B-ZIP_CODE", "I-ZIP_CODE",
]

/// Thresholds from rampart/src/ner/classifier.ts.
public enum NERThresholds {
    public static let anchor = 0.4   // minScore default
    public static let extend = 0.15  // EXTEND_SCORE: weaker spans kept only when bridged to an anchor
}

/// Turn per-token logits into spans (mirrors Rampart's mergeBioTokens + a simplified repairSpans):
/// softmax → argmax; non-O tokens grouped; a `##` continuation of the same base label always extends
/// (even if tagged B-); an I- of the same base extends; spans' score = mean token score.
public enum BIODecoder {
    public static func decode(tokens: [Token], logits: [[Float]], text: String,
                              id2label: [String] = rampartId2Label) -> [Span] {
        struct Cur { var base: String; var start: Int; var end: Int; var score: Double; var n: Int; var lastTok: Int }
        var raw: [Cur] = [], cur: Cur?
        func flush() { if let c = cur { raw.append(c); cur = nil } }
        for (i, tok) in tokens.enumerated() where i < logits.count {
            let probs = softmax(logits[i])
            let (best, p) = probs.enumerated().max { $0.element < $1.element }.map { ($0.offset, Double($0.element)) }!
            let lab = best < id2label.count ? id2label[best] : "O"
            if lab == "O" { flush(); continue }
            let prefix = String(lab.prefix(1)), base = String(lab.dropFirst(2))
            let sub = tok.piece.hasPrefix("##")
            if var c = cur, c.base == base, prefix != "B" || sub {
                c.end = tok.end; c.score += p; c.n += 1; c.lastTok = i; cur = c
            } else {
                flush(); cur = Cur(base: base, start: tok.start, end: tok.end, score: p, n: 1, lastTok: i)
            }
        }
        flush()
        let spans: [Span] = raw.compactMap { c in
            guard let label = PiiLabel(rawValue: c.base) else { return nil }
            let s = c.score / Double(c.n)
            guard s >= NERThresholds.extend else { return nil }
            return Span(start: c.start, end: c.end, label: label, score: s, source: .ner, text: text.utf16Slice(c.start, c.end))
        }
        return repair(spans, text: text)
    }

    /// Keep anchors (>= 0.4); rescue weaker spans touching an anchor across only connector chars (space ' ’ . -).
    static func repair(_ spans: [Span], text: String) -> [Span] {
        var kept = spans.filter { $0.score >= NERThresholds.anchor }
        var cands = spans.filter { $0.score < NERThresholds.anchor }
        var changed = true, iters = 0
        while changed && iters < 32 {
            changed = false; iters += 1
            for (i, c) in cands.enumerated().reversed() where kept.contains(where: { bridges(c, $0, text) }) {
                kept.append(c); cands.remove(at: i); changed = true
            }
        }
        return kept.sorted { $0.start < $1.start }
    }

    static func bridges(_ a: Span, _ b: Span, _ text: String) -> Bool {
        let person: Set<PiiLabel> = [.givenName, .surname]
        guard a.label == b.label || (person.contains(a.label) && person.contains(b.label)) else { return false }
        let (l, r) = a.start < b.start ? (a, b) : (b, a)
        guard r.start >= l.end else { return true }
        let gap = text.utf16Slice(l.end, r.start)
        return gap.count <= 3 && gap.allSatisfy { " '\u{2019}.-".contains($0) }
    }

    static func softmax(_ x: [Float]) -> [Float] {
        let m = x.max() ?? 0
        let e = x.map { expf($0 - m) }
        let s = e.reduce(0, +)
        return e.map { $0 / s }
    }
}
