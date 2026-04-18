import Foundation

final class StubAIService: SiteVoiceAI {
    func loadModel() async throws {
        try await Task.sleep(nanoseconds: 400_000_000)
    }

    func transcribe(audio: Data) async throws -> String {
        try await Task.sleep(nanoseconds: 600_000_000)
        return "There is a large crack running vertically on the north wall of Room 204."
    }

    func analyze(transcript: String, photo: Data) async throws -> DefectReport {
        try await Task.sleep(nanoseconds: 1_500_000_000)
        return DefectReport(
            defectType: "crack",
            location: "North wall, Room 204, Floor 2",
            severity: .high,
            visualDescription: "A diagonal structural crack approximately 30 cm long runs across the upper portion of the interior drywall.",
            spokenResponse: "I see a vertical structural crack about a foot long. High severity under IBC 2308.5 — I'm logging it now.",
            transcript: transcript,
            codeReferenceId: "IBC 2308.5",
            confidence: 0.87,
            photoData: photo,
            timestamp: Date()
        )
    }
}
