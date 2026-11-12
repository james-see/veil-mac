import Foundation

/// BERT uncased WordPiece tokenizer matching Rampart's tokenizer.json:
/// BertNormalizer(clean_text, handle_chinese_chars, lowercase=true, strip_accents=nil → follows lowercase, i.e. strip)
/// + BertPreTokenizer (whitespace + punctuation split) + WordPiece("##", max 100 chars/word, [UNK]).
/// Rampart's vocab is custom (19,730 entries): [PAD]=0 [UNK]=1 [CLS]=2 [SEP]=3 [MASK]=4 — always read ids from vocab.txt.
public struct Token: Equatable, Sendable {
    public let id: Int
    public let piece: String
    /// UTF-16 offsets into the original text.
    public let start: Int
    public let end: Int
}

public final class WordPieceTokenizer: @unchecked Sendable {
    public let vocab: [String: Int]
    public let unkId, clsId, sepId, padId: Int
    let maxCharsPerWord = 100

    public init(vocab: [String: Int]) {
        self.vocab = vocab
        unkId = vocab["[UNK]"] ?? 1; clsId = vocab["[CLS]"] ?? 2
        sepId = vocab["[SEP]"] ?? 3; padId = vocab["[PAD]"] ?? 0
    }

    public convenience init(vocabURL: URL) throws {
        let lines = try String(contentsOf: vocabURL, encoding: .utf8).components(separatedBy: "\n")
        var v: [String: Int] = [:]
        for (i, l) in lines.enumerated() where !l.isEmpty { v[l] = i }
        self.init(vocab: v)
    }

    /// A normalized "word" with a per-character map back to raw UTF-16 offsets.
    struct Word { var chars: [Character] = []; var starts: [Int] = []; var ends: [Int] = [] }

    func preTokenize(_ text: String) -> [Word] {
        var words: [Word] = [], cur = Word()
        func flush() { if !cur.chars.isEmpty { words.append(cur); cur = Word() } }
        var off = 0
        for scalar in text.unicodeScalars {
            let len = scalar.utf16.count
            defer { off += len }
            let v = scalar.value
            // clean_text: drop NUL, U+FFFD, control chars (except whitespace)
            if v == 0 || v == 0xFFFD || (scalar.properties.generalCategory == .control && !scalar.properties.isWhitespace) { continue }
            if scalar.properties.isWhitespace { flush(); continue }
            // lowercase + NFD + strip combining marks
            let folded = String(scalar).lowercased().decomposedStringWithCanonicalMapping.unicodeScalars
                .filter { $0.properties.generalCategory != .nonspacingMark }
            for f in folded {
                let c = Character(f)
                if Self.isPunctuation(f) || Self.isCJK(f.value) {
                    flush(); words.append(Word(chars: [c], starts: [off], ends: [off + len]))
                } else {
                    cur.chars.append(c); cur.starts.append(off); cur.ends.append(off + len)
                }
            }
        }
        flush()
        return words
    }

    public func tokenize(_ text: String) -> [Token] {
        var out: [Token] = []
        for w in preTokenize(text) {
            if w.chars.count > maxCharsPerWord { out.append(Token(id: unkId, piece: "[UNK]", start: w.starts[0], end: w.ends.last!)); continue }
            var start = 0, pieces: [Token] = [], bad = false
            while start < w.chars.count {
                var end = w.chars.count, found: Token?
                while start < end {
                    var sub = String(w.chars[start..<end]); if start > 0 { sub = "##" + sub }
                    if let id = vocab[sub] { found = Token(id: id, piece: sub, start: w.starts[start], end: w.ends[end - 1]); break }
                    end -= 1
                }
                guard let f = found else { bad = true; break }
                pieces.append(f); start = end
            }
            if bad { out.append(Token(id: unkId, piece: "[UNK]", start: w.starts[0], end: w.ends.last!)) } else { out += pieces }
        }
        return out
    }

    static func isPunctuation(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        if (33...47).contains(v) || (58...64).contains(v) || (91...96).contains(v) || (123...126).contains(v) { return true }
        switch s.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation: return true
        default: return false
        }
    }

    static func isCJK(_ v: UInt32) -> Bool {
        (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0x20000...0x2A6DF).contains(v) ||
        (0x2A700...0x2B73F).contains(v) || (0x2B740...0x2B81F).contains(v) || (0x2B820...0x2CEAF).contains(v) ||
        (0xF900...0xFAFF).contains(v) || (0x2F800...0x2FA1F).contains(v)
    }
}
