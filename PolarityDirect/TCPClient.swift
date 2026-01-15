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
        
        let encoded = CMEDemoV3.encode(text)
        let payloadStr = CMEFrame.makeText(encoded)
        print("[iPhone] TX frame: \(payloadStr)")
        
        print("[iPhone] TX plain: \(text)")
        print("[iPhone] TX encoded: \(encoded)")
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
                        
                        // --- CME decode hook ---
                        let decoded: String
                        if payload.hasPrefix("R0:") || payload.hasPrefix("R1:") {
                            decoded = CMEDecode.decode(payload)
                        } else {
                            decoded = payload
                        }
                        
                        DispatchQueue.main.async {
                            self.messages.append(
                                ChatMsg(dir: "IN", text: "Samsung: \(decoded)")
                            )
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
    enum CMEDecode {
        
        static func decode(_ payload: String) -> String {
            if payload.hasPrefix("R0:") {
                return decodeR0(payload)
            }
            if payload.hasPrefix("R1:") {
                return decodeR1(payload)
            }
            return payload
        }
        
        private static func decodeR0(_ payload: String) -> String {
            let b64 = String(payload.dropFirst(3))
            guard
                let data = Data(base64Encoded: b64),
                data.count == 8
            else { return payload }
            
            let r0 = data.withUnsafeBytes { $0.load(as: Double.self) }
            let areaD = (4.0 * Double.pi) * (r0 * r0)
            let A = UInt64(areaD.rounded())
            return u64ToText(A)
        }
        
        private static func decodeR1(_ payload: String) -> String {
            let phi = 1.618033988749895
            let b64 = String(payload.dropFirst(3))
            guard
                let data = Data(base64Encoded: b64),
                data.count == 8
            else { return payload }
            
            let r1 = data.withUnsafeBytes { $0.load(as: Double.self) }
            let r0 = r1 * phi
            let areaD = (4.0 * Double.pi) * (r0 * r0)
            let A = UInt64(areaD.rounded())
            return u64ToText(A)
        }
        
        private static func u64ToText(_ x: UInt64) -> String {
            var v = x.bigEndian
            let data = Data(bytes: &v, count: 8)
            return String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .controlCharacters)
        }
    }
    
}

enum CMEDecode {

    private static let r0Prefix = "R0:"
    private static let r1Prefix = "R1:"
    private static let phi: Double = 1.618033988749895

    static func decode(_ payload: String) -> String {
        if payload.hasPrefix(r0Prefix) { return decodeR0(payload) }
        if payload.hasPrefix(r1Prefix) { return decodeR1(payload) }
        return payload
    }

    // MARK: - R0

    private static func decodeR0(_ payload: String) -> String {
        let b64 = String(payload.dropFirst(r0Prefix.count))
        guard let r0 = unpackF64LE(fromB64: b64) else { return payload }

        let areaD = (4.0 * Double.pi) * (r0 * r0)     // Double
        let A: UInt64 = areaD.isFinite && areaD > 0 ? UInt64(areaD.rounded()) : 0

        return u64ToText(A)
    }

    // MARK: - R1

    private static func decodeR1(_ payload: String) -> String {
        let b64 = String(payload.dropFirst(r1Prefix.count))
        guard let r1 = unpackF64LE(fromB64: b64) else { return payload }

        let r0 = r1 * phi
        let areaD = (4.0 * Double.pi) * (r0 * r0)     // Double
        let A: UInt64 = areaD.isFinite && areaD > 0 ? UInt64(areaD.rounded()) : 0

        return u64ToText(A)
    }

    // MARK: - Base64 <-> Double (little-endian, matches Python struct.pack("<d", ...))

    private static func unpackF64LE(fromB64 b64: String) -> Double? {
        guard let data = Data(base64Encoded: b64), data.count == 8 else { return nil }
        return data.withUnsafeBytes { rawPtr -> Double in
            let ptr = rawPtr.bindMemory(to: Double.self)
            return ptr[0]
        }
    }

    // MARK: - 8-byte meaning helpers (match Python)

    private static func u64ToText(_ x: UInt64) -> String {
        var be = x.bigEndian
        let data = withUnsafeBytes(of: &be) { Data($0) }  // 8 bytes
        // Strip trailing nulls (Python rstrip(b"\x00"))
        let trimmed = data.reversed().drop(while: { $0 == 0 }).reversed()
        return String(decoding: trimmed, as: UTF8.self)
    }
}
