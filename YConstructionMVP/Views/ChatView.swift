import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @StateObject private var cameraController = CameraSessionController()
    @State private var isImportingModel = false

    @MainActor
    init(viewModel: ChatViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: ChatViewModel())
    }

    var body: some View {
        ZStack {
            cameraLayer
            gradientOverlay
            content
        }
        .background(.black)
        .task {
            viewModel.setCameraSnapshotProvider {
                await cameraController.captureStillImage()
            }
            await viewModel.prepare()
        }
        .onChange(of: viewModel.isCameraContextEnabled, initial: true) { _, isEnabled in
            if isEnabled {
                Task {
                    await cameraController.start()
                }
            } else {
                cameraController.stop()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await viewModel.refreshModelAvailability()
                if viewModel.isCameraContextEnabled {
                    await cameraController.start()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            cameraController.stop()
        }
        .fileImporter(
            isPresented: $isImportingModel,
            allowedContentTypes: [.folder]
        ) { result in
            switch result {
            case .success(let url):
                Task {
                    await viewModel.importModel(from: url)
                }
            case .failure(let error):
                viewModel.modelSetupMessage = error.localizedDescription
                viewModel.modelStatusText = "Model import failed."
            }
        }
        .onDisappear {
            cameraController.stop()
            viewModel.stopListening()
            viewModel.setCameraSnapshotProvider(nil)
        }
    }

    private var cameraLayer: some View {
        Group {
            if viewModel.canCaptureSitePhoto, viewModel.isCameraContextEnabled, cameraController.isReady {
                CameraPreview(session: cameraController.session)
                    .ignoresSafeArea()
            } else {
                Rectangle()
                    .fill(Color.black)
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: viewModel.isCameraContextEnabled ? "camera.viewfinder" : "camera.fill")
                                .font(.system(size: 32))
                            Text(cameraStatusOverlayText)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(24)
                    }
                    .ignoresSafeArea()
            }
        }
    }

    private var gradientOverlay: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.65),
                Color.clear,
                Color.black.opacity(0.8)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            Spacer()
            bottomPanel
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 20)
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YConstruction Field Copilot")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            HStack(spacing: 10) {
                StatusPill(
                    label: cameraPillLabel,
                    systemImage: cameraPillSystemImage,
                    tint: cameraPillTint
                )

                StatusPill(
                    label: modelPillLabel,
                    systemImage: modelPillSystemImage,
                    tint: modelPillTint
                )

                StatusPill(
                    label: syncPillLabel,
                    systemImage: syncPillSystemImage,
                    tint: syncPillTint
                )
            }
        }
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            infoCard(title: "Local Model", text: viewModel.modelStatusText)
            infoCard(title: "Local Search", text: viewModel.localSearchStatusText)
            infoCard(title: "Backend Contract", text: viewModel.backendStatusText)
            infoCard(title: "Backend Sync", text: backendSyncDescription)
            infoCard(title: "Site Photo", text: cameraContextDescription)

            if let modelSetupMessage = viewModel.modelSetupMessage {
                modelSetupCard(text: modelSetupMessage)
            }

            if let backendErrorMessage = viewModel.backendErrorMessage {
                infoCard(title: "Backend Error", text: backendErrorMessage)
            }

            if let permissionMessage = viewModel.permissionMessage {
                infoCard(title: "Permission Needed", text: permissionMessage)
            }

            if !viewModel.lastInputSummary.isEmpty {
                infoCard(title: "Last Capture", text: viewModel.lastInputSummary)
            }

            if let lastRuntimeText = viewModel.lastRuntimeText {
                infoCard(title: "Last Runtime", text: lastRuntimeText)
            }

            if !viewModel.latestReply.isEmpty {
                infoCard(title: "Assistant", text: viewModel.latestReply)
            }

            Toggle(isOn: $viewModel.isCameraContextEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Capture a site photo")
                        .foregroundStyle(.white)
                    Text(
                        "Optional. Stage one photo for a new report or for a local question against synced history. Voice still works fully with the camera off."
                    )
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .tint(.white)

            Text(viewModel.statusText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))

            HStack(spacing: 16) {
                Button(role: .destructive) {
                    viewModel.clearConversation()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title3)
                        .frame(width: 52, height: 52)
                        .background(.white.opacity(0.14))
                        .clipShape(Circle())
                }
                .foregroundStyle(.white)

                Button {
                    viewModel.syncNow()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title3)
                        .frame(width: 52, height: 52)
                        .background(.white.opacity(0.14))
                        .clipShape(Circle())
                }
                .foregroundStyle(.white)

                Button {
                    viewModel.captureSitePhoto()
                } label: {
                    ZStack {
                        Circle()
                            .fill(photoButtonFill)
                            .frame(width: 52, height: 52)

                        if viewModel.isCapturingPhoto {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: viewModel.hasStagedPhoto ? "checkmark.circle.fill" : "camera.fill")
                                .font(.title3)
                        }
                    }
                }
                .foregroundStyle(.white)
                .disabled(!viewModel.canCapturePhotoNow)

                Button {
                    viewModel.toggleListening()
                } label: {
                    ZStack {
                        Circle()
                            .fill(viewModel.canUseMicrophone ? (viewModel.isListening ? Color.red : Color.white) : Color.white.opacity(0.45))
                            .frame(width: 96, height: 96)

                        Image(systemName: viewModel.isListening ? "stop.fill" : "mic.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(viewModel.isListening ? .white : .black.opacity(viewModel.canUseMicrophone ? 1 : 0.55))
                    }
                }
                .disabled(!viewModel.canUseMicrophone)

                Button {
                    viewModel.replayLatestReply()
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.title3)
                        .frame(width: 52, height: 52)
                        .background(.white.opacity(0.14))
                        .clipShape(Circle())
                }
                .foregroundStyle(.white)
                .disabled(!viewModel.hasReply)
            }

            Text(viewModel.isListening
                 ? "Talk naturally. The app auto-sends after you pause, or tap again to send now."
                 : "Recommended flow: 1) tap the camera button to stage a photo, 2) tap the mic to either report a new issue or ask a question about it, 3) let Wi-Fi auto-sync or press Sync Now for report uploads.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.82))
        }
        .padding(18)
        .background(.ultraThinMaterial.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var cameraStatusOverlayText: String {
        return viewModel.isCameraContextEnabled
            ? cameraController.statusText
            : "Site photo capture is off. Voice still works locally without it."
    }

    private var cameraContextDescription: String {
        if !viewModel.isCameraContextEnabled {
            return "Off. Enable this when you want to snap one photo, then either describe a new issue or ask a question about it."
        }

        return "\(viewModel.stagedPhotoStatusText) The next completed voice turn will consume the staged photo and decide whether this is a new report or a local question."
    }

    private var backendSyncDescription: String {
        if viewModel.pendingSyncCount > 0 {
            return "\(viewModel.backendSyncText)\nPending queue: \(viewModel.pendingSyncCount)"
        }

        return viewModel.backendSyncText
    }

    private var cameraPillLabel: String {
        if !viewModel.isCameraContextEnabled {
            return "Photo Off"
        }

        if viewModel.hasStagedPhoto {
            return "Photo Staged"
        }

        if viewModel.isCapturingPhoto {
            return "Capturing"
        }

        return cameraController.isReady ? "Photo Ready" : "Photo Optional"
    }

    private var cameraPillSystemImage: String {
        if !viewModel.isCameraContextEnabled {
            return "camera.fill"
        }

        if viewModel.hasStagedPhoto {
            return "checkmark.circle.fill"
        }

        if viewModel.isCapturingPhoto {
            return "camera.aperture"
        }

        return cameraController.isReady ? "video.fill" : "video.badge.waveform"
    }

    private var cameraPillTint: Color {
        if !viewModel.isCameraContextEnabled {
            return .gray
        }

        if viewModel.hasStagedPhoto {
            return .green
        }

        if viewModel.isCapturingPhoto {
            return .yellow
        }

        return cameraController.isReady ? .green : .orange
    }

    private var photoButtonFill: Color {
        if !viewModel.canCapturePhotoNow {
            return .white.opacity(0.08)
        }

        if viewModel.hasStagedPhoto {
            return Color.green.opacity(0.28)
        }

        return .white.opacity(0.14)
    }

    private var modelPillLabel: String {
        if viewModel.isImportingModel {
            return "Importing Model"
        }

        if viewModel.isPreparingModel {
            return "Prewarming"
        }

        if viewModel.isListening {
            return "Listening"
        }

        if viewModel.isLoading {
            return "Thinking"
        }

        return viewModel.isModelReady ? "Model Ready" : "Model Needed"
    }

    private var modelPillSystemImage: String {
        if viewModel.isImportingModel {
            return "square.and.arrow.down.fill"
        }

        if viewModel.isPreparingModel {
            return "bolt.badge.clock.fill"
        }

        if viewModel.isListening {
            return "waveform"
        }

        return viewModel.isModelReady ? "bolt.circle.fill" : "externaldrive.fill.badge.exclamationmark"
    }

    private var modelPillTint: Color {
        if viewModel.isImportingModel {
            return .orange
        }

        if viewModel.isPreparingModel {
            return .yellow
        }

        if viewModel.isListening {
            return .red
        }

        return viewModel.isModelReady ? .blue : .yellow
    }

    private var syncPillLabel: String {
        if viewModel.pendingSyncCount > 0 {
            return "Queued \(viewModel.pendingSyncCount)"
        }

        if let backendErrorMessage = viewModel.backendErrorMessage, !backendErrorMessage.isEmpty {
            return "Sync Error"
        }

        return "Sync Ready"
    }

    private var syncPillSystemImage: String {
        if viewModel.pendingSyncCount > 0 {
            return "tray.full.fill"
        }

        if let backendErrorMessage = viewModel.backendErrorMessage, !backendErrorMessage.isEmpty {
            return "exclamationmark.triangle.fill"
        }

        return "icloud.and.arrow.up.fill"
    }

    private var syncPillTint: Color {
        if viewModel.pendingSyncCount > 0 {
            return .orange
        }

        if let backendErrorMessage = viewModel.backendErrorMessage, !backendErrorMessage.isEmpty {
            return .red
        }

        return .green
    }

    private func modelSetupCard(text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            infoCard(title: "Setup", text: text)

            HStack(spacing: 10) {
                Button("Import Model Folder") {
                    isImportingModel = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.22))

                Button("Refresh") {
                    Task {
                        await viewModel.refreshModelAvailability()
                    }
                }
                .buttonStyle(.bordered)
            }
            .tint(.white)
        }
    }

    private func infoCard(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.7))

            Text(text)
                .font(.body)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.black.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct StatusPill: View {
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tint.opacity(0.18))
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

