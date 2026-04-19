import AVFoundation
import Combine
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @StateObject private var cameraController = CameraSessionController()
    @State private var isImportingModel = false
    @State private var showingCameraPopup = false

    @MainActor
    init(viewModel: ChatViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: ChatViewModel())
    }

    var body: some View {
        content
        .overlay {
            if showingCameraPopup {
                cameraPopup
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .overlay(alignment: .top) {
            if let toast = viewModel.toastMessage {
                toastBanner(text: toast)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: showingCameraPopup)
        .animation(.easeInOut(duration: 0.22), value: viewModel.toastMessage)
        .onChange(of: viewModel.hasStagedPhoto) { _, hasPhoto in
            if hasPhoto && showingCameraPopup {
                showingCameraPopup = false
            }
        }
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

    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                statusCard(title: "General Model", detail: "Gemma 3n E2B loaded", showCheck: true)
                statusCard(title: "RAG Model", detail: "Qwen3 Embedding 0.6B loaded", showCheck: true)
                statusCard(title: "Cloud Surfacing", detail: "Supabase - Loaded", showCheck: false)
                statusCard(title: "Cloud Sync", detail: cloudSyncDetail, showCheck: false)

                actionButtons
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
    }

    private var actionButtons: some View {
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 16) {
                Button(role: .destructive) {
                    viewModel.undoLastAction()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title3)
                        .frame(width: 52, height: 52)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .foregroundStyle(.primary)

                Button {
                    viewModel.syncNow()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title3)
                        .frame(width: 52, height: 52)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .foregroundStyle(.primary)
                .overlay(alignment: .top) {
                    ZStack {
                        Circle()
                            .fill(viewModel.isOnWiFi ? Color.green : Color.red)
                            .frame(width: 18, height: 18)
                        Image(systemName: "wifi")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    .offset(y: -12)
                }

                Button {
                    showingCameraPopup = true
                } label: {
                    ZStack {
                        if viewModel.isCapturingPhoto {
                            ProgressView()
                        } else {
                            Image(systemName: viewModel.hasStagedPhoto ? "checkmark.circle.fill" : "camera.fill")
                                .font(.title3)
                        }
                    }
                    .frame(width: 52, height: 52)
                    .glassEffect(.regular.interactive(), in: .circle)
                }
                .foregroundStyle(viewModel.hasStagedPhoto ? .green : .primary)
                .disabled(viewModel.isListening || viewModel.isLoading || viewModel.isCapturingPhoto || viewModel.hasStagedPhoto)

                Button {
                    viewModel.toggleListening()
                } label: {
                    ZStack {
                        Circle()
                            .fill(viewModel.canUseMicrophone ? (viewModel.isListening ? Color.red : Color.accentColor) : Color.secondary.opacity(0.35))
                            .frame(width: 72, height: 72)

                        Image(systemName: viewModel.isListening ? "stop.fill" : "mic.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .disabled(!viewModel.canUseMicrophone)

                Button {
                    viewModel.replayLatestReply()
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.title3)
                        .frame(width: 52, height: 52)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .foregroundStyle(.primary)
                .disabled(!viewModel.hasReply)
            }
        }
    }

    private var cloudSyncDetail: String {
        if viewModel.backendSyncText.localizedCaseInsensitiveContains("syncing") {
            return "Syncing…"
        }
        if viewModel.pendingSyncCount > 0 {
            return "\(viewModel.pendingSyncCount) queued"
        }
        if let lastSyncedAt = viewModel.lastSyncedAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return "Synced \(formatter.localizedString(for: lastSyncedAt, relativeTo: Date()))"
        }
        return "Idle"
    }

    private func statusCard(title: String, detail: String, showCheck: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Text(detail)
                    .font(.body)
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 8)

            if showCheck {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private var cameraPopup: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { showingCameraPopup = false }

            VStack(spacing: 0) {
                ZStack {
                    if cameraController.isReady {
                        CameraPreview(session: cameraController.session)
                    } else {
                        Color.black.overlay {
                            VStack(spacing: 10) {
                                ProgressView()
                                Text(cameraController.statusText)
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.8))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                }
                .frame(width: 280, height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Button {
                        showingCameraPopup = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(.black.opacity(0.55), in: .circle)
                    }
                    .padding(10)
                }

                Button {
                    viewModel.captureSitePhoto()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 68, height: 68)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 56, height: 56)
                        if viewModel.isCapturingPhoto {
                            ProgressView()
                                .tint(.black)
                        }
                    }
                }
                .disabled(!cameraController.isReady || viewModel.isCapturingPhoto)
                .padding(.top, 20)
            }
        }
    }

    private func toastBanner(text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.green)
            Text(text)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
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
            name: AVCaptureSession.runtimeErrorNotification,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionInterrupted(_:)),
            name: AVCaptureSession.wasInterruptedNotification,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionInterruptionEnded(_:)),
            name: AVCaptureSession.interruptionEndedNotification,
            object: session
        )
    }

    private func publishStatus(_ text: String, ready: Bool) {
        Task { @MainActor in
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

    nonisolated private final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
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
