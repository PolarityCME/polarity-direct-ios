import Foundation

enum CMEDemoV3 {

    // MARK: - CME settings (must match Android/Python)
    // We operate in the ring Z/(2^64 Z)
    // Choose an odd multiplier K so it has an inverse mod 2^64.
    private static let K: UInt64 = 0x9E3779B97F4A7C15  // odd
    private static let K_INV: UInt64 = 0xF1DE83E19937733D // inverse of K mod 2^64 (must match Python)

    // Codec marker so receiver knows whether payload is encoded
    private static let PREFIX = "M3:"      // version marker
    private static let SEP = "."           // hex-word separator

    // MARK: - Public API

    static func encode(_ text: String) -> String {
        // If already encoded, don't double-encode
        if text.hasPrefix(PREFIX) { return text }

        let bytes = Array(text.utf8)
        let n = UInt64(bytes.count)

        // Pack as: [len][word0][word1]...
        var words: [UInt64] = [n]
        var i = 0
        while i < bytes.count {
            var w: UInt64 = 0
            for b in 0..<8 {
                let idx = i + b
                if idx < bytes.count {
                    w |= UInt64(bytes[idx]) << (8 * b) // little-endian pack
                }
            }
            words.append(w)
            i += 8
        }

        // Layer 1 transform (invertible mod 2^64) on all data words except length
        // If you want Layer 0 (no transform), set doLayer1 = false.
        let doLayer1 = true
        if doLayer1 {
            for j in 1..<words.count {
                words[j] = words[j] &* K
            }
        }

        // Serialize as hex words
        let hex = words.map { String(format: "%016llx", $0) }.joined(separator: SEP)
        return PREFIX + hex
    }

    static func decode(_ payload: String) -> String {
        guard payload.hasPrefix(PREFIX) else {
            // Not encoded; treat as plain text
            return payload
        }

        let body = String(payload.dropFirst(PREFIX.count))
        let parts = body.split(separator: Character(SEP), omittingEmptySubsequences: true)
        if parts.isEmpty { return "" }

        var words: [UInt64] = []
        words.reserveCapacity(parts.count)

        for p in parts {
            guard let w = UInt64(p, radix: 16) else { return "" }
            words.append(w)
        }
        if words.count < 1 { return "" }

        let n = words[0]
        if n == 0 { return "" }

        // Reverse Layer 1 on data words
        let doLayer1 = true
        if doLayer1 {
            for j in 1..<words.count {
                words[j] = words[j] &* K_INV
            }
        }

        // Unpack bytes
        var out: [UInt8] = []
        out.reserveCapacity(Int(n))

        for j in 1..<words.count {
            let w = words[j]
            for b in 0..<8 {
                if out.count >= Int(n) { break }
                out.append(UInt8((w >> (8 * b)) & 0xFF))
            }
        }

        return String(bytes: out, encoding: .utf8) ?? ""
    }
}
