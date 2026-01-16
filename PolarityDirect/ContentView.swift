import SwiftUI

struct ContentView: View {
    @EnvironmentObject var client: TCPClient

    @State private var host: String = "192.168.2.26"
    @State private var port: String = "5555"
    @State private var toSamsung: String = ""
    @State private var tapProof: String = "Tap Proof: (not tapped yet)"

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "yin.yang")
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 84)

            Text("Polarity").font(.title2).bold()

            Text(tapProof).font(.caption).foregroundStyle(.yellow)
            Text(client.status).font(.subheadline).foregroundStyle(.secondary)

            Divider().opacity(0.25)

            HStack {
                TextField("Host", text: $host)
                    .textFieldStyle(.roundedBorder)

                TextField("Port", text: $port)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .keyboardType(.numberPad)
            }
            .padding(.horizontal, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(client.messages) { m in
                        Text("[\(m.dir)] \(m.text)")
                            .font(.system(.body, design: .monospaced))
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
                if ok { toSamsung = "" }
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 12)

            Button("Connect") {
                tapProof = "Connect tapped at \(Date())"
                let p = UInt16(port) ?? 5555
                client.connect(host: host, port: p)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 12)
        }
        .padding(.top, 10)
    }
}

#Preview {
    ContentView()
        .environmentObject(TCPClient()) // preview-only
}
