import Foundation

/// A session persona: the "primary" twin identity. The first distinct person/email/phone/address seen in a
/// session maps onto the persona's fields; further distinct originals fall back to the salted pools so the
/// map stays bijective. Presets are fixed; `.random(seed:)` rolls one from the pools once per session.
public struct TwinPersona: Equatable, Codable, Sendable, Identifiable {
    public let id: String
    public let profileName: String
    public let givenName: String
    public let surname: String
    public let emailDomain: String
    public let phoneArea: String       // 3 digits; local part is always the fictional 555-01xx block
    public let phoneLine: String       // 2 digits → 555-01<line>
    public let street: String
    public let city: String
    public let state: String

    public var isRandom: Bool { id == Self.randomId }
    public var email: String { "\(givenName.lowercased()).\(surname.lowercased())@\(emailDomain)" }
    public var phone: String { "(\(phoneArea)) 555-01\(phoneLine)" }
    public var phoneDigits: String { phoneArea + "55501" + phoneLine }
    public var fullName: String { "\(givenName) \(surname)" }

    public static let randomId = "random"

    public static let alexRivera = TwinPersona(id: "alex-rivera", profileName: "Alex Rivera", givenName: "Alex", surname: "Rivera",
        emailDomain: "example.com", phoneArea: "415", phoneLine: "00", street: "Maple Grove Ave", city: "Fairview", state: "Oregon")
    public static let samMorgan = TwinPersona(id: "sam-morgan", profileName: "Sam Morgan", givenName: "Sam", surname: "Morgan",
        emailDomain: "example.net", phoneArea: "312", phoneLine: "42", street: "Juniper Ln", city: "Riverton", state: "Vermont")
    public static let presets: [TwinPersona] = [alexRivera, samMorgan]

    /// Roll a random persona from the generator pools. Deterministic per seed.
    public static func random(seed: UInt64) -> TwinPersona {
        var rng = SplitMix(state: seed)
        let g = TwinGenerator.givenNames.pick(&rng), s = TwinGenerator.surnames.pick(&rng)
        return TwinPersona(id: randomId, profileName: "Random", givenName: g, surname: s,
                           emailDomain: ["example.com", "example.org", "example.net"].pick(&rng),
                           phoneArea: String(format: "%03d", 200 + Int(rng.next() % 700)),
                           phoneLine: String(format: "%02d", Int(rng.next() % 100)),
                           street: TwinGenerator.streets.pick(&rng), city: TwinGenerator.cities.pick(&rng),
                           state: TwinGenerator.states.pick(&rng))
    }
}
