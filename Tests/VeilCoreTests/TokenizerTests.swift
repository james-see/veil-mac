import XCTest
@testable import VeilCore

final class TokenizerTests: XCTestCase {
    let tok = WordPieceTokenizer(vocab: ["[PAD]": 0, "[UNK]": 1, "[CLS]": 2, "[SEP]": 3, "[MASK]": 4,
                                         "jose": 5, "lives": 6, "in": 7, "ber": 8, "##lin": 9, ".": 10, "[": 11, "ssn": 12, "]": 13])

    func testLowercaseAccentStripAndOffsets() {
        let t = tok.tokenize("José lives in Berlin.")
        XCTAssertEqual(t.map(\.piece), ["jose", "lives", "in", "ber", "##lin", "."])
        XCTAssertEqual(t[0].start, 0); XCTAssertEqual(t[0].end, 4)
        XCTAssertEqual(t[4].start, 17); XCTAssertEqual(t[4].end, 20)
    }

    func testSentinelSplitsOnPunctuation() {
        XCTAssertEqual(tok.tokenize("[SSN]").map(\.id), [11, 12, 13])
    }

    func testUnknownWord() { XCTAssertEqual(tok.tokenize("zzz").map(\.id), [1]) }

    func testBIODecodeSubwordContinuation() {
        let text = "Berlin"
        let toks = tok.tokenize(text)               // ber, ##lin
        func onehot(_ i: Int) -> [Float] { (0..<35).map { $0 == i ? 10 : 0 } }
        // Model mislabels the ## piece as B-: Rampart treats it as continuation.
        let spans = BIODecoder.decode(tokens: toks, logits: [onehot(3), onehot(3)], text: text)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].label, .surname); XCTAssertEqual(spans[0].text, "Berlin")
    }
}
