import SwiftUI

@main
struct YConstructionApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @State private var mainViewModel: MainViewModel?
    @State private var showDebugSmokeTests: Bool = false

    var body: some View {
        ZStack {
            if let mainViewModel {
                MainView(
                    viewModel: mainViewModel,
                    onExit: { self.mainViewModel = nil }
                )
                    .onLongPressGesture(minimumDuration: 1.2) {
                        AppConfig.toggleDebugReporter()
                    }
            } else {
                ProjectEntryView(onSubmit: loadProject)
                    .onLongPressGesture(minimumDuration: 1.2) {
                        showDebugSmokeTests = true
                    }
            }
        }
        .sheet(isPresented: $showDebugSmokeTests) {
            SmokeTestResultsView(results: SmokeTests.runAll())
        }
    }

    @MainActor
    private func makeMainViewModel(projectId: String) -> MainViewModel {
        let store = DefectStore(projectId: projectId)
        return MainViewModel(store: store)
    }

    @MainActor
    private func loadProject(_ rawProjectId: String) {
        let projectId = rawProjectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectId.isEmpty else { return }
        mainViewModel = makeMainViewModel(projectId: projectId)
    }
}

struct SmokeTestResultsView: View {
    let results: [String]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(Array(results.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(line.contains("PASS") ? .green : .red)
            }
            .navigationTitle("Smoke tests")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
