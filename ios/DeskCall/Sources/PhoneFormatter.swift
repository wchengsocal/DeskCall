import Foundation

/// Minimal, dependency-free formatting. The backend does authoritative E.164
/// parsing, so this only has to make typing comfortable.
enum PhoneFormatter {
    static func digits(_ input: String) -> String {
        input.filter { $0.isNumber }
    }

    /// Formats as a US number while typing; leaves anything with a "+" alone.
    static func formatForDisplay(_ input: String) -> String {
        if input.hasPrefix("+") { return input }
        let d = digits(input)
        guard d.count <= 10 else { return input }
        switch d.count {
        case 0...3:
            return d
        case 4...6:
            return "(\(d.prefix(3))) \(d.dropFirst(3))"
        default:
            let area = d.prefix(3)
            let exchange = d.dropFirst(3).prefix(3)
            let line = d.dropFirst(6)
            return "(\(area)) \(exchange)-\(line)"
        }
    }

    /// Pretty-prints a canonical E.164 number coming back from the server.
    static func prettyE164(_ e164: String) -> String {
        let d = digits(e164)
        guard e164.hasPrefix("+1"), d.count == 11 else { return e164 }
        let area = d.dropFirst().prefix(3)
        let exchange = d.dropFirst(4).prefix(3)
        let line = d.dropFirst(7)
        return "(\(area)) \(exchange)-\(line)"
    }

    static func asCallKitNumber(_ e164: String) -> Int64? {
        Int64(digits(e164))
    }
}
