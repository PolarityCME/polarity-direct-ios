//
//  CMEFrame.swift
//  PolarityDirect
//
//  Created by Wayne Russell on 2026-01-10.
//
import Foundation

struct CMEFrame {

    // MARK: - Build frames

    static func makeHello(device: String, ver: String) -> String {
        // CME1|HELLO|iPhone|P2
        return "CME1|HELLO|\(device)|\(ver)"
    }

    static func makeText(_ text: String) -> String {
        // CME1|TEXT|hello world
        return "CME1|TEXT|\(text)"
    }

    // MARK: - Parse frames

    // Returns: (type, payload, rawLine)
    static func parse(_ line: String) -> (String, String, String) {
        let raw = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Transport ACK
        if raw == "ACK" || raw.hasPrefix("CME1|ACK") {
            return ("ACK", "", raw)
        }

        // Plain text fallback
        if !raw.hasPrefix("CME1|") {
            return ("TEXT", raw, raw)
        }

        // CME1|TYPE|payload...
        let parts = raw.split(separator: "|", omittingEmptySubsequences: false)
        let type = parts.count > 1 ? String(parts[1]) : "UNKNOWN"
        let payload = parts.count > 2
            ? parts.dropFirst(2).joined(separator: "|")
            : ""

        return (type, payload, raw)
    }
}
