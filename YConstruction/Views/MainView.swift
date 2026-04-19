import SwiftUI
import SceneKit
import Combine

@MainActor
final class MainViewModel: ObservableObject {
    @Published var mode: SceneCameraMode = .perspective3D
    @Published var tappedDefectId: String?
    @Published var selectedDefect: Defect?
    @Published var isLoading: Bool = true
    @Published var loadError: String?

    @Published var isOnline: Bool = true
    @Published var isSyncing: Bool = false

    let renderer = SceneRendererService()
    let resolver = DefectResolverService()
    let bcfEmitter = BCFEmitterService()
    let store: DefectStore
    let syncService: SyncService
    let projectId: String

    private var booted = false
    private var storeObservation: AnyCancellable?
    private var errorDismissTask: Task<Void, Never>?

    init(store: DefectStore) {
        self.store = store
        self.syncService = SyncService(store: store)
        self.projectId = store.projectId
        self.storeObservation = store.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    func showTransientError(_ message: String) {
        loadError = message
        errorDismissTask?.cancel()
        errorDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, let self else { return }
            if self.loadError == message {
                self.loadError = nil
            }
        }
    }

    func clearTransientError() {
        errorDismissTask?.cancel()
        errorDismissTask = nil
        loadError = nil
    }

    func markBooted() { booted = true }
    var isBooted: Bool { booted }
}

struct MainView: View {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject var workerDirectory: WorkerDirectoryService = .shared
    let onExit: () -> Void
    @State private var glossaryExpanded = true

    var body: some View {
        ZStack {
            Scene3DView(
                renderer: viewModel.renderer,
                mode: viewModel.mode,
                tappedDefectId: $viewModel.tappedDefectId
            )
            .ignoresSafeArea()

            if viewModel.mode == .orthographic2D {
                Scene2DMarkerOverlay(
                    renderer: viewModel.renderer,
                    defects: viewModel.store.defects,
                    tappedDefectId: $viewModel.tappedDefectId
                )
                .ignoresSafeArea()
            }

            VStack {
                topBar
                HStack(alignment: .top) {
                    Spacer()
                    WorkerGlossaryView(
                        workers: workersInView,
                        counts: defectCountsByReporter,
                        expanded: $glossaryExpanded
                    )
                    .padding(.trailing, 16)
                    .padding(.top, 4)
                }
                Spacer()
            }

            if viewModel.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading project…")
                        .font(.callout.weight(.medium))
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            if let error = viewModel.loadError {
                VStack(spacing: 12) {
                    Text(viewModel.isBooted ? "Something Went Wrong" : "Failed to Load Project")
                        .font(.headline)
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    if !viewModel.isBooted {
                        Button("Choose Another Project", action: onExit)
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding()
            }
        }
        .task(id: viewModel.projectId) { await boot() }
        .sheet(item: sheetBinding) { defect in
            DetailSheet(
                defect: defect,
                onResolve: { toggleResolved(defect) },
                onDismiss: dismissSelectedDefect
            )
        }
        .onChange(of: viewModel.tappedDefectId) { _, newValue in
            guard let newValue else { return }
            if let defect = viewModel.store.defects.first(where: { $0.id == newValue }) {
                viewModel.selectedDefect = defect
            }
        }
        .onChange(of: viewModel.store.defects) { _, newValue in
            viewModel.renderer.syncMarkers(with: newValue)
        }
        .onChange(of: viewModel.mode) { _, newValue in
            viewModel.renderer.setMode(newValue)
        }
        .onReceive(viewModel.syncService.$isOnline) { viewModel.isOnline = $0 }
        .onReceive(viewModel.syncService.$isSyncing) { viewModel.isSyncing = $0 }
        .onReceive(viewModel.syncService.$lastSyncedAt) { date in
            if let date { viewModel.store.noteSynced(at: date) }
        }
    }

    private var defectCountsByReporter: [String: Int] {
        var counts: [String: Int] = [:]
        for d in viewModel.store.defects {
            counts[d.reporter, default: 0] += 1
        }
        return counts
    }

    private var workersInView: [Worker] {
        let names = Set(viewModel.store.defects.map(\.reporter))
        guard !names.isEmpty else { return [] }

        let directoryByName = Dictionary(
            uniqueKeysWithValues: workerDirectory.workers.map { ($0.name, $0) }
        )

        let now = Date()
        let entries: [Worker] = names.map { name in
            if let worker = directoryByName[name] { return worker }
            return Worker(
                id: "reporter:\(name)",
                name: name,
                department: "Unknown",
                colorIndex: WorkerColorPalette.fallbackIndex(for: name),
                createdAt: now,
                updatedAt: now
            )
        }
        return entries.sorted { $0.name < $1.name }
    }

    private var sheetBinding: Binding<Defect?> {
        Binding(
            get: { viewModel.selectedDefect },
            set: { newValue in
                if let newValue {
                    viewModel.selectedDefect = newValue
                } else {
                    dismissSelectedDefect()
                }
            }
        )
    }

    // MARK: - Top bar

    private var topBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 10) {
                backButton
                SyncStatusBadge(
                    lastSyncedAt: viewModel.store.lastSyncedAt,
                    isOnline: viewModel.isOnline,
                    isSyncing: viewModel.isSyncing
                )
                Spacer()
                openIssuesBadge
                modeToggle
            }
            .padding(.horizontal)
            .padding(.top, 10)
        }
    }

    private var backButton: some View {
        Button(action: onExit) {
            Image(systemName: "chevron.left")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .accessibilityLabel("Back to projects")
    }

    @ViewBuilder
    private var openIssuesBadge: some View {
        let openCount = viewModel.store.defects.filter { !$0.resolved }.count
        if openCount > 0 {
            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text("\(openCount) OPEN")
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(.red)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .glassEffect(.regular, in: .capsule)
        }
    }

    private var modeToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                viewModel.mode = (viewModel.mode == .perspective3D) ? .orthographic2D : .perspective3D
            }
        } label: {
            Text(viewModel.mode == .perspective3D ? "2D" : "3D")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    private func dismissSelectedDefect() {
        viewModel.selectedDefect = nil
        viewModel.tappedDefectId = nil
    }

    private func toggleResolved(_ defect: Defect) {
        do { try viewModel.store.markResolved(defect.id, resolved: !defect.resolved) }
        catch { print("markResolved failed: \(error)") }
        dismissSelectedDefect()
    }

    // MARK: - Boot

    private func boot() async {
        guard !viewModel.isBooted else { return }

        let loader = ProjectLoaderService(projectId: viewModel.projectId)
        do {
            let bundle = try await loader.load()
            try await viewModel.renderer.load(glbURL: bundle.glbURL)
            try viewModel.resolver.load(from: bundle.elementIndexURL)
            if let idx = viewModel.resolver.index {
                viewModel.renderer.filterMeshes(keepingIndexed: idx)
            }
            viewModel.renderer.syncMarkers(with: viewModel.store.defects)
            viewModel.syncService.start()
            workerDirectory.start()
            viewModel.markBooted()
            viewModel.isLoading = false
        } catch is CancellationError {
            viewModel.isLoading = false
        } catch {
            viewModel.loadError = error.localizedDescription
            viewModel.isLoading = false
        }
    }
}

#Preview {
    MainView(
        viewModel: MainViewModel(store: DefectStore()),
        onExit: {}
    )
}
