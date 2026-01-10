import SwiftUI

struct ContentView: View {

    @StateObject private var client = TCPClient()

    @State private var tapProof = "Tap Proof: (not tapped yet)"
    @State private var toSamsung: String = ""
    @State private var host: String = "192.168.2.26"
    @State private var port: String = "5555"

    var body: some View {
        VStack(spacing: 12) {

            VStack(spacing: 8) {
                Image("taijitu")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 84)

                Text("Polarity")
                    .font(.title2)
                    .bold()

                Text(tapProof)
                    .font(.caption)
                    .foregroundStyle(.yellow)

                Text(client.status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 10)

            Divider().opacity(0.25)

            // Host/Port row
            HStack {
                TextField("Host", text: $host)
                    .textFieldStyle(.roundedBorder)
                TextField("Port", text: $port)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .keyboardType(.numberPad)
            }
            .padding(.horizontal, 12)

            // Messages
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(client.messages) { msg in
                        Text("[\(msg.dir)] \(msg.text)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 180)

            TextField("Message to Samsung", text: $toSamsung)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)

            Button("Send to Samsung") {
                tapProof = "Send tapped at \(Date())"
                let ok = client.sendText(toSamsung)
                if ok {
                    toSamsung = ""
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 12)

            Button("Connect") {
                tapProof = "Connect tapped at \(Date())"

                // 🔑 RESET HANDSHAKE STATE (PASTE HERE)
                client.handshakeOK = false
                client.sessionID = ""

                let p = UInt16(port) ?? 5555
                client.connect(host: host, port: p)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 12)
        }
    }
}

#Preview {
    ContentView()
}
