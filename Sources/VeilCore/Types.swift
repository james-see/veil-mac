import Foundation

/// Every entity class Rampart's heuristics and NER head can emit (mirrors rampart/src/types.ts),
/// plus `PHONE` from Veil's extra deterministic phone rule.
public enum PiiLabel: String, CaseIterable, Codable, Sendable {
    // Structured (heuristic, premasked before the model)
    case ssn = "SSN", creditCard = "CREDIT_CARD", ipAddress = "IP_ADDRESS"
    // Contextual (NER)
    case givenName = "GIVEN_NAME", surname = "SURNAME", email = "EMAIL", phone = "PHONE", url = "URL"
    case taxId = "TAX_ID", bankAccount = "BANK_ACCOUNT", routingNumber = "ROUTING_NUMBER"
    case governmentId = "GOVERNMENT_ID", passport = "PASSPORT", driversLicense = "DRIVERS_LICENSE"
    // Address components (NER)
    case buildingNumber = "BUILDING_NUMBER", streetName = "STREET_NAME", secondaryAddress = "SECONDARY_ADDRESS"
    case city = "CITY", state = "STATE", zipCode = "ZIP_CODE"

    /// Rampart's default keep-set: coarse location is left in place (default-deny for everything else).
    public static let defaultKeep: Set<PiiLabel> = [.city, .state, .zipCode]
}

public enum SpanSource: String, Codable, Sendable { case heuristic, ner }

/// A detected span. Offsets are UTF-16 offsets into the raw string (NSString / NSRange space).
public struct Span: Equatable, Sendable {
    public var start: Int
    public var end: Int
    public var label: PiiLabel
    public var score: Double
    public var source: SpanSource
    public var text: String

    public init(start: Int, end: Int, label: PiiLabel, score: Double, source: SpanSource, text: String) {
        self.start = start; self.end = end; self.label = label
        self.score = score; self.source = source; self.text = text
    }
    public var length: Int { end - start }
}

extension String {
    /// Substring by UTF-16 offsets.
    func utf16Slice(_ start: Int, _ end: Int) -> String {
        (self as NSString).substring(with: NSRange(location: start, length: end - start))
    }
}
