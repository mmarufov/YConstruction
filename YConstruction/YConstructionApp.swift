import SwiftUI

@main
struct YConstructionApp: App {
    @StateObject private var app = AppState(useStub: true)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
                .onAppear { app.bootstrap() }
        }
    }
}
