import Foundation

struct DefectReport: Codable {
    let defectType: String
    let location: String
    let severity: Severity
    let visualDescription: String
    let spokenResponse: String
    let transcript: String
    let codeReferenceId: String?
    let confidence: Double
    let photoData: Data
    let timestamp: Date

    enum Severity: String, Codable {
        case low, medium, high
    }
}

enum SiteVoiceAIError: Error {
    case modelNotLoaded
    case malformedResponse(String)
    case transcriptionFailed(String)
    case inferenceFailed(String)
}

protocol SiteVoiceAI {
    func loadModel() async throws
    func transcribe(audio: Data) async throws -> String
    func analyze(transcript: String, photo: Data) async throws -> DefectReport
}
