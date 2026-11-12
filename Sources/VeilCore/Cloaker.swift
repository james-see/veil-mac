import Foundation

/// Contextual detector (the Rampart ONNX model in the app; a stub in tests).
/// Receives premasked text and returns spans in *that* text's UTF-16 coordinates.
public protocol NERDetector: Sendable {
    func detect(_ text: String) async throws -> [Span]
}

public struct CloakResult: Sendable {
    public let text: String
    public let spans: [Span]          // over the raw input
    public let replaced: Int
}

/// Rampart pipeline: heuristics → premask → NER on masked text → project → merge/policy → twin substitution.
public final class Cloaker: @unchecked Sendable {
    public let map: TwinMap
    public var ner: NERDetector?
    public var keep: Set<PiiLabel>

    public init(map: TwinMap = TwinMap(), ner: NERDetector? = nil, keep: Set<PiiLabel> = PiiLabel.defaultKeep) {
        self.map = map; self.ner = ner; self.keep = keep
    }

    public func detect(_ raw: String) async throws -> [Span] {
        let heur = Heuristics.detect(raw)
        var all = heur
        if let ner {
            let pm = premask(raw, spans: heur)
            // Rampart replaces '-' with ' ' (1:1) before inference so hyphenated names split cleanly.
            let infer = pm.masked.replacingOccurrences(of: "-", with: " ")
            for s in try await ner.detect(infer) {
                if let p = pm.project(s, raw: raw) { all.append(p) }
            }
        }
        return applyPolicy(all, raw: raw, keep: keep)
    }

    public func cloak(_ raw: String) async throws -> CloakResult {
        let spans = try await detect(raw)
        let ns = raw as NSString
        var out = "", last = 0
        for s in spans.sorted(by: { $0.start < $1.start }) where s.start >= last {
            out += ns.substring(with: NSRange(location: last, length: s.start - last))
            out += map.twin(for: s.text, label: s.label)
            last = s.end
        }
        out += ns.substring(from: last)
        return CloakResult(text: out, spans: spans, replaced: spans.count)
    }

    public func uncloak(_ text: String) -> String { map.restore(text) }
}

/// Token-window planner: Rampart budgets 512 - 2 specials - 10 margin, with 64-token overlap.
public enum NERWindowing {
    public static let maxTokens = 512
    public static let budget = maxTokens - 2 - 10
    public static let overlap = 64

    /// Returns half-open token index ranges covering `count` tokens.
    public static func windows(count: Int, budget: Int = budget, overlap: Int = overlap) -> [Range<Int>] {
        guard count > 0 else { return [] }
        guard count > budget else { return [0..<count] }
        var out: [Range<Int>] = [], start = 0
        while true {
            let end = min(start + budget, count)
            out.append(start..<end)
            if end == count { break }
            start = end - overlap
        }
        return out
    }
}
