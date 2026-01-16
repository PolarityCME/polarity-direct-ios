import SwiftUI

@main
struct PolarityDirectApp: App {
    @StateObject private var client = TCPClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(client)
        }
    }
}
