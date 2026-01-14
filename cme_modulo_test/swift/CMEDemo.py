import Foundation

// MARK: - Utilities

// Integer sqrt for UInt64 (safe because sqrt(2^64-1) < 2^32, so r*r fits in UInt64)
func isqrt(_ x: UInt64) -> UInt64 {
    var r = UInt64(Double(x).squareRoot())
    while (r &+ 1) != 0 && (r &+ 1) * (r &+ 1) <= x { r &+= 1 }
    while r * r > x { r &-= 1 }
    return r
}

// Multiplicative inverse modulo 2^64 for odd a.
// Uses 2-adic Newton iteration: inv = inv * (2 - a*inv) mod 2^64
func modInverseOdd(_ a: UInt64) -> UInt64 {
    precondition(a & 1 == 1, "a must be odd for inverse mod 2^64")
    var inv = a
    // 6 iterations are enough to converge to 64-bit inverse
    for _ in 0..<6 {
        inv = inv &* (2 &- (a &* inv))
    }
    return inv
}

// MARK: - CME Layering (affine transforms in Z/2^64Z)

typealias Layer = (a: UInt64, b: UInt64)

func forwardLayers(_ x: UInt64, layers: [Layer]) -> UInt64 {
    var v = x
    for (a, b) in layers {
        precondition(a & 1 == 1, "Layer multiplier a must be odd")
        v = (a &* v) &+ b  // wraparound is mod 2^64
    }
    return v
}

func inverseLayers(_ x: UInt64, layers: [Layer]) -> UInt64 {
    var v = x
    for (a, b) in layers.reversed() {
        let ainv = modInverseOdd(a)
        v = ainv &* (v &- b) // v = a^{-1} (v - b) mod 2^64
    }
    return v
}

// MARK: - Packing 8 ASCII bytes into UInt64 (big-endian)

func pack8(_ s: String) -> UInt64 {
    let bytes = Array(s.utf8)
    precondition(bytes.count == 8, "Need exactly 8 bytes for a 64-bit register demo")
    var x: UInt64 = 0
    for b in bytes {
        x = (x << 8) | UInt64(b)
    }
    return x
}

func unpack8(_ x: UInt64) -> String {
    var bytes = [UInt8](repeating: 0, count: 8)
    for i in 0..<8 {
        let shift = UInt64((7 - i) * 8)
        bytes[i] = UInt8((x >> shift) & 0xFF)
    }
    return String(bytes: bytes, encoding: .utf8) ?? "<non-utf8>"
}

// MARK: - Demo

let text = "Good day" // 8 bytes exactly
let A = pack8(text)
print("Original text: \(text)")
print(String(format: "A (hex) = 0x%016llX", A))

// Geometry step (reversible only with remainder)
let r0 = isqrt(A)
let rem = A &- (r0 &* r0)
print("r0 = \(r0)")
print("rem = \(rem)   (A = r0*r0 + rem)")

// Example layers (hardcoded for demo). In reality: derived from session keys / handshake.
let layers: [Layer] = [
    (a: 0xD6E8FEB86659FD93, b: 0xA5A5A5A5A5A5A5A5), // odd a
    (a: 0x9E3779B97F4A7C15, b: 0x0123456789ABCDEF), // odd a
    (a: 0xBF58476D1CE4E5B9, b: 0xF0F0F0F0F0F0F0F0)  // odd a
]

// "Secure" transport values (meaningless to observers)
let rL   = forwardLayers(r0, layers: layers)
let remL = forwardLayers(rem, layers: layers)

print(String(format: "Transmit rL   = 0x%016llX", rL))
print(String(format: "Transmit remL = 0x%016llX", remL))

// Receiver reverses
let r0_recv   = inverseLayers(rL, layers: layers)
let rem_recv  = inverseLayers(remL, layers: layers)
let A_recv    = (r0_recv &* r0_recv) &+ rem_recv
let text_recv = unpack8(A_recv)

print("Recovered r0  = \(r0_recv)")
print("Recovered rem = \(rem_recv)")
print(String(format: "Recovered A (hex) = 0x%016llX", A_recv))
print("Recovered text: \(text_recv)")

precondition(A_recv == A, "FAIL: A mismatch")
precondition(text_recv == text, "FAIL: text mismatch")
print("✅ PASS: End-to-end reconstruction works")
