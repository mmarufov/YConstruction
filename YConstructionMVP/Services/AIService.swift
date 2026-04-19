import Foundation

nonisolated struct AIRuntimeStats: Equatable, Sendable {
    let ramUsageMB: Double?
    let timeToFirstTokenMS: Double?
    let totalTimeMS: Double?
    let decodeTokensPerSecond: Double?
    let cloudHandoff: Bool
}

nonisolated struct AIResponse: Equatable, Sendable {
    let text: String
    let runtimeStats: AIRuntimeStats?
}

nonisolated struct AIModelPrewarmResult: Equatable, Sendable {
    let modelPath: String
}

nonisolated struct AIRequest: Sendable {
    let prompt: String
    let imagePaths: [String]
    let audioPaths: [String]
    let audioPCMData: Data?
    let maxTokens: Int?

    init(
        prompt: String,
        imagePaths: [String] = [],
        audioPaths: [String] = [],
        audioPCMData: Data? = nil,
        maxTokens: Int? = nil
    ) {
        self.prompt = prompt
        self.imagePaths = imagePaths
        self.audioPaths = audioPaths
        self.audioPCMData = audioPCMData
        self.maxTokens = maxTokens
    }
}

nonisolated protocol AIService: Sendable {
    func prewarm() async throws -> AIModelPrewarmResult

    /// Sends a multimodal turn plus any current conversation context.
    func send(request: AIRequest, conversation: [Message]) async throws -> AIResponse

    /// Streaming variant. `onToken` is invoked from the model's generation
    /// thread as tokens are decoded. The final `AIResponse` still contains the
    /// full buffered text.
    func sendStreaming(
        request: AIRequest,
        conversation: [Message],
        onToken: @Sendable @escaping (String) -> Void
    ) async throws -> AIResponse

    func latestRuntimeStats() async -> AIRuntimeStats?
}

extension AIService {
    /// Default no-streaming fallback: delivers the entire response at the end
    /// as a single token. Real streaming implementations should override.
    func sendStreaming(
        request: AIRequest,
        conversation: [Message],
        onToken: @Sendable @escaping (String) -> Void
    ) async throws -> AIResponse {
        let response = try await send(request: request, conversation: conversation)
        onToken(response.text)
        return response
    }
}
