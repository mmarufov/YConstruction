import SwiftUI
import PhotosUI

enum InspectionPhase: Equatable {
    case ready
    case recording
    case transcribing
    case analyzing
    case complete(DefectReport)
    case failed(String)
}

struct InspectionView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var camera = CameraCaptureController()
    @StateObject private var mic = MicRecorder()

    @State private var phase: InspectionPhase = .ready
    @State private var transcript: String = ""
    @State private var capturedPhoto: Data?
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            #if targetEnvironment(simulator)
            simulatorFallback
            #else
            if camera.isReady {
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text("Starting camera…").foregroundStyle(.white)
                }
            }
            #endif

            VStack {
                topBar
                Spacer()
                bottomBar
            }
            .padding(.horizontal)
            .padding(.vertical, 20)

            if case .analyzing = phase {
                overlay("Analyzing with Gemma…")
            }
            if case .transcribing = phase {
                overlay("Transcribing voice…")
            }
        }
        .onAppear { camera.configure() }
        .onDisappear { camera.stop() }
        .navigationDestination(isPresented: .constant(completedReport != nil)) {
            if let r = completedReport {
                ReportView(report: r, canSave: true, onSave: { saved in
                    app.punchList.add(saved)
                    dismiss()
                })
            }
        }
    }

    private var completedReport: DefectReport? {
        if case .complete(let r) = phase { return r }
        return nil
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white, .black.opacity(0.4))
            }
            Spacer()
            if mic.isRecording {
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 10, height: 10)
                    Text("Recording").font(.caption.bold()).foregroundStyle(.white)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.black.opacity(0.5)).clipShape(Capsule())
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 16) {
            if !transcript.isEmpty {
                Text("\"\(transcript)\"")
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 8)
            }

            HStack(spacing: 40) {
                talkButton
                captureButton
            }
            .padding(.bottom, 24)
        }
    }

    private var talkButton: some View {
        Button {} label: {
            ZStack {
                Circle()
                    .fill(mic.isRecording ? Color.red : Color.white.opacity(0.85))
                    .frame(width: 72, height: 72)
                Image(systemName: mic.isRecording ? "mic.fill" : "mic")
                    .font(.title)
                    .foregroundStyle(mic.isRecording ? .white : .black)
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0)
                .onChanged { _ in
                    if !mic.isRecording {
                        Task { await mic.start() }
                    }
                }
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onEnded { _ in
                    Task { await finishRecording() }
                }
        )
        .disabled(!phaseAllowsCapture)
    }

    private var captureButton: some View {
        Button {
            Task { await capturePhoto() }
        } label: {
            ZStack {
                Circle().stroke(.white, lineWidth: 4).frame(width: 80, height: 80)
                Circle().fill(.white).frame(width: 66, height: 66)
                Image(systemName: "camera.fill").font(.title2).foregroundStyle(.black)
            }
        }
        .disabled(!phaseAllowsCapture)
    }

    private var phaseAllowsCapture: Bool {
        switch phase {
        case .ready, .recording: return true
        default: return false
        }
    }

    private func overlay(_ text: String) -> some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().scaleEffect(1.6).tint(.white)
                Text(text).foregroundStyle(.white).font(.headline)
            }
        }
    }

    // MARK: - Flow

    private func finishRecording() async {
        guard let audio = mic.stop(), !audio.isEmpty else { return }
        phase = .transcribing
        do {
            transcript = try await app.ai.transcribe(audio: audio)
            phase = .ready
        } catch {
            transcript = ""
            phase = .failed(error.localizedDescription)
        }
    }

    private func capturePhoto() async {
        do {
            #if targetEnvironment(simulator)
            guard let data = capturedPhoto else { return }
            #else
            let data = try await camera.capturePhoto()
            capturedPhoto = data
            #endif

            if transcript.isEmpty {
                transcript = "Flag this area for review."
            }
            phase = .analyzing
            let report = try await app.ai.analyze(transcript: transcript, photo: data)
            phase = .complete(report)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Simulator fallback

    #if targetEnvironment(simulator)
    private var simulatorFallback: some View {
        VStack(spacing: 20) {
            Text("Simulator Mode")
                .font(.title.bold())
                .foregroundStyle(.white)

            if let data = capturedPhoto, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable().scaledToFit()
                    .frame(maxHeight: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.1))
                    .overlay(Text("Pick a photo to test").foregroundStyle(.white))
                    .frame(height: 300)
            }

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Pick a photo", systemImage: "photo.on.rectangle")
                    .padding(12)
                    .background(.white.opacity(0.2))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .onChange(of: pickerItem) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self) {
                        capturedPhoto = data
                    }
                }
            }
        }
        .padding()
    }
    #endif
}
