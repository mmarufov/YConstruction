import Foundation

enum CactusServiceError: Error, LocalizedError {
    case modelWeightsMissing(name: String, expectedPath: String)
    case modelLoadFailed(String)
    case notInitialized

    var errorDescription: String? {
        switch self {
        case .modelWeightsMissing(let name, let path):
            return "Missing weights for \(name). Place them at \(path)."
        case .modelLoadFailed(let msg):
            return "Model load failed: \(msg)"
        case .notInitialized:
            return "Cactus model not initialized"
        }
    }
}

actor CactusService {
    static let shared = CactusService()

    private var gemmaHandle: CactusModelT?
    private var whisperHandle: CactusModelT?

    private init() {}

    // MARK: - Paths

    static func gemmaModelPath() throws -> String {
        try AppConfig.modelsDirectory()
            .appendingPathComponent(AppConfig.gemmaModelDirName, isDirectory: true)
            .path
    }

    static func whisperModelPath() throws -> String {
        try AppConfig.modelsDirectory()
            .appendingPathComponent(AppConfig.whisperModelDirName, isDirectory: true)
            .path
    }

    // MARK: - Availability

    static func gemmaWeightsAvailable() -> Bool {
        guard let path = try? gemmaModelPath() else { return false }
        return directoryExistsAndNotEmpty(path)
    }

    static func whisperWeightsAvailable() -> Bool {
        guard let path = try? whisperModelPath() else { return false }
        return directoryExistsAndNotEmpty(path)
    }

    private static func directoryExistsAndNotEmpty(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        return !contents.isEmpty
    }

    // MARK: - Lifecycle

    func loadGemma() throws -> CactusModelT {
        if let handle = gemmaHandle { return handle }
        let path = try Self.validatedGemmaModelPath()
        do {
            let handle = try cactusInit(path, nil, false)
            self.gemmaHandle = handle
            return handle
        } catch {
            throw CactusServiceError.modelLoadFailed(error.localizedDescription)
        }
    }

    func loadWhisper() throws -> CactusModelT {
        if let handle = whisperHandle { return handle }
        let path = try Self.validatedWhisperModelPath()
        do {
            let handle = try cactusInit(path, nil, false)
            self.whisperHandle = handle
            return handle
        } catch {
            throw CactusServiceError.modelLoadFailed(error.localizedDescription)
        }
    }

    func gemma() -> CactusModelT? { gemmaHandle }
    func whisper() -> CactusModelT? { whisperHandle }

    func shutdown() {
        if let g = gemmaHandle { cactusDestroy(g); gemmaHandle = nil }
        if let w = whisperHandle { cactusDestroy(w); whisperHandle = nil }
    }

    static func validatedGemmaModelPath() throws -> String {
        try validatedModelPath(
            path: gemmaModelPath,
            displayName: "Gemma 4 E2B"
        )
    }

    static func validatedWhisperModelPath() throws -> String {
        try validatedModelPath(
            path: whisperModelPath,
            displayName: "whisper-base"
        )
    }

    private static func validatedModelPath(
        path: () throws -> String,
        displayName: String
    ) throws -> String {
        let resolvedPath = try path()
        guard directoryExistsAndNotEmpty(resolvedPath) else {
            throw CactusServiceError.modelWeightsMissing(
                name: displayName,
                expectedPath: resolvedPath
            )
        }
        return resolvedPath
    }
}
