import Foundation

nonisolated private func ycLog(_ message: String) {
    print("[YC][Cactus] \(message)")
}

/// Thread-safe one-shot latch that logs the time-to-first-token exactly once.
nonisolated final class FirstTokenLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func markIfFirst(elapsedSince started: Date) {
        lock.lock()
        let shouldFire = !fired
        fired = true
        lock.unlock()
        guard shouldFire else { return }
        let elapsed = Date().timeIntervalSince(started)
        ycLog("[sendStreaming] first token at \(String(format: "%.2f", elapsed))s")
    }
}

actor CactusAIService: AIService {
    nonisolated struct ModelSearchPath {
        let subdirectory: String?
        let folderName: String
    }

    nonisolated struct ChatPayloadMessage: Encodable, Equatable {
        let role: String
        let content: String
        let images: [String]?
        let audio: [String]?

        init(role: String, content: String, images: [String]? = nil, audio: [String]? = nil) {
            self.role = role
            self.content = content
            self.images = images?.isEmpty == false ? images : nil
            self.audio = audio?.isEmpty == false ? audio : nil
        }
    }

    nonisolated enum SetupError: LocalizedError {
        case missingInstalledModel(String)
        case emptyModelResponse

        var errorDescription: String? {
            switch self {
            case .missingInstalledModel(let modelFolderName):
                return """
                \(LocalModelStore.displayName) is not installed locally yet.

                Import the `\(modelFolderName)` folder from Files, or copy it into the app with Finder:
                iPhone > Files > YConstructionMVP.
                """
            case .emptyModelResponse:
                return "\(LocalModelStore.displayName) returned an empty response."
            }
        }
    }

    private let modelFolderName: String
    private let systemPrompt: String
    private let defaultMaxTokens: Int
    private let answerOptionsJSONTemplate: String
    private var modelHandle: CactusModelHandle?
    private var loadedModelPath: String?
    private var lastRuntimeStatsStore: AIRuntimeStats?

    init(
        modelFolderName: String = LocalModelStore.modelFolderName,
        systemPrompt: String = "You are a practical on-site construction assistant. Answer briefly and concretely. If the prompt asks for JSON, return valid JSON only.",
        defaultMaxTokens: Int = 192,
        answerOptionsJSONTemplate: String = #""temperature":0.0,"top_p":0.0,"top_k":1,"confidence_threshold":0.0,"auto_handoff":false,"telemetry_enabled":false,"enable_thinking_if_supported":false"#
    ) {
        self.modelFolderName = modelFolderName
        self.systemPrompt = systemPrompt
        self.defaultMaxTokens = defaultMaxTokens
        self.answerOptionsJSONTemplate = answerOptionsJSONTemplate
    }

    func prewarm() async throws -> AIModelPrewarmResult {
        let (_, modelPath) = try await loadModelIfNeeded()
        return AIModelPrewarmResult(modelPath: modelPath)
    }

    func send(request: AIRequest, conversation: [Message]) async throws -> AIResponse {
        let (model, _) = try await loadModelIfNeeded()
        _ = conversation

        let promptLen = request.prompt.count
        let imagesCount = request.imagePaths.count
        let audioCount = request.audioPaths.count
        let maxTokens = request.maxTokens ?? defaultMaxTokens
        ycLog("[send] start promptLen=\(promptLen) images=\(imagesCount) audio=\(audioCount) maxTokens=\(maxTokens)")
        let started = Date()

        let heartbeat = Task.detached {
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { return }
                ticks += 1
                ycLog("[send] still running… ~\(ticks * 5)s")
            }
        }
        defer { heartbeat.cancel() }

        CactusRuntime.resetModel(model)
        let payload = try Self.makeMessagesPayload(
            systemPrompt: systemPrompt,
            userContent: request.prompt,
            imagePaths: request.imagePaths,
            audioPaths: request.audioPaths
        )

        do {
            let completion = try complete(
                model: model,
                messagesJSON: payload,
                optionsJSON: makeOptionsJSON(maxTokens: request.maxTokens),
                pcmData: request.audioPCMData
            )
            CactusRuntime.resetModel(model)
            let elapsed = Date().timeIntervalSince(started)
            let decode = completion.runtimeStats.decodeTokensPerSecond ?? 0
            ycLog("[send] done in \(String(format: "%.2f", elapsed))s textLen=\(completion.text.count) decode=\(String(format: "%.1f", decode))tok/s")
            lastRuntimeStatsStore = completion.runtimeStats
            return AIResponse(text: completion.text, runtimeStats: completion.runtimeStats)
        } catch {
            CactusRuntime.resetModel(model)
            let elapsed = Date().timeIntervalSince(started)
            ycLog("[send] ERROR failed after \(String(format: "%.2f", elapsed))s error=\(error.localizedDescription)")
            throw error
        }
    }

    private func makeOptionsJSON(maxTokens: Int?) -> String {
        let effectiveMaxTokens = maxTokens ?? defaultMaxTokens
        return #"{"max_tokens":\#(effectiveMaxTokens),\#(answerOptionsJSONTemplate)}"#
    }

    func latestRuntimeStats() async -> AIRuntimeStats? {
        lastRuntimeStatsStore
    }

    private func loadModelIfNeeded() async throws -> (model: CactusModelHandle, modelPath: String) {
        if let modelHandle, let loadedModelPath {
            return (modelHandle, loadedModelPath)
        }

        guard let modelURL = try await LocalModelStore.shared.installedModelURL() ?? findBundledModelURL() else {
            throw SetupError.missingInstalledModel(modelFolderName)
        }

        let handle = try CactusRuntime.initializeModel(at: modelURL.path)
        modelHandle = handle
        loadedModelPath = modelURL.path
        return (handle, modelURL.path)
    }

    private func findBundledModelURL() -> URL? {
        let candidates = [
            ModelSearchPath(subdirectory: nil, folderName: modelFolderName),
            ModelSearchPath(subdirectory: "ModelAssets", folderName: modelFolderName)
        ]

        for candidate in candidates {
            if let url = Bundle.main.url(
                forResource: candidate.folderName,
                withExtension: nil,
                subdirectory: candidate.subdirectory
            ) {
                return url
            }
        }

        // Xcode may flatten a dragged model folder into individual resource files
        // at the root of the app bundle. In that case, point Cactus at the bundle
        // directory itself so it can resolve the expected filenames from there.
        if hasFlattenedModelResources() {
            return Bundle.main.bundleURL
        }

        return nil
    }

    private func hasFlattenedModelResources() -> Bool {
        let requiredFiles = [
            "config.txt",
            "tokenizer.json",
            "token_embeddings.weights"
        ]

        return requiredFiles.allSatisfy { filename in
            Bundle.main.url(forResource: filename, withExtension: nil) != nil
        }
    }

    private func complete(
        model: CactusModelHandle,
        messagesJSON: String,
        optionsJSON: String,
        pcmData: Data?,
        onToken: (@Sendable (String) -> Void)? = nil
    ) throws -> (text: String, runtimeStats: AIRuntimeStats) {
        let rawResult = try CactusRuntime.complete(
            model: model,
            messagesJSON: messagesJSON,
            optionsJSON: optionsJSON,
            pcmData: pcmData,
            onToken: onToken
        )

        let envelope = try CactusRuntime.decodeCompletionEnvelope(from: rawResult)
        if let error = envelope.error, !error.isEmpty {
            throw CactusRuntimeError.completionFailed(error)
        }

        guard let response = envelope.response?.trimmingCharacters(in: .whitespacesAndNewlines),
              !response.isEmpty else {
            throw SetupError.emptyModelResponse
        }

        return (response, envelope.runtimeStats)
    }

    func sendStreaming(
        request: AIRequest,
        conversation: [Message],
        onToken: @Sendable @escaping (String) -> Void
    ) async throws -> AIResponse {
        let (model, _) = try await loadModelIfNeeded()
        _ = conversation

        let promptLen = request.prompt.count
        let imagesCount = request.imagePaths.count
        let audioCount = request.audioPaths.count
        let maxTokens = request.maxTokens ?? defaultMaxTokens
        ycLog("[sendStreaming] start promptLen=\(promptLen) images=\(imagesCount) audio=\(audioCount) maxTokens=\(maxTokens)")
        let started = Date()
        let firstTokenFlag = FirstTokenLatch()

        let heartbeat = Task.detached {
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { return }
                ticks += 1
                ycLog("[sendStreaming] still running… ~\(ticks * 5)s")
            }
        }
        defer { heartbeat.cancel() }

        CactusRuntime.resetModel(model)
        let payload = try Self.makeMessagesPayload(
            systemPrompt: systemPrompt,
            userContent: request.prompt,
            imagePaths: request.imagePaths,
            audioPaths: request.audioPaths
        )

        let wrappedOnToken: @Sendable (String) -> Void = { token in
            firstTokenFlag.markIfFirst(elapsedSince: started)
            onToken(token)
        }

        do {
            let completion = try complete(
                model: model,
                messagesJSON: payload,
                optionsJSON: makeOptionsJSON(maxTokens: request.maxTokens),
                pcmData: request.audioPCMData,
                onToken: wrappedOnToken
            )
            CactusRuntime.resetModel(model)
            let elapsed = Date().timeIntervalSince(started)
            let decode = completion.runtimeStats.decodeTokensPerSecond ?? 0
            ycLog("[sendStreaming] done in \(String(format: "%.2f", elapsed))s textLen=\(completion.text.count) decode=\(String(format: "%.1f", decode))tok/s")
            lastRuntimeStatsStore = completion.runtimeStats
            return AIResponse(text: completion.text, runtimeStats: completion.runtimeStats)
        } catch {
            CactusRuntime.resetModel(model)
            let elapsed = Date().timeIntervalSince(started)
            ycLog("[sendStreaming] ERROR failed after \(String(format: "%.2f", elapsed))s error=\(error.localizedDescription)")
            throw error
        }
    }

    nonisolated static func makeMessagesPayload(
        systemPrompt: String,
        userContent: String,
        imagePaths: [String] = [],
        audioPaths: [String] = []
    ) throws -> String {
        var messages: [ChatPayloadMessage] = []

        if !systemPrompt.isEmpty {
            messages.append(ChatPayloadMessage(role: "system", content: systemPrompt))
        }

        messages.append(
            ChatPayloadMessage(
                role: "user",
                content: userContent,
                images: imagePaths,
                audio: audioPaths
            )
        )

        let encoder = JSONEncoder()
        // Cactus's current path-array parser expects plain POSIX paths and does
        // not normalize escaped forward slashes such as `\/private\/var\/...`.
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let encoded = try encoder.encode(messages)
        guard let json = String(data: encoded, encoding: .utf8) else {
            throw CactusRuntimeError.invalidResponse
        }

        return json
    }
}
