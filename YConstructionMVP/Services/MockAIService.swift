import Foundation

nonisolated struct MockAIService: AIService {
    func prewarm() async throws -> AIModelPrewarmResult {
        AIModelPrewarmResult(modelPath: "/mock/gemma-3n-e2b-it")
    }

    func send(request: AIRequest, conversation: [Message]) async throws -> AIResponse {
        try await Task.sleep(for: .seconds(1))

        return AIResponse(
            text: """
            Mock response: later this will come from local Cactus + Gemma 3n text completion.

            Prompt: \(request.prompt)
            Images: \(request.imagePaths.count)
            Audio clips: \(request.audioPaths.count)
            Raw PCM bytes: \(request.audioPCMData?.count ?? 0)
            """,
            runtimeStats: AIRuntimeStats(
                ramUsageMB: 256,
                timeToFirstTokenMS: 120,
                totalTimeMS: 900,
                decodeTokensPerSecond: 36,
                cloudHandoff: false
            )
        )
    }

    func latestRuntimeStats() async -> AIRuntimeStats? {
        AIRuntimeStats(
            ramUsageMB: 256,
            timeToFirstTokenMS: 120,
            totalTimeMS: 900,
            decodeTokensPerSecond: 36,
            cloudHandoff: false
        )
    }
}
