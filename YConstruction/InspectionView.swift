import SwiftUI
import PhotosUI

enum InspectionState: Equatable {
    case idle
    case listening
    case thinking
    case speaking
    case failed(String)
}

struct InspectionView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var camera = CameraCaptureController()
    @StateObject private var mic = MicRecorder()
    @StateObject private var tts = SpeechSynthesizer()

    @State private var state: InspectionState = .idle
    @State private var latestTranscript: String = ""
    @State private var latestReport: DefectReport?
    @State private var pickerItem: PhotosPickerItem?
    @State private var simulatorPhoto: Data?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            #if targetEnvironment(simulator)
            simulatorFallback
            #else
            if camera.isReady {
                CameraPreviewView(session: camera.session).ignoresSafeArea()
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
                transcriptBubble
                stateLabel
                micButton
            }
            .padding(.horizontal)
            .padding(.vertical, 20)
        }
        .onAppear {
            camera.configure()
            mic.onUtterance = { data in
                Task { await handleUtterance(audio: data) }
            }
        }
        .onDisappear {
            mic.stopListening()
            tts.stop()
            camera.stop()
        }
    }

    // MARK: - UI

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
            if let r = latestReport {
                Button {
                    app.punchList.add(r)
                    latestReport = nil
                } label: {
                    Label("Save to Punch List", systemImage: "plus.circle.fill")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.white.opacity(0.9))
                        .foregroundStyle(.black)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var transcriptBubble: some View {
        Group {
            if !latestTranscript.isEmpty {
                Text("\"\(latestTranscript)\"")
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 8)
            }
            if let r = latestReport {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(r.defectType.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.headline).foregroundStyle(.white)
                        Spacer()
                        SeverityBadge(severity: r.severity)
                    }
                    Text(r.spokenResponse).font(.subheadline).foregroundStyle(.white.opacity(0.9))
                    if let code = r.codeReferenceId {
                        Text(code).font(.caption).foregroundStyle(.cyan)
                    }
                }
                .padding(12)
                .background(.black.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 8)
            }
        }
    }

    private var stateLabel: some View {
        HStack(spacing: 10) {
            stateIcon
            Text(stateText)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.black.opacity(0.55))
        .clipShape(Capsule())
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch state {
        case .idle:
            Image(systemName: "mic.slash.fill").foregroundStyle(.white.opacity(0.8))
        case .listening:
            Circle().fill(.red).frame(width: 10, height: 10)
        case .thinking:
            ProgressView().controlSize(.small).tint(.white)
        case .speaking:
            Image(systemName: "speaker.wave.2.fill").foregroundStyle(.cyan)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private var stateText: String {
        switch state {
        case .idle: return "Tap mic to start"
        case .listening: return "Listening…"
        case .thinking: return "Analyzing…"
        case .speaking: return "Speaking…"
        case .failed(let e): return "Error: \(e)"
        }
    }

    private var micButton: some View {
        Button {
            Task { await toggleMic() }
        } label: {
            ZStack {
                Circle()
                    .fill(mic.isListening ? Color.red : Color.white.opacity(0.9))
                    .frame(width: 88, height: 88)
                    .shadow(radius: 8)
                Image(systemName: mic.isListening ? "mic.fill" : "mic")
                    .font(.system(size: 34))
                    .foregroundStyle(mic.isListening ? .white : .black)

                if mic.isListening {
                    Circle()
                        .stroke(.red.opacity(0.4), lineWidth: 4)
                        .frame(width: 88 + CGFloat(mic.audioLevel) * 40,
                               height: 88 + CGFloat(mic.audioLevel) * 40)
                        .animation(.easeOut(duration: 0.1), value: mic.audioLevel)
                }
            }
        }
        .padding(.bottom, 24)
    }

    // MARK: - Flow

    private func toggleMic() async {
        if mic.isListening {
            mic.stopListening()
            state = .idle
        } else {
            latestTranscript = ""
            latestReport = nil
            state = .listening
            await mic.startListening()
        }
    }

    private func handleUtterance(audio: Data) async {
        state = .thinking

        do {
            latestTranscript = try await app.ai.transcribe(audio: audio)
        } catch {
            state = .failed("Transcription: \(error.localizedDescription)")
            return
        }

        let photo: Data
        do {
            photo = try await capturePhoto()
        } catch {
            state = .failed("Camera: \(error.localizedDescription)")
            return
        }

        do {
            let report = try await app.ai.analyze(transcript: latestTranscript, photo: photo)
            latestReport = report
            state = .speaking
            tts.speak(report.spokenResponse) {
                Task { @MainActor in
                    if mic.isListening {
                        state = .listening
                    } else {
                        state = .idle
                    }
                }
            }
        } catch {
            state = .failed("Gemma: \(error.localizedDescription)")
        }
    }

    private func capturePhoto() async throws -> Data {
        #if targetEnvironment(simulator)
        guard let data = simulatorPhoto else {
            throw NSError(domain: "sim", code: -1, userInfo: [NSLocalizedDescriptionKey: "Pick a photo first"])
        }
        return data
        #else
        return try await camera.capturePhoto()
        #endif
    }

    // MARK: - Simulator fallback

    #if targetEnvironment(simulator)
    private var simulatorFallback: some View {
        VStack(spacing: 16) {
            Text("Simulator Mode")
                .font(.title.bold()).foregroundStyle(.white)

            if let data = simulatorPhoto, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable().scaledToFit()
                    .frame(maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.1))
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "photo").font(.largeTitle).foregroundStyle(.white)
                            Text("Pick a photo to simulate camera").foregroundStyle(.white)
                        }
                    )
                    .frame(height: 300)
            }

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(simulatorPhoto == nil ? "Pick photo" : "Change photo", systemImage: "photo.on.rectangle")
                    .padding(12)
                    .background(.white.opacity(0.2))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .onChange(of: pickerItem) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self) {
                        simulatorPhoto = data
                    }
                }
            }
        }
        .padding()
    }
    #endif
}
