import Foundation

enum ArtifactStore {
    private static let root: URL = {
        let docs = try! FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return docs.appendingPathComponent("Artifacts", isDirectory: true)
    }()

    private static let photosDir: URL = root.appendingPathComponent("Photos", isDirectory: true)
    private static let issuesDir: URL = root.appendingPathComponent("Issues", isDirectory: true)

    private static func ensureDirectories() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: photosDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: issuesDir, withIntermediateDirectories: true)
    }

    static func persistPhotoCopy(from sourceURL: URL) throws -> URL {
        try ensureDirectories()
        let ext = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension
        let destinationURL = photosDir
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }
        try fm.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    static func bcfOutputURL(for topicID: String) throws -> URL {
        try ensureDirectories()
        return issuesDir
            .appendingPathComponent(topicID)
            .appendingPathExtension("bcfzip")
    }
}
