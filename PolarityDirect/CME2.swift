//
//  CME2.swift
//  PolarityDirect
//
//  Created by Wayne Russell on 2026-01-16.
//

import Foundation

enum CME2 {
    // MARK: - Session parameters (MVP defaults)
    // Later: set these from handshake (weakest device wins)
    static var modulusM: UInt64 = 5          // MUST be odd
    static var precisionDigits: Int = 6      // fixed-point scale
    static var sessionMaskKey: UInt64 = 0xC0FFEE_BADC0DE1  // Later: derived from handshake

    // MARK: - Public API

    /// Encode plaintext -> CME2 payload string (safe for wire)
    static func encode(text: String) -> String {
        // 1) bytes -> integer (deterministic)
        let data = Data(text.utf8)

        // MVP: keep it simple and bounded.
        // We pack up to 8 bytes into one UInt64. Longer messages can be chunked later (MVP-5+).
        guard data.count <= 8 else {
            return "CME2|ERR=TOO_LONG|max=8|len=\(data.count)"
        }

        let x = u64FromBytesBE(data) // meaning as UInt64

        // 2) Optional: fixed-point "radius scaling" slot
        // For MVP-4, we keep it integer-only to stay perfectly reversible on-device.
        // If you want your radius step here later, you’ll compute rScaled deterministically, then set x = rScaled.
        let scaled = x

        // 3) Modular split: scaled = m*q + rem
        let m = modulusM
        let rem = scaled % m
        let q = scaled / m

        // 4) Mask the quotient so observers can't trivially rebuild scaled
        let maskedQ = q ^ sessionMaskKey

        // 5) Simple integrity check (not crypto): 32-bit checksum of original bytes
        let c32 = fnv1a32(data)

        // Wire payload (ASCII safe)
        // Note: m & p included for debug now; later you can omit if fixed in-session.
        return "CME2|m=\(m)|p=\(precisionDigits)|rem=\(rem)|q=\(toHex64(maskedQ))|c=\(toHex32(c32))"
    }

    /// Decode CME2 payload -> recovered plaintext + pass/fail
    static func decode(payload: String) -> (text: String, pass: Bool)? {
        guard payload.hasPrefix("CME2|") else { return nil }
        if payload.contains("ERR=") { return (payload, false) }

        let fields = parseFields(payload)

        guard
            let mStr = fields["m"], let m = UInt64(mStr),
            let remStr = fields["rem"], let rem = UInt64(remStr),
            let qHex = fields["q"], let maskedQ = u64FromHex(qHex),
            let cHex = fields["c"], let expectedC32 = u32FromHex(cHex)
        else {
            return ("CME2|ERR=BAD_FIELDS", false)
        }

        let q = maskedQ ^ sessionMaskKey
        let scaled = m &* q &+ rem

        // Recover bytes (MVP: we don't know original length, so strip leading zeros)
        let bytes = bytesFromU64BE(scaled)
        let trimmed = trimLeadingZeros(bytes)

        guard let text = String(data: trimmed, encoding: .utf8) else {
            return ("CME2|ERR=BAD_UTF8", false)
        }

        let actualC32 = fnv1a32(trimmed)
        return (text, actualC32 == expectedC32)
    }

    // MARK: - Helpers

    private static func parseFields(_ s: String) -> [String: String] {
        // "CME2|k=v|k=v" -> dictionary
        var out: [String: String] = [:]
        let parts = s.split(separator: "|")
        for part in parts {
            if part == "CME2" { continue }
            if let eq = part.firstIndex(of: "=") {
                let k = String(part[..<eq])
                let v = String(part[part.index(after: eq)...])
                out[k] = v
            }
        }
        return out
    }

    private static func u64FromBytesBE(_ data: Data) -> UInt64 {
        var x: UInt64 = 0
        for b in data {
            x = (x << 8) | UInt64(b)
        }
        return x
    }

    private static func bytesFromU64BE(_ x: UInt64) -> Data {
        var out = Data(count: 8)
        out[0] = UInt8((x >> 56) & 0xFF)
        out[1] = UInt8((x >> 48) & 0xFF)
        out[2] = UInt8((x >> 40) & 0xFF)
        out[3] = UInt8((x >> 32) & 0xFF)
        out[4] = UInt8((x >> 24) & 0xFF)
        out[5] = UInt8((x >> 16) & 0xFF)
        out[6] = UInt8((x >> 8) & 0xFF)
        out[7] = UInt8(x & 0xFF)
        return out
    }

    private static func trimLeadingZeros(_ data: Data) -> Data {
        var i = 0
        while i < data.count && data[i] == 0 { i += 1 }
        return data.suffix(from: i)
    }

    // FNV-1a 32-bit (simple integrity, not crypto)
    private static func fnv1a32(_ data: Data) -> UInt32 {
        var hash: UInt32 = 2166136261
        for b in data {
            hash ^= UInt32(b)
            hash = hash &* 16777619
        }
        return hash
    }

    private static func toHex64(_ x: UInt64) -> String {
        String(format: "%016llx", x)
    }

    private static func toHex32(_ x: UInt32) -> String {
        String(format: "%08x", x)
    }

    private static func u64FromHex(_ s: String) -> UInt64? {
        UInt64(s, radix: 16)
    }

    private static func u32FromHex(_ s: String) -> UInt32? {
        UInt32(s, radix: 16)
    }
}
