import XCTest
@testable import VeilCore

final class TwinMapTests: XCTestCase {
    func testConsistentAndBijective() {
        let m = TwinMap(salt: 42)
        let a = m.twin(for: "Jane", label: .givenName)
        XCTAssertEqual(a, m.twin(for: "Jane", label: .givenName))
        XCTAssertNotEqual(a, "Jane")
        let b = m.twin(for: "Maria", label: .givenName)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(m.original(forTwin: a), "Jane")
        XCTAssertEqual(m.count, 2)
    }

    func testDeterministicPerSalt() {
        XCTAssertEqual(TwinMap(salt: 7).twin(for: "x@y.com", label: .email), TwinMap(salt: 7).twin(for: "x@y.com", label: .email))
    }

    func testFormatPreservingTwins() {
        let m = TwinMap(salt: 1)
        let ssn = m.twin(for: "123-45-6789", label: .ssn)
        XCTAssertTrue(ssn.range(of: #"^9\d{2}-\d{2}-\d{4}$"#, options: .regularExpression) != nil, ssn)
        let card = m.twin(for: "4111 1111 1111 1111", label: .creditCard)
        XCTAssertTrue(isLuhnValid(card.filter(\.isASCIIDigitChar)))
        XCTAssertEqual(card.count, 19)
        XCTAssertTrue(m.twin(for: "(415) 555-2671", label: .phone).contains("555-01"))
        XCTAssertTrue(m.twin(for: "a@b.com", label: .email).hasSuffix("@example.com"))
        XCTAssertTrue(m.twin(for: "10.1.2.3", label: .ipAddress).hasPrefix("192.0.2."))
    }

    func testRestoreRoundTripAndLongestFirst() {
        let m = TwinMap(salt: 3)
        let first = m.twin(for: "Jane", label: .givenName)
        let email = m.twin(for: "jane@acme.com", label: .email)
        let text = "Dear \(first), we emailed \(email)."
        XCTAssertEqual(m.restore(text), "Dear Jane, we emailed jane@acme.com.")
    }

    func testClear() {
        let m = TwinMap(salt: 3)
        let t = m.twin(for: "Jane", label: .givenName)
        m.clear()
        XCTAssertEqual(m.count, 0)
        XCTAssertEqual(m.restore(t), t)
    }

    func testCloakUncloakEndToEndRegexOnly() async throws {
        let c = Cloaker(map: TwinMap(salt: 9))
        let raw = "Email bob@corp.com, SSN 123-45-6789, again bob@corp.com"
        let r = try await c.cloak(raw)
        XCTAssertFalse(r.text.contains("bob@corp.com"))
        XCTAssertFalse(r.text.contains("123-45-6789"))
        XCTAssertEqual(r.replaced, 3)
        XCTAssertEqual(c.map.count, 2) // same email → same twin
        XCTAssertEqual(c.uncloak(r.text), raw)
    }

    struct StubNER: NERDetector {
        func detect(_ text: String) async throws -> [Span] {
            // Find "Ann" in the masked text and report it as a given name.
            let r = (text as NSString).range(of: "Ann")
            guard r.location != NSNotFound else { return [] }
            return [Span(start: r.location, end: r.location + r.length, label: .givenName, score: 0.9, source: .ner, text: "Ann")]
        }
    }

    func testCloakWithNERProjectsThroughPremask() async throws {
        let c = Cloaker(map: TwinMap(salt: 11), ner: StubNER())
        let raw = "SSN 123-45-6789 belongs to Ann"
        let r = try await c.cloak(raw)
        XCTAssertFalse(r.text.contains("Ann"))
        XCTAssertEqual(c.uncloak(r.text), raw)
    }
}
