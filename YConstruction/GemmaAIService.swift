import Foundation

final class GemmaAIService: SiteVoiceAI {
    private var model: CactusModelT?
    private let queue = DispatchQueue(label: "com.yconstruction.gemma", qos: .userInitiated)

    func loadModel() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard let path = Self.resolveModelPath() else {
                        cont.resume(throwing: SiteVoiceAIError.modelNotLoaded)
                        return
                    }
                    self.model = try cactusInit(path, nil, false)
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    func transcribe(audio: Data) async throws -> String {
        guard let model else { throw SiteVoiceAIError.modelNotLoaded }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            queue.async {
                do {
                    let json = try cactusTranscribe(model, nil, nil, nil, nil as ((String, UInt32) -> Void)?, audio)
                    let text = Self.extractTranscript(from: json)
                    cont.resume(returning: text)
                } catch {
                    cont.resume(throwing: SiteVoiceAIError.transcriptionFailed(error.localizedDescription))
                }
            }
        }
    }

    func analyze(transcript: String, photo: Data) async throws -> DefectReport {
        guard let model else { throw SiteVoiceAIError.modelNotLoaded }

        let imagePath = try Self.writeTemporaryImage(photo)
        defer { try? FileManager.default.removeItem(atPath: imagePath) }

        let messages: [[String: Any]] = [
            ["role": "system", "content": SystemPrompts.defectAnalysis],
            ["role": "user", "content": transcript, "images": [imagePath]]
        ]
        let messagesJson = try Self.encodeJson(messages)
        let optionsJson = #"{"max_tokens":512,"temperature":0.2}"#

        let raw: String = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            queue.async {
                do {
                    let out = try cactusComplete(model, messagesJson, optionsJson, nil, nil)
                    cont.resume(returning: out)
                } catch {
                    cont.resume(throwing: SiteVoiceAIError.inferenceFailed(error.localizedDescription))
                }
            }
        }

        do {
            return try Self.parseReport(raw, transcript: transcript, photo: photo)
        } catch {
            let retryMessages: [[String: Any]] = [
                ["role": "system", "content": SystemPrompts.defectAnalysis],
                ["role": "user", "content": transcript, "images": [imagePath]],
                ["role": "assistant", "content": raw],
                ["role": "user", "content": "Your previous response was not valid JSON. Output only the JSON object, nothing else."]
            ]
            let retryJson = try Self.encodeJson(retryMessages)
            let retryRaw: String = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                queue.async {
                    do {
                        let out = try cactusComplete(model, retryJson, optionsJson, nil, nil)
                        cont.resume(returning: out)
                    } catch {
                        cont.resume(throwing: SiteVoiceAIError.inferenceFailed(error.localizedDescription))
                    }
                }
            }
            return try Self.parseReport(retryRaw, transcript: transcript, photo: photo)
        }
    }

    deinit {
        if let model { cactusDestroy(model) }
    }

    // MARK: - Helpers

    private static func resolveModelPath() -> String? {
        let fm = FileManager.default
        let candidates = [
            Bundle.main.path(forResource: "gemma-4-E2B-it", ofType: nil),
            (fm.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("gemma-4-E2B-it").path),
            NSString(string: "~/Desktop/cactus/weights/gemma-4-E2B-it").expandingTildeInPath
        ]
        return candidates.compactMap { $0 }.first { fm.fileExists(atPath: $0) }
    }

    private static func writeTemporaryImage(_ data: Data) throws -> String {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("inspection-\(UUID().uuidString).jpg")
        try data.write(to: url)
        return url.path
    }

    private static func encodeJson(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [])
        guard let s = String(data: data, encoding: .utf8) else {
            throw SiteVoiceAIError.malformedResponse("could not encode messages")
        }
        return s
    }

    private static func extractTranscript(from json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return json
        }
        if let text = obj["text"] as? String { return text }
        if let segs = obj["segments"] as? [[String: Any]] {
            return segs.compactMap { $0["text"] as? String }.joined(separator: " ")
        }
        return json
    }

    private static func parseReport(_ raw: String, transcript: String, photo: Data) throws -> DefectReport {
        let cleaned = stripFences(raw)
        guard let range = cleaned.range(of: #"\{[\s\S]*\}"#, options: .regularExpression),
              let data = String(cleaned[range]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SiteVoiceAIError.malformedResponse(raw)
        }

        let defectType = obj["defect_type"] as? String ?? "other"
        let severityStr = (obj["severity"] as? String) ?? "low"
        let severity = DefectReport.Severity(rawValue: severityStr) ?? .low
        let visual = obj["visual_description"] as? String ?? ""
        let spoken = obj["spoken_response"] as? String ?? visual
        let code = obj["code_reference_id"] as? String
        let confidence = (obj["confidence"] as? NSNumber)?.doubleValue ?? 0.0

        return DefectReport(
            defectType: defectType,
            location: "",
            severity: severity,
            visualDescription: visual,
            spokenResponse: spoken,
            transcript: transcript,
            codeReferenceId: code?.isEmpty == true ? nil : code,
            confidence: confidence,
            photoData: photo,
            timestamp: Date()
        )
    }

    private static func stripFences(_ s: String) -> String {
        var out = s
        if let start = out.range(of: "```json") { out.removeSubrange(start) }
        if let start = out.range(of: "```") { out.removeSubrange(start) }
        if let end = out.range(of: "```", options: .backwards) { out.removeSubrange(end) }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
