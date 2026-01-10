import Foundation
import Network
import Combine


final class TCPServer: ObservableObject {
    @Published var status: String = "Server: stopped"
    @Published var lastFromSamsung: String = ""
    @Published var messages: [ChatMsg] = []
    @Published var handshakeOK: Bool = false
    @Published var sessionID: String = ""

    private var listener: NWListener?
    private var connection: NWConnection?
    
    var hasClient: Bool {
        connection != nil
    }
    
    // Start listening on a TCP port (default 5555)
    func start(port: UInt16 = 5555) {
        // Prevent "Address already in use" if you tap Start twice
        stop()

        do {
            let nwPort = NWEndpoint.Port(rawValue: port)!
            listener = try NWListener(using: .tcp, on: nwPort)
        } catch {
            DispatchQueue.main.async {
                self.status = "Server failed: \(error.localizedDescription)"
            }
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                self?.status = "Server: \(state)"
            }
        }

        // Called when a client connects (Samsung Termux client.py)
        listener?.newConnectionHandler = { [weak self] conn in
            guard let self = self else { return }

            // If a new client connects, close the old one (simple single-client server)
            self.connection?.cancel()
            self.connection = conn

            conn.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    self?.status = "Client: \(state)"
                }
            }

            conn.start(queue: .global(qos: .userInitiated))
            self.receiveLoop()
        }

        listener?.start(queue: .global(qos: .userInitiated))
        DispatchQueue.main.async {
            self.status = "Server: listening on \(port)"
        }
    }

    // Stop server + client connection
    func stop() {
        connection?.cancel()
        connection = nil

        listener?.cancel()
        listener = nil

        DispatchQueue.main.async {
            self.status = "Server: stopped"
        }
    }

    // Send text to the currently connected client (Samsung)
    func sendText(_ text: String) {
        guard let conn = connection else {
            status = "No client connected"
            return
        }

        let cmeWrapped = "CME1|" + text + "\n"
        let data = cmeWrapped.data(using: .utf8)!

        conn.send(content: data, completion: .contentProcessed { err in
            DispatchQueue.main.async {

                if let err = err {
                    // ❌ SEND FAILED
                    self.status = "Send failed: \(err.localizedDescription)"

                } else {
                    // ✅ SEND SUCCEEDED  ← THIS IS THE SUCCESS CASE
                    self.status = "Sent to Samsung ✅"

                    // 👉 Add message to chat log
                    self.messages.append(
                        ChatMsg(dir: "OUT", text: text)
                    )
                }
            }
        })
    }

    // Keep receiving messages from client until it disconnects
    private func receiveLoop() {
        guard let conn = connection else { return }

        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                let text = String(decoding: data, as: UTF8.self)

                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

                // 1) Ignore plain ACK control frames (do NOT treat as message / do NOT reset handshake)
                if trimmed == "ACK" || trimmed.hasPrefix("CME1|ACK") {
                    DispatchQueue.main.async {
                        self.messages.append(ChatMsg(dir: "IN", text: "ACK"))
                    }
                    self.receiveLoop()
                    return
                }

                // 2) KEY: unwrap CME1| prefix if present BEFORE parsing/display
                let shown: String
                if trimmed.hasPrefix("CME1|") {
                    shown = String(trimmed.dropFirst(5))   // removes "CME1|"
                } else {
                    shown = trimmed
                }
                // 3) Parse WELCOME (session anchor) and lock handshake
                // Handles: "WELCOME abc123" or "WELCOME|abc123"
                if shown.hasPrefix("WELCOME ") || shown.hasPrefix("WELCOME|") {
                    let session: String
                    if shown.hasPrefix("WELCOME ") {
                        session = String(shown.dropFirst("WELCOME ".count))
                    } else {
                        // "WELCOME|abc123"
                        session = shown.split(separator: "|", omittingEmptySubsequences: true).dropFirst().first.map(String.init) ?? ""
                    }

                    DispatchQueue.main.async {
                        self.sessionID = session
                        self.handshakeOK = true
                        self.messages.append(ChatMsg(dir: "IN", text: "WELCOME \(session)"))
                    }
                    self.receiveLoop()
                    return
                }
                
                DispatchQueue.main.async {
                    self.lastFromSamsung = shown
                    self.messages.append(ChatMsg(dir: "IN", text: shown))
                }

                // Optional: If your Samsung client expects an ACK, you can send one back:
                // self.sendText("ACK: \(text)")
            }

            if isComplete {
                DispatchQueue.main.async {
                    self.status = "Client disconnected"
                }
                self.connection?.cancel()
                self.connection = nil
                return
            }

            if let error = error {
                DispatchQueue.main.async {
                    self.status = "Receive failed: \(error.localizedDescription)"
                }
                self.connection?.cancel()
                self.connection = nil
                return
            }

            // Continue listening for next message
            self.receiveLoop()
        }
    }
    
    private func cme1Encode(_ text: String) -> String {
        let bytes = [UInt8](text.utf8)

        // convert bytes -> big-endian integer
        var n = 0
        for b in bytes {
            n = (n << 8) | Int(b)
        }

        return "CME1|\(n)"
    }
}
