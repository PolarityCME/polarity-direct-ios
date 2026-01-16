import Foundation

enum CMECodec {

    // MARK: - MVP4 U64 Safe6

    static let u64Prefix = "U64:"

    /// Encode up to 6 UTF-8 bytes into an 8-byte "sphere":
    /// [b0 b1 b2 b3 b4 b5 0x00 0x00] then Base64, prefixed with "U64:"
    static func encodeU64Safe6(_ text: String) -> String {
        let bytes6 = Array(text.utf8.prefix(6))
        var buf = [UInt8](repeating: 0, count: 8)
        for i in 0..<bytes6.count { buf[i] = bytes6[i] }

        let data = Data(buf)                     // EXACT 8 bytes
        return u64Prefix + data.base64EncodedString()
    }

    /// Decode "U64:<base64>" -> first 6 bytes -> UTF-8 string, trimming trailing NULs/spaces.
    static func decodePayload(_ payload: String) -> String {
        guard payload.hasPrefix(u64Prefix) else { return payload }

        let b64 = String(payload.dropFirst(u64Prefix.count))
        guard let data = Data(base64Encoded: b64), data.count == 8 else { return payload }

        let first6 = data.prefix(6)

        // Remove trailing 0x00
        let trimmed = first6.reversed().drop(while: { $0 == 0 }).reversed()
        return String(decoding: trimmed, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .controlCharacters)
    }
}
