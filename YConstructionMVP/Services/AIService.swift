import Foundation

struct AIRuntimeStats: Equatable, Sendable {
    let ramUsageMB: Double?
    let timeToFirstTokenMS: Double?
    let totalTimeMS: Double?
    let decodeTokensPerSecond: Double?
    let cloudHandoff: Bool
}

struct AIResponse: Equatable, Sendable {
    let text: String
    let runtimeStats: AIRuntimeStats?
}

struct AIModelPrewarmResult: Equatable, Sendable {
    let modelPath: String
}

struct AIRequest: Sendable {
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

protocol AIService: Sendable {
    func prewarm() async throws -> AIModelPrewarmResult

    /// Sends a multimodal turn plus any current conversation context.
    func send(request: AIRequest, conversation: [Message]) async throws -> AIResponse

    func latestRuntimeStats() async -> AIRuntimeStats?
}
