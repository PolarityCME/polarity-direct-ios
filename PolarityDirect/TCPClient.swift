import Combine
import Foundation
import Network

final class TCPClient: ObservableObject {
    @Published var status: String = "idle"
    @Published var messages: [ChatMsg] = []

    // Primitive-2 state
    @Published var handshakeOK: Bool = false
    @Published var sessionID: String = ""

    private var conn: NWConnection?
    private var rxBuffer = Data()

    // Primitive-2 identifiers (match your server expectations)
    private let deviceLabel = "iPhone"
    private let protoVer = "P2"

    func connect(host: String, port: UInt16) {
        status = "connecting..."
        rxBuffer.removeAll()

        // reset handshake every new connect
        handshakeOK = false
        sessionID = ""

        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let c = NWConnection(host: nwHost, port: nwPort, using: .tcp)
        conn = c

        c.stateUpdateHandler = { [weak self] st in
            DispatchQueue.main.async { self?.status = "state: \(st)" }
            print("[iPhone] state => \(st)")

            if case .ready = st {
                print("[iPhone] READY — starting receive loop + sending HELLO")
                self?.receiveLoop()
                self?.sendHello()
            }
        }

        c.start(queue: .global(qos: .userInitiated))
    }

    func disconnect() {
        conn?.cancel()
        conn = nil
        DispatchQueue.main.async {
            self.status = "idle"
            self.handshakeOK = false
            self.sessionID = ""
        }
    }

    // ---- Primitive-2: HELLO ----
    private func sendHello() {
        guard let c = conn, !handshakeOK else { return }

        // Your project should already include CMEMessage.makeHello(...)
        // If not, tell me and I’ll give you the tiny CMEMessage helper.
        let payloadStr = CMEFrame.makeHello(device: deviceLabel, ver: protoVer)
        let payload = (payloadStr + "\n").data(using: .utf8)!

        c.send(content: payload, completion: .contentProcessed { err in
            if let err = err {
                print("[iPhone] HELLO send error: \(err)")
            } else {
                print("[iPhone] HELLO sent")
            }
        })
    }

    // ---- Primitive-2: TEXT (blocked until WELCOME) ----
    @discardableResult
    func sendText(_ text: String) -> Bool {
        guard let c = conn else {
            DispatchQueue.main.async { self.status = "not connected" }
            print("[iPhone] send blocked: no connection")
            return false
        }

        guard handshakeOK else {
            DispatchQueue.main.async { self.status = "blocked: no handshake" }
            print("[iPhone] blocked: tried TEXT before WELCOME")
            return false
        }

        let payloadStr = CMEFrame.makeText(text)
        let payload = (payloadStr + "\n").data(using: .utf8)!

        c.send(content: payload, completion: .contentProcessed { [weak self] err in
            DispatchQueue.main.async {
                if let err = err {
                    self?.status = "send error: \(err.localizedDescription)"
                    print("[iPhone] send error: \(err)")
                } else {
                    self?.status = "sent ✅"
                    self?.messages.append(ChatMsg(dir: "TX", text: text))
                    print("[iPhone] send ok")
                }
            }
        })

        return true
    }

    // ---- Receive loop (newline framed) ----
    private func receiveLoop() {
        conn?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async { self.status = "rx error: \(error.localizedDescription)" }
                return
            }

            if isComplete {
                DispatchQueue.main.async { self.status = "server closed" }
                return
            }

            if let data = data, !data.isEmpty {
                self.rxBuffer.append(data)

                // split on '\n'
                while let nl = self.rxBuffer.firstRange(of: Data([0x0A])) {
                    let lineData = self.rxBuffer.subdata(in: 0..<nl.lowerBound)
                    self.rxBuffer.removeSubrange(0...nl.lowerBound) // through '\n'

                    guard let line = String(data: lineData, encoding: .utf8) else { continue }
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty { continue }

                    let shown = trimmed

                    let (t, payload, raw) = CMEFrame.parse(shown)

                    if t == "ACK" {
                        DispatchQueue.main.async {
                            self.messages.append(ChatMsg(dir: "IN", text: "ACK"))
                        }
                        self.receiveLoop()
                        return
                    }

                    if t == "WELCOME" {
                        DispatchQueue.main.async {
                            self.sessionID = payload
                            self.handshakeOK = true
                            self.messages.append(ChatMsg(dir: "IN", text: "WELCOME \(payload)"))
                        }
                        self.receiveLoop()
                        return
                    }

                    if t == "HELLO_ACK" {
                        DispatchQueue.main.async {
                            self.messages.append(ChatMsg(dir: "IN", text: "CME1|HELLO_ACK|\(payload)"))
                        }
                        self.receiveLoop()
                        return
                    }

                    if t == "TEXT" {
                        DispatchQueue.main.async {
                            self.messages.append(ChatMsg(dir: "IN", text: "Samsung: \(payload)"))
                        }
                        self.receiveLoop()
                        return
                    }

                    // fallback: show raw line
                    DispatchQueue.main.async {
                        self.messages.append(ChatMsg(dir: "IN", text: raw))
                    }
                    self.receiveLoop()
                    return
                }
            }

            // keep listening
            self.receiveLoop()
        }
    }
}
