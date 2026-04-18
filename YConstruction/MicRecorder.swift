import Foundation
import AVFoundation
import Combine

@MainActor
final class MicRecorder: ObservableObject {
    @Published private(set) var isListening = false
    @Published var audioLevel: Float = 0
    @Published var lastError: String?

    var onUtterance: ((Data) -> Void)?

    private var recorder: AVAudioRecorder?
    private var currentFileURL: URL?
    private var meterTimer: Timer?

    private let silenceThreshold: Float = -40.0
    private let speechThreshold: Float = -28.0
    private let silenceDurationSec: Double = 1.2
    private let minSpeechDurationSec: Double = 0.4

    private var hasSpokenSinceStart = false
    private var speechStart: Date?
    private var lastSpeechActivity: Date?

    func startListening() async {
        guard !isListening else { return }
        await requestPermission()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: [])
        } catch {
            lastError = "Audio session: \(error.localizedDescription)"
            return
        }

        isListening = true
        startUtteranceRecorder()
    }

    func stopListening() {
        isListening = false
        meterTimer?.invalidate()
        meterTimer = nil
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        if let url = currentFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        currentFileURL = nil
        hasSpokenSinceStart = false
        speechStart = nil
        lastSpeechActivity = nil
        audioLevel = 0
    }

    private func startUtteranceRecorder() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("utterance-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        do {
            let rec = try AVAudioRecorder(url: tmp, settings: settings)
            rec.isMeteringEnabled = true
            rec.record()
            recorder = rec
            currentFileURL = tmp
            hasSpokenSinceStart = false
            speechStart = nil
            lastSpeechActivity = Date()
            startMeterTimer()
        } catch {
            lastError = "Recorder: \(error.localizedDescription)"
        }
    }

    private func startMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickMeter() }
        }
    }

    private func tickMeter() {
        guard isListening, let rec = recorder else { return }
        rec.updateMeters()
        let power = rec.averagePower(forChannel: 0)
        audioLevel = max(0, min(1, (power + 60) / 60))

        let now = Date()
        if power > speechThreshold {
            if !hasSpokenSinceStart {
                hasSpokenSinceStart = true
                speechStart = now
            }
            lastSpeechActivity = now
        } else if power < silenceThreshold, hasSpokenSinceStart {
            if let last = lastSpeechActivity,
               let start = speechStart,
               now.timeIntervalSince(last) >= silenceDurationSec,
               now.timeIntervalSince(start) >= minSpeechDurationSec {
                finalizeUtterance()
            }
        }
    }

    private func finalizeUtterance() {
        guard let rec = recorder, let url = currentFileURL else { return }
        rec.stop()
        meterTimer?.invalidate()
        meterTimer = nil

        let data = try? Data(contentsOf: url)
        try? FileManager.default.removeItem(at: url)
        recorder = nil
        currentFileURL = nil

        if let data, !data.isEmpty {
            onUtterance?(data)
        }

        if isListening {
            startUtteranceRecorder()
        }
    }

    private func requestPermission() async {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { _ in cont.resume() }
        }
    }
}
