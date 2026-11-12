import Foundation

/// Ported from rampart/src/policy.ts: collapse overlapping spans into a disjoint set.
/// Containment → keep preferred; partial overlap → union range under preferred label.
public func mergeSpans(_ spans: [Span]) -> [Span] {
    let sorted = spans.sorted { $0.start != $1.start ? $0.start < $1.start : $0.end > $1.end }
    var out: [Span] = []
    for span in sorted {
        guard var prev = out.last, span.start < prev.end else { out.append(span); continue }
        let winner = preferred(prev, span)
        let contains = (prev.start <= span.start && prev.end >= span.end) || (span.start <= prev.start && span.end >= prev.end)
        if contains { prev = winner } else {
            let s = min(prev.start, span.start), e = max(prev.end, span.end)
            prev = winner; prev.start = s; prev.end = e
        }
        out[out.count - 1] = prev
    }
    return out
}

private func preferred(_ a: Span, _ b: Span) -> Span {
    if a.score != b.score { return a.score > b.score ? a : b }
    if a.length != b.length { return a.length > b.length ? a : b }
    return a.source == .heuristic ? a : b
}

/// Merge, drop keep-set labels, refresh `text` from raw. Returned ascending by start.
public func applyPolicy(_ spans: [Span], raw: String, keep: Set<PiiLabel> = PiiLabel.defaultKeep) -> [Span] {
    mergeSpans(spans).filter { !keep.contains($0.label) }.map {
        var s = $0; s.text = raw.utf16Slice(s.start, s.end); return s
    }
}
