import Foundation

/// Luhn checksum — gates CREDIT_CARD (rampart/src/validators.ts).
public func isLuhnValid(_ digits: String) -> Bool {
    var sum = 0, double = false
    for ch in digits.reversed() {
        guard var d = ch.wholeNumberValue else { return false }
        if double { d *= 2; if d > 9 { d -= 9 } }
        sum += d; double.toggle()
    }
    return !digits.isEmpty && sum % 10 == 0
}

/// US SSN structural rules: area != 000/666/9xx, group != 00, serial != 0000.
public func isValidSsn(_ digits: String) -> Bool {
    guard digits.count == 9, digits.allSatisfy(\.isASCIIDigitChar) else { return false }
    let a = Array(digits)
    let area = String(a[0..<3]), group = String(a[3..<5]), serial = String(a[5...])
    if area == "000" || area == "666" { return false }
    if Int(area)! >= 900 { return false }
    if group == "00" || serial == "0000" { return false }
    return true
}

/// NANP phone sanity: 10 digits (optionally leading 1), area and exchange don't start with 0/1.
public func isPlausibleNanpPhone(_ digits: String) -> Bool {
    var d = Array(digits)
    if d.count == 11, d.first == "1" { d.removeFirst() }
    guard d.count == 10 else { return false }
    return !"01".contains(d[0]) && !"01".contains(d[3])
}

extension Character {
    var isASCIIDigitChar: Bool { ("0"..."9").contains(self) }
}
