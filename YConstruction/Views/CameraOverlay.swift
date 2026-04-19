import SwiftUI
import AVFoundation

struct CameraOverlay: View {
    let reason: String
    let projectId: String
    let camera: CameraService
    let onCapture: (URL) -> Void
    let onCancel: () -> Void

    @State private var isCapturing = false
    @State private var errorText: String?
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if errorText == nil {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            if let countdown, countdown > 0 {
                Text("\(countdown)")
                    .font(.system(size: 160, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 12)
                    .transition(.scale(scale: 1.4).combined(with: .opacity))
                    .id("countdown-\(countdown)")
            }

            VStack {
                HStack {
                    Button(action: handleCancel) {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.bold))
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                }
                .padding()

                Spacer()

                VStack(spacing: 16) {
                    Text(reason)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding()
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)

                    if countdown != nil {
                        Text("Auto-capturing — aim at the defect")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.black.opacity(0.55), in: Capsule())
                    }

                    if let errorText {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .padding()
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal)
                    }

                    Button {
                        Task { await captureNow() }
                    } label: {
                        ZStack {
                            Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                            Circle().fill(isCapturing ? .gray : .white).frame(width: 64, height: 64)
                        }
                    }
                    .disabled(isCapturing)
                }
                .padding(.bottom, 40)
            }
        }
        .task {
            do {
                try await camera.configure()
                camera.start()
                startCountdown()
            } catch {
                await MainActor.run { errorText = error.localizedDescription }
            }
        }
        .onDisappear {
            countdownTask?.cancel()
            countdownTask = nil
            camera.stop()
        }
    }

    private func startCountdown() {
        countdownTask?.cancel()
        countdownTask = Task { @MainActor in
            for i in stride(from: 3, through: 1, by: -1) {
                withAnimation(.easeOut(duration: 0.25)) { countdown = i }
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
                if Task.isCancelled { return }
            }
            withAnimation { countdown = nil }
            guard !Task.isCancelled else { return }
            await capture()
        }
    }

    private func handleCancel() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
        onCancel()
    }

    private func captureNow() async {
        countdownTask?.cancel()
        countdownTask = nil
        withAnimation { countdown = nil }
        await capture()
    }

    private func capture() async {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }
        do {
            let url = try await camera.capturePhoto(projectId: projectId)
            onCapture(url)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session = session
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
