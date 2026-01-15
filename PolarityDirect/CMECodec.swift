import Foundation

enum CMECodec {
    static let phi = 1.618033988749895
    static let r0Prefix = "R0:"
    static let r1Prefix = "R1:"

    // MARK: - Public

    static func encode(_ text: String, layers: Int) -> String {
        if layers <= 0 { return r0Encode(text) }
        return r1Encode(text)
    }

    static func decode(_ payload: String) -> String {
        if payload.hasPrefix(r0Prefix) { return r0Decode(payload) }
        if payload.hasPrefix(r1Prefix) { return r1Decode(payload) }
        return payload // fail-open for now
    }

    // MARK: - R0

    private static func r0Encode(_ text: String) -> String {
        let A = textToU64(text)
        let r0 = (A > 0) ? sqrt(Double(A) / (4.0 * Double.pi)) : 0.0
        return r0Prefix + packF64B64LittleEndian(r0)
    }

    private static func r0Decode(_ payload: String) -> String {
        let b64 = String(payload.dropFirst(r0Prefix.count))
        guard let r0: Double = unpackF64B64LittleEndian(b64) else { return payload }
        let areaD = (4.0 * Double.pi) * (r0 * r0)
        let A = UInt64(areaD.rounded())
        return u64ToText(A)
    }

    // MARK: - R1 (demo step)

    private static func r1Encode(_ text: String) -> String {
        let A = textToU64(text)
        let r0 = (A > 0) ? sqrt(Double(A) / (4.0 * Double.pi)) : 0.0
        let r1 = r0 / phi
        return r1Prefix + packF64B64LittleEndian(r1)
    }

    private static func r1Decode(_ payload: String) -> String {
        let b64 = String(payload.dropFirst(r1Prefix.count))
        guard let r1: Double = unpackF64B64LittleEndian(b64) else { return payload }
        let r0 = r1 * phi
        let areaD = (4.0 * Double.pi) * (r0 * r0)
        let A = UInt64(areaD.rounded())
        return u64ToText(A)
    }

    // MARK: - 8-byte meaning helpers (match Python)

    // Python: int.from_bytes(b, "big", signed=False)
    private static func textToU64(_ text: String) -> UInt64 {
        var b = Array(text.utf8.prefix(8))
        while b.count < 8 { b.append(0) }

        var x: UInt64 = 0
        for byte in b {
            x = (x << 8) | UInt64(byte)
        }
        return x
    }

    private static func u64ToText(_ x: UInt64) -> String {
        var v = x
        let data = Data(bytes: &v, count: 8).reversed()
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .controlCharacters)
    }

    // MARK: - Double <-> base64 (match Python struct.pack("<d", x))

    private static func packF64B64LittleEndian(_ x: Double) -> String {
        let u = x.bitPattern.littleEndian
        var v = u
        let data = Data(bytes: &v, count: 8)
        return data.base64EncodedString()
    }

    private static func unpackF64B64LittleEndian(_ b64: String) -> Double? {
        guard let data = Data(base64Encoded: b64), data.count == 8 else { return nil }
        let u: UInt64 = data.withUnsafeBytes { ptr in
            ptr.load(as: UInt64.self)
        }
        return Double(bitPattern: UInt64(littleEndian: u))
    }
}//
//  CMECodec.swift
//  PolarityDirect
//
//  Created by Wayne Russell on 2026-01-15.
//

