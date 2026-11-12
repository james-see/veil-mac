import Foundation

/// Ported from rampart/src/premask.ts. Heuristic spans are replaced with `[LABEL]` sentinels before
/// the model runs (the model was trained on text masked the same way). Each masked UTF-16 unit maps
/// back to a raw range so model spans can be projected onto the raw input.
public struct PremaskResult {
    public let masked: String
    public let rawStart: [Int]
    public let rawEnd: [Int]

    public func project(_ span: Span, raw: String) -> Span? {
        guard span.end > span.start, span.start < rawStart.count, span.end - 1 < rawEnd.count else { return nil }
        let s = rawStart[span.start], e = rawEnd[span.end - 1]
        guard e > s else { return nil }
        var out = span; out.start = s; out.end = e; out.text = raw.utf16Slice(s, e)
        return out
    }
}

public func sentinel(for label: PiiLabel) -> String { "[\(label.rawValue)]" }

public func premask(_ raw: String, spans: [Span]) -> PremaskResult {
    let units = Array(raw.utf16)
    var masked: [UInt16] = [], rs: [Int] = [], re: [Int] = []
    var cursor = 0
    func copy(_ a: Int, _ b: Int) { for i in a..<b { masked.append(units[i]); rs.append(i); re.append(i + 1) } }
    for span in mergeSpans(spans) where span.start >= cursor {
        copy(cursor, span.start)
        for u in sentinel(for: span.label).utf16 { masked.append(u); rs.append(span.start); re.append(span.end) }
        cursor = span.end
    }
    copy(cursor, units.count)
    return PremaskResult(masked: String(decoding: masked, as: UTF16.self), rawStart: rs, rawEnd: re)
}
