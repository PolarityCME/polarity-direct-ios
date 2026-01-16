import Foundation

enum Layer64 {
    static let r0Prefix = "R0:"
    static let r1Prefix = "R1:"
    static let u64Prefix = "U64:"

    // MARK: - MVP4: U64 safe-6 encode
    // Takes first 6 UTF-8 bytes, pads to 8 with zeros, base64 encodes 8 bytes.
    static func encodeU64Safe6(_ text: String) -> String {
        var b = Array(text.utf8.prefix(6))              // only 6 bytes
        while b.count < 6 { b.append(0) }               // pad to 6
        b.append(0)                                     // pad to 8 total
        b.append(0)

        let data = Data(b)                              // EXACT 8 bytes
        return u64Prefix + data.base64EncodedString()
    }

    // MARK: - Decode payload (routes by prefix)
    static func decodePayload(_ payload: String) -> String {
        if payload.hasPrefix(u64Prefix) { return decodeU64Safe6(payload) }
        // Keep fail-open for now; we can re-add R0/R1 later without breaking MVP4
        return payload
    }

    // MARK: - U64 safe-6 decode
    // base64 -> 8 bytes -> take first 6 -> show printable
    private static func decodeU64Safe6(_ payload: String) -> String {
        let b64 = String(payload.dropFirst(u64Prefix.count))
        guard let data = Data(base64Encoded: b64), data.count == 8 else { return payload }

        let first6 = data.prefix(6)

        // If bytes are normal UTF-8 letters/numbers, this works.
        // If not (rare), map non-printables to "·" so we *see* something.
        if let s = String(data: first6, encoding: .utf8) {
            return s.trimmingCharacters(in: .controlCharacters)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            return first6.map { byte in
                if byte >= 32 && byte <= 126 {
                    return Character(UnicodeScalar(byte))
                } else {
                    return "·"
                }
            }.reduce("") { $0 + String($1) }
        }
    }
}