private final class CameraSessionController: NSObject, ObservableObject, @unchecked Sendable {
    @Published private(set) var statusText = "Camera context off."
    @Published private(set) var isReady = false

    let session = AVCaptureSession()

    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "YConstructionMVP.camera.session")
    private var isConfigured = false
    private var desiredRunning = false
    private var isStarting = false
    private var observersInstalled = false
    private var photoCaptureProcessors: [Int64: PhotoCaptureProcessor] = [:]

    func start() async {
        let granted = await requestCameraPermissionIfNeeded()
        guard granted else {
            desiredRunning = false
            publishStatus("Camera access is blocked. Voice still works without it.", ready: false)
            return
        }

        desiredRunning = true
        installObserversIfNeeded()
        sessionQueue.async { [weak self] in
            self?.startIfNeededLocked()
        }
    }

    func stop() {
        desiredRunning = false
        sessionQueue.async { [weak self] in
            guard let self else { return }

            self.isStarting = false
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.publishStatus("Camera context off.", ready: false)
        }
    }

    func captureStillImage() async -> URL? {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }

                guard self.desiredRunning, self.isConfigured, self.session.isRunning else {
                    continuation.resume(returning: nil)
                    return
                }

                let settings = AVCapturePhotoSettings()
                let uniqueID = Int64(settings.uniqueID)
                let processor = PhotoCaptureProcessor(uniqueID: uniqueID) { [weak self] result in
                    self?.sessionQueue.async {
                        self?.photoCaptureProcessors.removeValue(forKey: uniqueID)
                    }

                    switch result {
                    case .success(let imageData):
                        do {
                            let imageURL = try Self.writeCapturedPhoto(imageData)
                            continuation.resume(returning: imageURL)
                        } catch {
                            continuation.resume(returning: nil)
                        }
                    case .failure:
                        continuation.resume(returning: nil)
                    }
                }

                self.photoCaptureProcessors[uniqueID] = processor
                self.photoOutput.capturePhoto(with: settings, delegate: processor)
            }
        }
    }

    @objc private func handleRuntimeError(_ notification: Notification) {
        let errorDescription: String
        if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError {
            errorDescription = error.localizedDescription
        } else {
            errorDescription = "Unknown runtime error."
        }

        desiredRunning = false
        publishStatus("Camera runtime error. Voice still works without it. \(errorDescription)", ready: false)
    }

    @objc private func handleSessionInterrupted(_ notification: Notification) {
        let reasonText: String
        if let rawValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber,
           let reason = AVCaptureSession.InterruptionReason(rawValue: rawValue.intValue) {
            reasonText = String(describing: reason)
        } else {
            reasonText = "Camera unavailable right now."
        }

        publishStatus("Camera interrupted. Voice still works without it. \(reasonText)", ready: false)
    }

    @objc private func handleSessionInterruptionEnded(_ notification: Notification) {
        guard desiredRunning else { return }
        sessionQueue.async { [weak self] in
            self?.startIfNeededLocked()
        }
    }

    private func startIfNeededLocked() {
        guard desiredRunning else { return }

        if session.isRunning {
            publishStatus("Camera live.", ready: true)
            return
        }

        guard !isStarting else { return }
        isStarting = true
        publishStatus("Starting camera context...", ready: false)

        do {
            try configureIfNeededLocked()
            guard desiredRunning else {
                isStarting = false
                return
            }

            session.startRunning()

            if session.isRunning {
                publishStatus("Camera live.", ready: true)
            } else {
                throw CameraError.startFailed
            }
        } catch {
            desiredRunning = false
            publishStatus("Camera unavailable. Voice still works without it. \(error.localizedDescription)", ready: false)
        }

        isStarting = false
    }

    private func configureIfNeededLocked() throws {
        guard !isConfigured else { return }

        session.beginConfiguration()
        do {
            session.sessionPreset = .photo

            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                throw CameraError.noCamera
            }

            let input = try AVCaptureDeviceInput(device: camera)

            guard session.canAddInput(input) else {
                throw CameraError.cannotAddInput
            }
            session.addInput(input)

            guard session.canAddOutput(photoOutput) else {
                throw CameraError.cannotAddPhotoOutput
            }
            session.addOutput(photoOutput)

            isConfigured = true
            session.commitConfiguration()
        } catch {
            session.commitConfiguration()
            throw error
        }
    }

    private func requestCameraPermissionIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func installObserversIfNeeded() {
        guard !observersInstalled else { return }
        observersInstalled = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRuntimeError(_:)),
            name: .AVCaptureSessionRuntimeError,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionInterrupted(_:)),
            name: .AVCaptureSessionWasInterrupted,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionInterruptionEnded(_:)),
            name: .AVCaptureSessionInterruptionEnded,
            object: session
        )
    }

    private func publishStatus(_ text: String, ready: Bool) {
        DispatchQueue.main.async {
            self.statusText = text
            self.isReady = ready
        }
    }

    private static func writeCapturedPhoto(_ imageData: Data) throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CapturedFrames", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        try imageData.write(to: fileURL, options: [.atomic])
        return fileURL
    }

    private enum CameraError: LocalizedError {
        case noCamera
        case cannotAddInput
        case cannotAddPhotoOutput
        case noPhotoData
        case startFailed

        var errorDescription: String? {
            switch self {
            case .noCamera:
                return "No rear camera was found."
            case .cannotAddInput:
                return "The camera input could not be attached."
            case .cannotAddPhotoOutput:
                return "The camera photo output could not be attached."
            case .noPhotoData:
                return "The camera did not return an image."
            case .startFailed:
                return "The camera session did not start."
            }
        }
    }

    private final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
        let uniqueID: Int64
        private let completion: (Result<Data, Error>) -> Void

        init(uniqueID: Int64, completion: @escaping (Result<Data, Error>) -> Void) {
            self.uniqueID = uniqueID
            self.completion = completion
        }

        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            if let error {
                completion(.failure(error))
                return
            }

            guard let imageData = photo.fileDataRepresentation() else {
                completion(.failure(CameraError.noPhotoData))
                return
            }

            completion(.success(imageData))
        }
    }
}

#Preview {
    ChatView(viewModel: ChatViewModel(aiService: MockAIService()))
}
