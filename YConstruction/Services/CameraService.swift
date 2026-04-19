import Foundation
import AVFoundation
import UIKit

enum CameraServiceError: Error, LocalizedError {
    case permissionDenied
    case noCamera
    case sessionConfigurationFailed(String)
    case captureInProgress
    case captureFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Camera permission denied"
        case .noCamera: return "No rear camera available on this device"
        case .sessionConfigurationFailed(let m): return "Camera setup failed: \(m)"
        case .captureInProgress: return "A photo capture is already in progress"
        case .captureFailed(let m): return "Photo capture failed: \(m)"
        case .writeFailed(let m): return "Could not save photo: \(m)"
        }
    }
}

nonisolated final class CameraService: NSObject {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.yconstruction.camera", qos: .userInitiated)
    private var currentCaptureContinuation: CheckedContinuation<URL, Error>?
    private var currentProjectId: String?
    private var isConfigured: Bool = false

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    func configure() async throws {
        guard await Self.requestPermission() else { throw CameraServiceError.permissionDenied }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.configureSessionIfNeeded()
                    self.isConfigured = true
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    func start() {
        sessionQueue.async {
            guard self.isConfigured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func capturePhoto(projectId: String) async throws -> URL {
        return try await withCheckedThrowingContinuation { cont in
            self.sessionQueue.async {
                guard self.isConfigured else {
                    cont.resume(throwing: CameraServiceError.sessionConfigurationFailed("call configure() first"))
                    return
                }
                guard self.currentCaptureContinuation == nil else {
                    cont.resume(throwing: CameraServiceError.captureInProgress)
                    return
                }

                self.currentProjectId = projectId
                self.currentCaptureContinuation = cont

                let settings = AVCapturePhotoSettings()
                settings.flashMode = .auto
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    // MARK: - Private

    private func configureSessionIfNeeded() throws {
        guard !isConfigured else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        if session.inputs.isEmpty {
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video)
            else {
                throw CameraServiceError.noCamera
            }

            do {
                let input = try AVCaptureDeviceInput(device: camera)
                guard session.canAddInput(input) else {
                    throw CameraServiceError.sessionConfigurationFailed("cannot add camera input")
                }
                session.addInput(input)
            } catch let err as CameraServiceError {
                throw err
            } catch {
                throw CameraServiceError.sessionConfigurationFailed(error.localizedDescription)
            }
        }

        if !session.outputs.contains(where: { $0 === photoOutput }) {
            guard session.canAddOutput(photoOutput) else {
                throw CameraServiceError.sessionConfigurationFailed("cannot add photo output")
            }
            session.addOutput(photoOutput)
        }
        photoOutput.maxPhotoQualityPrioritization = .quality
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let result: Result<Data, Error>
        if let error {
            result = .failure(CameraServiceError.captureFailed(error.localizedDescription))
        } else if let data = photo.fileDataRepresentation() {
            result = .success(data)
        } else {
            result = .failure(CameraServiceError.captureFailed("no photo data"))
        }

        sessionQueue.async {
            guard let cont = self.currentCaptureContinuation else { return }
            self.currentCaptureContinuation = nil
            let projectId = self.currentProjectId
            self.currentProjectId = nil

            switch result {
            case .failure(let err):
                cont.resume(throwing: err)
            case .success(let data):
                do {
                    guard let projectId else {
                        throw CameraServiceError.writeFailed("missing project id")
                    }
                    let url = try Self.writePhoto(data: data, projectId: projectId)
                    cont.resume(returning: url)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private static func writePhoto(data: Data, projectId: String) throws -> URL {
        let dir = try AppConfig.photosDirectory(projectId: projectId)
        let url = dir.appendingPathComponent("\(UUID().uuidString).jpg")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw CameraServiceError.writeFailed(error.localizedDescription)
        }
    }
}
