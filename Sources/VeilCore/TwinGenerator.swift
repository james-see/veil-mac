import Foundation

/// Produces format-preserving synthetic "twins". Deterministic per (label, original, salt) so the
/// same original always gets the same twin within a session. Twins are chosen to be obviously
/// non-real where a reserved range exists (555-01xx phones, example.* domains, 9xx SSN areas,
/// documented test card BINs) so a twin is never someone's real identifier.
public struct TwinGenerator: Sendable {
    public let salt: UInt64
    /// Optional session persona: attempt 0 for name/email/phone/address labels yields the persona's value.
    public let persona: TwinPersona?
    public init(salt: UInt64, persona: TwinPersona? = nil) { self.salt = salt; self.persona = persona }

    static let givenNames = ["Avery", "Jordan", "Morgan", "Riley", "Casey", "Quinn", "Rowan", "Harper", "Emerson", "Sawyer",
                             "Finley", "Reese", "Dakota", "Skyler", "Parker", "Hayden", "Blake", "Elliot", "Marlowe", "Teagan"]
    static let surnames = ["Hollis", "Vance", "Whitaker", "Calloway", "Prescott", "Lockhart", "Ellery", "Fairbanks", "Sterling",
                           "Ashby", "Kendrick", "Radcliffe", "Thorne", "Winslow", "Bramwell", "Holloway", "Merriman", "Pembrook"]
    static let streets = ["Maple Grove Ave", "Juniper Ln", "Harbor View Rd", "Willow Bend Dr", "Cedar Hollow St", "Lark Rise Ct"]
    static let cities = ["Fairview", "Riverton", "Lakewood", "Brookfield", "Ashford", "Kingsport"]
    static let states = ["Oregon", "Vermont", "Nebraska", "Delaware", "Montana", "Maine"]

    /// FNV-1a over the label + original + salt, then splitmix to spread bits.
    func seed(_ label: PiiLabel, _ original: String, attempt: Int) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325 ^ salt
        for b in "\(label.rawValue)|\(attempt)|\(original)".utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        h = (h ^ (h >> 30)) &* 0xbf58476d1ce4e5b9; h = (h ^ (h >> 27)) &* 0x94d049bb133111eb
        return h ^ (h >> 31)
    }

    public func twin(for original: String, label: PiiLabel, attempt: Int = 0) -> String {
        if attempt == 0, let p = persona, let t = personaTwin(p, original, label) { return t }
        var rng = SplitMix(state: seed(label, original, attempt: attempt))
        switch label {
        case .givenName: return matchCase(Self.givenNames.pick(&rng), like: original)
        case .surname: return matchCase(Self.surnames.pick(&rng), like: original)
        case .email:
            return "\(Self.givenNames.pick(&rng).lowercased()).\(Self.surnames.pick(&rng).lowercased())\(rng.next() % 100)@example.com"
        case .url: return "https://example.org/\(String(rng.next(), radix: 36).prefix(8))"
        case .phone: let d = phoneDigits(original, &rng); return shapeDigits(original, fixed: d)
        case .ssn:
            // Area 9xx is never issued → never a real SSN.
            var d = "9" + (0..<8).map { _ in String(rng.next() % 10) }.joined()
            if d.hasSuffix("0000") { d = String(d.dropLast()) + "1" }
            return shapeDigits(original, fixed: d)
        case .creditCard:
            let d = testCard(length: original.filter(\.isASCIIDigitChar).count, &rng)
            return shapeDigits(original, fixed: d)
        case .ipAddress:
            if original.contains(":") { return "2001:db8::\(String(rng.next() % 0xffff, radix: 16))" } // RFC 3849
            return "192.0.2.\(rng.next() % 254 + 1)" // RFC 5737 TEST-NET-1
        case .streetName: return Self.streets.pick(&rng)
        case .city: return Self.cities.pick(&rng)
        case .state: return Self.states.pick(&rng)
        default:
            // Numeric/alnum IDs (TAX_ID, BANK_ACCOUNT, ROUTING, PASSPORT, DL, GOV ID, BUILDING_NUMBER, ZIP, SECONDARY):
            // preserve shape — digits→digits, letters→letters (case kept), punctuation kept.
            return shapeAll(original, &rng)
        }
    }

    func personaTwin(_ p: TwinPersona, _ original: String, _ label: PiiLabel) -> String? {
        switch label {
        case .givenName: return matchCase(p.givenName, like: original)
        case .surname: return matchCase(p.surname, like: original)
        case .email: return p.email
        case .phone:
            let n = original.filter(\.isASCIIDigitChar).count, ten = p.phoneDigits
            guard n == 10 || n == 11 else { return nil }
            return shapeDigits(original, fixed: n == 11 ? "1" + ten : ten)
        case .streetName: return p.street
        case .city: return p.city
        case .state: return p.state
        default: return nil
        }
    }

    func phoneDigits(_ original: String, _ rng: inout SplitMix) -> String {
        let n = original.filter(\.isASCIIDigitChar).count
        let core = "555" + "01" + String(format: "%02d", Int(rng.next() % 100))   // 555-01xx: fictional block
        let area = String(format: "%03d", 200 + Int(rng.next() % 700))
        let ten = area + core
        return n == 11 ? "1" + ten : n == 10 ? ten : String((ten + ten).prefix(max(n, 1)))
    }

    func testCard(length: Int, _ rng: inout SplitMix) -> String {
        var body = "400000" // Visa test BIN family
        while body.count < max(length, 13) - 1 { body += String(rng.next() % 10) }
        for check in 0...9 where isLuhnValid(body + String(check)) { return body + String(check) }
        return body + "0"
    }

    /// Lay `fixed` digits into the original's separator pattern.
    func shapeDigits(_ original: String, fixed: String) -> String {
        var it = fixed.makeIterator(), out = ""
        for c in original { out.append(c.isASCIIDigitChar ? (it.next() ?? "0") : c) }
        return out
    }

    func shapeAll(_ original: String, _ rng: inout SplitMix) -> String {
        let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
        return String(original.map { c -> Character in
            if c.isASCIIDigitChar { return Character(String(rng.next() % 10)) }
            if c.isLetter { let l = letters.pick(&rng); return c.isLowercase ? Character(l.lowercased()) : l }
            return c
        })
    }

    func matchCase(_ s: String, like o: String) -> String {
        if o == o.uppercased() && o.count > 1 { return s.uppercased() }
        if o == o.lowercased() { return s.lowercased() }
        return s
    }
}

struct SplitMix {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state; z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9; z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

extension Array {
    func pick(_ rng: inout SplitMix) -> Element { self[Int(rng.next() % UInt64(count))] }
}
