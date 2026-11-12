import XCTest
@testable import VeilCore

final class HeuristicsTests: XCTestCase {
    func labels(_ s: String) -> [PiiLabel] { applyPolicy(Heuristics.detect(s), raw: s).map(\.label) }

    func testLuhnAndSsnValidators() {
        XCTAssertTrue(isLuhnValid("4111111111111111"))
        XCTAssertFalse(isLuhnValid("4111111111111112"))
        XCTAssertTrue(isValidSsn("123456789"))
        for bad in ["000123456", "666123456", "900123456", "123006789", "123450000", "12345678"] { XCTAssertFalse(isValidSsn(bad), bad) }
    }

    func testCreditCardWithSeparators() {
        let s = "card 4111 1111 1111 1111 exp"
        let spans = applyPolicy(Heuristics.detect(s), raw: s)
        XCTAssertEqual(spans.map(\.label), [.creditCard])
        XCTAssertEqual(spans.first?.text, "4111 1111 1111 1111")
    }

    func testNonLuhnSixteenDigitsIgnored() { XCTAssertEqual(labels("order 1234567812345678"), []) }

    func testSsn() {
        let s = "SSN: 123-45-6789."
        XCTAssertEqual(applyPolicy(Heuristics.detect(s), raw: s).first?.text, "123-45-6789")
        XCTAssertEqual(labels("bad 666-12-3456"), [])
    }

    func testEmailUrlIp() {
        XCTAssertEqual(labels("mail alex+housing@sub.example.gov now"), [.email])
        XCTAssertEqual(labels("see https://foo.com/a?b=1 and www.bar.org/x"), [.url, .url])
        XCTAssertEqual(labels("host 10.0.0.255 mac 00:1A:2B:3C:4D:5E"), [.ipAddress, .ipAddress])
        XCTAssertEqual(labels("v6 2001:db8::1 ok"), [.ipAddress])
    }

    func testTimesAndYearsNotFlagged() {
        XCTAssertEqual(labels("Meet at 12:34 in 2024, income 85000"), [])
    }

    func testPhones() {
        XCTAssertEqual(labels("call (415) 555-2671 or +1 415.555.2671 or 4155552671"), [.phone, .phone, .phone])
        XCTAssertEqual(labels("zip 012-345-6789"), []) // area starting 0 rejected
    }

    func testMergePrefersHeuristicContainment() {
        let a = Span(start: 0, end: 10, label: .email, score: 1, source: .heuristic, text: "")
        let b = Span(start: 2, end: 5, label: .givenName, score: 0.9, source: .ner, text: "")
        XCTAssertEqual(mergeSpans([a, b]).map(\.label), [.email])
    }

    func testPremaskProjection() {
        let raw = "Hi Ann, SSN 123-45-6789 ok"
        let heur = Heuristics.detect(raw)
        let pm = premask(raw, spans: heur)
        XCTAssertEqual(pm.masked, "Hi Ann, SSN [SSN] ok")
        let ann = Span(start: 3, end: 6, label: .givenName, score: 0.9, source: .ner, text: "Ann")
        XCTAssertEqual(pm.project(ann, raw: raw)?.text, "Ann")
        let inSentinel = Span(start: 13, end: 15, label: .taxId, score: 0.5, source: .ner, text: "")
        XCTAssertEqual(pm.project(inSentinel, raw: raw)?.text, "123-45-6789")
    }

    func testKeepSetLeavesCityStateZip() {
        let spans = [Span(start: 0, end: 6, label: .city, score: 0.9, source: .ner, text: "Boston")]
        XCTAssertTrue(applyPolicy(spans, raw: "Boston").isEmpty)
    }

    func testWindowing() {
        XCTAssertEqual(NERWindowing.windows(count: 10), [0..<10])
        let w = NERWindowing.windows(count: 1200)
        XCTAssertEqual(w.first, 0..<500)
        XCTAssertEqual(w[1].lowerBound, 500 - 64)
        XCTAssertEqual(w.last?.upperBound, 1200)
    }
}
