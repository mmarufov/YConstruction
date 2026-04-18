import SwiftUI
import AVFoundation
import UIKit

final class CameraCaptureController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published var isReady: Bool = false
    @Published var lastError: String?

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.yconstruction.camera.session")
    private var captureContinuation: CheckedContinuation<Data, Error>?

    func configure() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input)
            else {
                DispatchQueue.main.async { self.lastError = "Camera unavailable" }
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)

            if self.session.canAddOutput(self.output) {
                self.session.addOutput(self.output)
            }
            self.session.commitConfiguration()
            self.session.startRunning()
            DispatchQueue.main.async { self.isReady = true }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    func capturePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            self.captureContinuation = cont
            let settings = AVCapturePhotoSettings()
            sessionQueue.async { [weak self] in
                self?.output.capturePhoto(with: settings, delegate: self!)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            captureContinuation?.resume(throwing: error)
        } else if let data = photo.fileDataRepresentation() {
            captureContinuation?.resume(returning: data)
        } else {
            captureContinuation?.resume(throwing: NSError(domain: "camera", code: -1, userInfo: [NSLocalizedDescriptionKey: "No photo data"]))
        }
        captureContinuation = nil
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
