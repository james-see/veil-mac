import Foundation

/// Session table: original ↔ twin, bijective. Same original (per label) → same twin for the whole session,
/// and a twin is never reused for a different original or equal to any original seen.
public final class TwinMap: @unchecked Sendable {
    public struct Entry: Equatable, Codable, Sendable { public let original: String; public let twin: String; public let label: PiiLabel }

    private let lock = NSLock()
    private var byOriginal: [String: Entry] = [:]   // key: "LABEL|original"
    private var byTwin: [String: Entry] = [:]
    private var originals: Set<String> = []
    public private(set) var generator: TwinGenerator

    public init(salt: UInt64 = UInt64.random(in: .min ... .max), persona: TwinPersona? = nil) {
        generator = TwinGenerator(salt: salt, persona: persona)
    }

    public var persona: TwinPersona? { lock.withLock { generator.persona } }

    public var entries: [Entry] { lock.withLock { Array(byOriginal.values).sorted { $0.original < $1.original } } }
    public var count: Int { lock.withLock { byOriginal.count } }

    /// Get or mint the twin for `original`.
    public func twin(for original: String, label: PiiLabel) -> String {
        lock.withLock {
            let key = "\(label.rawValue)|\(original)"
            if let e = byOriginal[key] { return e.twin }
            // If the text already contains a twin we minted (re-cloaking cloaked text), keep it.
            if byTwin[original] != nil { return original }
            var attempt = 0, t = generator.twin(for: original, label: label)
            while byTwin[t] != nil || originals.contains(t) || t == original {
                attempt += 1; t = generator.twin(for: original, label: label, attempt: attempt)
                if attempt > 64 { t += "-\(attempt)"; break }
            }
            let e = Entry(original: original, twin: t, label: label)
            byOriginal[key] = e; byTwin[t] = e; originals.insert(original)
            return t
        }
    }

    public func original(forTwin twin: String) -> String? { lock.withLock { byTwin[twin]?.original } }

    /// Replace every known twin in `text` with its original. Longest twins first so "Avery Hollis" style
    /// overlaps and prefixes resolve correctly; single pass via regex alternation so a restored original
    /// is never re-substituted.
    public func restore(_ text: String) -> String {
        let pairs: [(String, String)] = lock.withLock { byTwin.map { ($0.key, $0.value.original) } }
        guard !pairs.isEmpty else { return text }
        let sorted = pairs.sorted { $0.0.count > $1.0.count }
        let lookup = Dictionary(sorted, uniquingKeysWith: { a, _ in a })
        let pattern = sorted.map { NSRegularExpression.escapedPattern(for: $0.0) }.joined(separator: "|")
        guard let re = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var out = "", last = 0
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let hit = ns.substring(with: m.range)
            out += lookup[hit] ?? hit
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    /// Wipe the session. Keeps the current persona unless a new one is given.
    public func clear(persona newPersona: TwinPersona?? = nil) {
        lock.withLock {
            byOriginal.removeAll(); byTwin.removeAll(); originals.removeAll()
            generator = TwinGenerator(salt: UInt64.random(in: .min ... .max), persona: newPersona ?? generator.persona)
        }
    }
}
