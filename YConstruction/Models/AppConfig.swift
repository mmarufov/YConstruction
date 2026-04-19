import Foundation

nonisolated enum AppConfig {
    static let demoProjectId = "duplex-demo-001"

    static let elementIndexProjectId = "duplex-demo-001"

    static let whisperModelDirName = "whisper-base"
    static let gemmaModelDirName = "gemma-4-e2b-it"

    static var reporterId: String {
        get {
            UserDefaults.standard.string(forKey: "yconstruction.reporterId") ?? "Worker 1"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "yconstruction.reporterId")
        }
    }

    static func toggleDebugReporter() {
        reporterId = (reporterId == "Worker 1") ? "Worker 2" : "Worker 1"
    }

    static func modelsDirectory() throws -> URL {
        let docs = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = docs.appendingPathComponent("models", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func projectDirectory(projectId: String = elementIndexProjectId) throws -> URL {
        let docs = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = docs
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(projectId, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func photosDirectory(projectId: String = elementIndexProjectId) throws -> URL {
        let dir = try projectDirectory(projectId: projectId).appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
