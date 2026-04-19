import Foundation
import AVFoundation

enum STTServiceError: Error, LocalizedError {
    case micPermissionDenied
    case audioSessionFailed(String)
    case audioEngineStartFailed(String)
    case converterCreationFailed
    case notStreaming

    var errorDescription: String? {
        switch self {
        case .micPermissionDenied: return "Microphone permission denied"
        case .audioSessionFailed(let m): return "Audio session error: \(m)"
        case .audioEngineStartFailed(let m): return "Audio engine start failed: \(m)"
        case .converterCreationFailed: return "Could not create 16 kHz mono audio converter"
        case .notStreaming: return "No active STT stream"
        }
    }
}

struct STTPartial: Sendable {
    let text: String
    let isFinal: Bool
}

struct STTFinalResult: Sendable {
    let text: String
    let language: String?
}

actor STTService {
    static let shared = STTService()

    private let cactus: CactusService
    private var audioEngine: AVAudioEngine?
    private var streamHandle: CactusStreamTranscribeT?
    private var continuation: AsyncStream<STTPartial>.Continuation?
    private var accumulatedText: String = ""

    private init(cactus: CactusService = .shared) {
        self.cactus = cactus
    }

    static func requestMicPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    func startStreaming() async throws -> AsyncStream<STTPartial> {
        guard await Self.requestMicPermission() else {
            throw STTServiceError.micPermissionDenied
        }

        let whisper = try await cactus.loadWhisper()
        let handle = try cactusStreamTranscribeStart(whisper, nil)

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            try? cactusStreamTranscribeStop(handle)
            deactivateAudioSession()
            throw STTServiceError.audioSessionFailed(error.localizedDescription)
        }

        let engine = AVAudioEngine()
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        ), let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            try? cactusStreamTranscribeStop(handle)
            deactivateAudioSession()
            throw STTServiceError.converterCreationFailed
        }

        self.streamHandle = handle
        self.accumulatedText = ""

        let stream = AsyncStream<STTPartial> { cont in
            self.continuation = cont
            cont.onTermination = { @Sendable _ in
                Task { await self.handleContinuationTermination() }
            }
        }

        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let pcmData = Self.convertAndPack(buffer: buffer, converter: converter, targetFormat: targetFormat)
            guard !pcmData.isEmpty else { return }
            Task { await self.feed(pcmData) }
        }

        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            self.streamHandle = nil
            self.continuation = nil
            self.accumulatedText = ""
            try? cactusStreamTranscribeStop(handle)
            deactivateAudioSession()
            throw STTServiceError.audioEngineStartFailed(error.localizedDescription)
        }

        self.audioEngine = engine
        return stream
    }

    func stopStreaming() async throws -> STTFinalResult {
        guard let handle = streamHandle else {
            throw STTServiceError.notStreaming
        }

        teardownEngine()
        streamHandle = nil
        let finalJson = (try? cactusStreamTranscribeStop(handle)) ?? "{}"
        deactivateAudioSession()
        continuation?.finish()
        continuation = nil

        let parsed = Self.parse(json: finalJson)
        let text = parsed.text.isEmpty ? accumulatedText : parsed.text
        accumulatedText = ""
        return STTFinalResult(text: text, language: parsed.language)
    }

    private func feed(_ pcmData: Data) async {
        guard let handle = streamHandle else { return }
        do {
            let partialJson = try cactusStreamTranscribeProcess(handle, pcmData)
            let parsed = Self.parse(json: partialJson)
            if !parsed.text.isEmpty {
                accumulatedText = parsed.text
                continuation?.yield(STTPartial(text: parsed.text, isFinal: false))
            }
        } catch {
            continuation?.finish()
        }
    }

    private func handleContinuationTermination() {
        continuation = nil
        teardownEngine()
        if let handle = streamHandle {
            streamHandle = nil
            _ = try? cactusStreamTranscribeStop(handle)
        }
        accumulatedText = ""
        deactivateAudioSession()
    }

    private func teardownEngine() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Helpers

    private static func convertAndPack(
        buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) -> Data {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputCapacity
        ) else { return Data() }

        var fed = false
        var err: NSError?
        let status = converter.convert(to: outputBuffer, error: &err) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, err == nil,
              let int16Data = outputBuffer.int16ChannelData else {
            return Data()
        }
        let frames = Int(outputBuffer.frameLength)
        let channels = Int(targetFormat.channelCount)
        let byteCount = frames * channels * MemoryLayout<Int16>.size
        return Data(bytes: int16Data[0], count: byteCount)
    }

    private static func parse(json: String) -> (text: String, language: String?) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ("", nil)
        }
        let text = (obj["text"] as? String) ?? ""
        let language = obj["language"] as? String
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), language)
    }
}
