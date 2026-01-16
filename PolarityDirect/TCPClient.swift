//
//  TCPClient.swift
//  PolarityDirect
//
//  MVP Primitive 3/4 client: framed HELLO/WELCOME handshake + framed TEXT messages
//

import Foundation
import Network
import Combine

final class TCPClient: ObservableObject {

    // MARK: - Published UI state

    @Published var status: String = "idle"
    @Published var messages: [ChatMsg] = []

    // Handshake state
    @Published var handshakeOK: Bool = false
    @Published var sessionID: String = ""

    // MARK: - Private

    private var conn: NWConnection?
    private var rxBuffer = Data()

    // Must match server expectations
    private let deviceLabel = "iPhone"
    private let protoVer   = "P2"

    // MARK: - Connect / Disconnect

    func connect(host: String, port: UInt16) {
        // Reset local state every time we connect
        DispatchQueue.main.async {
            self.status = "connecting..."
            self.messages.removeAll()
            self.handshakeOK = false
            self.sessionID = ""
        }
        rxBuffer.removeAll()

        let nwHost = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            DispatchQueue.main.async { self.status = "bad port" }
            return
        }

        let c = NWConnection(host: nwHost, port: nwPort, using: .tcp)
        self.conn = c

        c.stateUpdateHandler = { [weak self] st in
            guard let self else { return }
            switch st {
            case .ready:
                DispatchQueue.main.async { self.status = "connected ✅" }
                self.startReceiveLoop()
                self.sendHello()

            case .failed(let err):
                DispatchQueue.main.async { self.status = "failed: \(err)" }
                self.cleanup()

            case .waiting(let err):
                DispatchQueue.main.async { self.status = "waiting: \(err)" }

            case .cancelled:
                DispatchQueue.main.async { self.status = "cancelled" }
                self.cleanup()

            default:
                break
            }
        }

        c.start(queue: .global(qos: .userInitiated))
    }

    func disconnect() {
        conn?.cancel()
        DispatchQueue.main.async {
            self.status = "idle"
            self.handshakeOK = false
            self.sessionID = ""
        }
        cleanup()
    }

    private func cleanup() {
        conn = nil
        rxBuffer.removeAll()
    }

    // MARK: - Send

    private func sendLine(_ line: String) {
        guard let c = conn else { return }
        let payload = (line + "\n").data(using: .utf8) ?? Data()
        c.send(content: payload, completion: .contentProcessed { _ in })
    }

    private func sendHello() {
        // Only send HELLO if we are connected and handshake is NOT done yet
        guard conn != nil, !handshakeOK else { return }

        let line = CMEFrame.makeHello(device: deviceLabel, ver: protoVer)
        sendLine(line)

        DispatchQueue.main.async {
            self.messages.append(ChatMsg(dir: "TX", text: "HELLO"))
        }
        print("[iPhone] TX: \(line)")
    }

    @discardableResult
    func sendText(_ text: String) -> Bool {
        guard conn != nil else {
            DispatchQueue.main.async { self.status = "not connected" }
            print("[iPhone] send blocked: no connection")
            return false
        }

        guard handshakeOK else {
            DispatchQueue.main.async { self.status = "blocked: no handshake" }
            print("[iPhone] blocked: tried TEXT before WELCOME")
            return false
        }

        // Encode your payload (MVP4 can swap this to CME2 later)
        let encoded = CMECodec.encodeU64Safe6(text)
        let frame = CMEFrame.makeText(encoded)

        sendLine(frame)

        DispatchQueue.main.async {
            self.messages.append(ChatMsg(dir: "TX", text: text))
            self.status = "sent ✅"
        }

        print("[iPhone] TX frame: \(frame)")
        print("[iPhone] TX plain: \(text)")
        print("[iPhone] TX encoded: \(encoded)")
        return true
    }

    // MARK: - Receive loop (newline framed)

    private func startReceiveLoop() {
        guard let c = conn else { return }

        c.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, err in
            guard let self else { return }

            if let err {
                DispatchQueue.main.async { self.status = "rx error: \(err)" }
                print("[iPhone] RX error: \(err)")
                self.disconnect()
                return
            }

            if let data, !data.isEmpty {
                self.rxBuffer.append(data)
                self.drainLinesFromBuffer()
            }

            if isComplete {
                DispatchQueue.main.async { self.status = "server closed" }
                print("[iPhone] server closed")
                self.disconnect()
                return
            }

            // Continue loop
            self.startReceiveLoop()
        }
    }

    private func drainLinesFromBuffer() {
        while true {
            guard let nl = rxBuffer.firstIndex(of: 0x0A) else { break } // '\n'
            let lineData = rxBuffer[..<nl]
            rxBuffer.removeSubrange(...nl) // remove through newline

            guard let line = String(data: lineData, encoding: .utf8) else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            handleLine(trimmed)
        }
    }

    private func handleLine(_ trimmed: String) {
        print("[iPhone] RAW IN: \(trimmed)")

        if trimmed.contains("WELCOME") {
            // try to extract token from either "CME1|WELCOME|token" OR "WELCOME token"
            let token: String = {
                if trimmed.contains("|") {
                    let parts = trimmed.split(separator: "|", omittingEmptySubsequences: false)
                    return parts.count >= 3 ? String(parts[2]) : ""
                } else {
                    // "WELCOME abc123"
                    let parts = trimmed.split(separator: "|", omittingEmptySubsequences: true)
                    return parts.count >= 2 ? String(parts[1]) : ""
                }
            }()

            DispatchQueue.main.async {
                if !token.isEmpty { self.sessionID = token }
                self.handshakeOK = true
                self.status = "handshake ✅"
            }
            print("[iPhone] FALLBACK WELCOME -> handshakeOK=true token=\(token)")
        }
        
        let (t, payload, raw) = CMEFrame.parse(trimmed)
        print("[iPhone] PARSED t=\(t) payload=\(payload) raw=\(raw)")

        switch t {
        case "ACK":
            DispatchQueue.main.async {
                self.messages.append(ChatMsg(dir: "RX", text: "ACK"))
            }

        case "HELLO_ACK":
            DispatchQueue.main.async {
                self.messages.append(ChatMsg(dir: "RX", text: raw))
            }

        case "WELCOME":
            DispatchQueue.main.async {
                self.sessionID = payload
                self.handshakeOK = true
                self.status = "handshake ✅"
                self.messages.append(ChatMsg(dir: "RX", text: "WELCOME \(payload)"))
            }
            print("[iPhone] handshakeOK set true, sessionID=\(payload)")

        case "TEXT":
            let decoded = CMECodec.decodePayload(payload)
            DispatchQueue.main.async {
                self.messages.append(ChatMsg(dir: "RX", text: "Samsung: \(decoded)"))
            }

        default:
            DispatchQueue.main.async {
                self.messages.append(ChatMsg(dir: "RX", text: raw))
            }
        }
    }
}
