import XCTest
@testable import VeilCore

final class TwinPersonaTests: XCTestCase {
    func testPresetPrimaryIdentity() {
        let m = TwinMap(salt: 1, persona: .alexRivera)
        XCTAssertEqual(m.twin(for: "Jane", label: .givenName), "Alex")
        XCTAssertEqual(m.twin(for: "Doe", label: .surname), "Rivera")
        XCTAssertEqual(m.twin(for: "jane@acme.com", label: .email), "alex.rivera@example.com")
        XCTAssertEqual(m.twin(for: "212-867-5309", label: .phone), "415-555-0100")
        XCTAssertEqual(m.twin(for: "Jane", label: .givenName), "Alex") // stable
    }

    func testSecondPersonFallsBackAndStaysBijective() {
        let m = TwinMap(salt: 1, persona: .alexRivera)
        let a = m.twin(for: "Jane", label: .givenName), b = m.twin(for: "Maria", label: .givenName)
        XCTAssertEqual(a, "Alex"); XCTAssertNotEqual(b, "Alex")
        XCTAssertEqual(m.original(forTwin: b), "Maria")
    }

    func testRandomPersonaDeterministicPerSeed() {
        XCTAssertEqual(TwinPersona.random(seed: 9), TwinPersona.random(seed: 9))
        XCTAssertTrue(TwinPersona.random(seed: 9).isRandom)
    }

    func testClearKeepsOrReplacesPersona() {
        let m = TwinMap(salt: 1, persona: .alexRivera)
        _ = m.twin(for: "Jane", label: .givenName)
        m.clear()
        XCTAssertEqual(m.count, 0); XCTAssertEqual(m.persona, .alexRivera)
        m.clear(persona: .samMorgan)
        XCTAssertEqual(m.twin(for: "Jane", label: .givenName), "Sam")
    }
}
