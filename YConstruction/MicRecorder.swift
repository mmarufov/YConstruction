import Foundation
import AVFoundation

@MainActor
final class MicRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published var lastError: String?

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    func start() async {
        await requestPermission()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: [])
        } catch {
            lastError = "Audio session: \(error.localizedDescription)"
            return
        }

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("inspection-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        do {
            recorder = try AVAudioRecorder(url: tmp, settings: settings)
            recorder?.record()
            fileURL = tmp
            isRecording = true
        } catch {
            lastError = "Recorder: \(error.localizedDescription)"
        }
    }

    func stop() -> Data? {
        recorder?.stop()
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        guard let url = fileURL else { return nil }
        defer { try? FileManager.default.removeItem(at: url) }
        return try? Data(contentsOf: url)
    }

    private func requestPermission() async {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { _ in cont.resume() }
        }
    }
}
