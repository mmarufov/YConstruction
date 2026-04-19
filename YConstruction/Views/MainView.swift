import SwiftUI
import SceneKit
import Combine

@MainActor
final class MainViewModel: ObservableObject {
    @Published var mode: SceneCameraMode = .perspective3D
    @Published var currentStorey: String?
    @Published var availableStoreys: [String] = []
    @Published var tappedDefectId: String?
    @Published var selectedDefect: Defect?
    @Published var isLoading: Bool = true
    @Published var loadError: String?

    @Published var recorderState: RecorderState = .idle
    @Published var liveTranscript: String = ""
    @Published var processingTitle: String = "Processing…"

    @Published var photoRequestReason: String?
    @Published var resolverCandidates: [ResolvedElement] = []
    @Published var resolverEnglishTranscript: String?
    @Published var showingResolverPicker: Bool = false

    @Published var isOnline: Bool = true

    let renderer = SceneRendererService()
    let resolver = DefectResolverService()
    let bcfEmitter = BCFEmitterService()
    let camera = CameraService()
    let store: DefectStore
    let syncService: SyncService
    let projectId: String

    var pipeline: PipelineService?
    private var storeObservation: AnyCancellable?

    init(store: DefectStore) {
        self.store = store
        self.syncService = SyncService(store: store)
        self.projectId = store.projectId
        // Forward nested store changes so SwiftUI re-renders MainView when
        // realtime inserts land in the DB (otherwise SwiftUI only subscribes
        // to viewModel.objectWillChange, not store.objectWillChange).
        self.storeObservation = store.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    enum RecorderState: Equatable {
        case idle
        case listening
        case processing(String)
        case camera(reason: String)
    }
}

struct MainView: View {
    @ObservedObject var viewModel: MainViewModel
    let onExit: () -> Void

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
                    currentStorey: viewModel.currentStorey,
                    tappedDefectId: $viewModel.tappedDefectId
                )
                .ignoresSafeArea()
            }

            VStack {
                topBar
                Spacer()
                bottomBar
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

            if case .listening = viewModel.recorderState {
                RecordingOverlay(
                    transcript: viewModel.liveTranscript,
                    onStop: { Task { await viewModel.pipeline?.stopRecording() } }
                )
            }

            if case .processing(let title) = viewModel.recorderState {
                ProcessingOverlay(title: title)
            }

            if case .camera(let reason) = viewModel.recorderState {
                CameraOverlay(
                    reason: reason,
                    projectId: viewModel.projectId,
                    camera: viewModel.camera,
                    onCapture: { url in
                        Task { await viewModel.pipeline?.handleCaptured(url: url) }
                    },
                    onCancel: {
                        Task { await viewModel.pipeline?.cancelCamera() }
                    }
                )
                .transition(.opacity)
            }

            if let error = viewModel.loadError {
                VStack(spacing: 12) {
                    Text(viewModel.pipeline == nil ? "Failed to Load Project" : "Something Went Wrong")
                        .font(.headline)
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    if viewModel.pipeline == nil {
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
        .sheet(isPresented: $viewModel.showingResolverPicker) {
            ResolverPickerSheet(
                candidates: viewModel.resolverCandidates,
                transcriptEnglish: viewModel.resolverEnglishTranscript,
                onPick: { element in
                    Task { await viewModel.pipeline?.confirmPick(element: element) }
                    viewModel.showingResolverPicker = false
                },
                onSaveAnyway: {
                    Task { await viewModel.pipeline?.saveWithoutResolver() }
                    viewModel.showingResolverPicker = false
                },
                onCancel: {
                    Task { await viewModel.pipeline?.cancelResolver() }
                    viewModel.showingResolverPicker = false
                }
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
        .onChange(of: viewModel.currentStorey) { _, newValue in
            viewModel.renderer.setStorey(newValue)
        }
        .onChange(of: viewModel.mode) { _, newValue in
            viewModel.renderer.setMode(newValue)
        }
        .onReceive(viewModel.syncService.$isOnline) { viewModel.isOnline = $0 }
        .onReceive(viewModel.syncService.$lastSyncedAt) { date in
            if let date { viewModel.store.noteSynced(at: date) }
        }
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
        HStack {
            HStack(spacing: 10) {
                storeyPicker
                SyncStatusBadge(
                    pendingCount: viewModel.store.pendingSyncCount,
                    lastSyncedAt: viewModel.store.lastSyncedAt,
                    isOnline: viewModel.isOnline
                )
            }
            Spacer()
            modeToggle
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }

    private var storeyPicker: some View {
        Menu {
            ForEach(viewModel.availableStoreys, id: \.self) { storey in
                Button(storey) { viewModel.currentStorey = storey }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                Text(viewModel.currentStorey ?? "Storey")
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
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
                .frame(width: 44, height: 36)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            Spacer()
            Button {
                Task { await viewModel.pipeline?.toggleRecording() }
            } label: {
                ZStack {
                    Circle().fill(.red).frame(width: 78, height: 78)
                    Image(systemName: "mic.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                }
                .shadow(radius: 8)
            }
            .disabled(disableRecord)
            Spacer()
        }
        .padding(.bottom, 30)
    }

    private var disableRecord: Bool {
        guard viewModel.pipeline != nil, !viewModel.isLoading else { return true }
        switch viewModel.recorderState {
        case .idle, .listening: return false
        default: return true
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
        guard viewModel.pipeline == nil else { return }

        let loader = ProjectLoaderService(projectId: viewModel.projectId)
        do {
            let bundle = try await loader.load()
            try await viewModel.renderer.load(glbURL: bundle.glbURL)
            try viewModel.resolver.load(from: bundle.elementIndexURL)
            if let idx = viewModel.resolver.index {
                viewModel.availableStoreys = idx.storeys.map(\.name)
                viewModel.renderer.configure(storeys: idx.storeys)
                viewModel.renderer.filterMeshes(keepingIndexed: idx)
                let initialStorey = idx.storeys.first(where: { $0.name == "Level 1" })?.name
                    ?? idx.storeys.first?.name
                viewModel.currentStorey = initialStorey
                viewModel.renderer.setStorey(initialStorey)
            }
            viewModel.renderer.syncMarkers(with: viewModel.store.defects)
            viewModel.pipeline = PipelineService(viewModel: viewModel)
            viewModel.syncService.start()
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
