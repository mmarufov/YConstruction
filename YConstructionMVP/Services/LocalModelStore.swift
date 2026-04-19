import Foundation

nonisolated struct LocalModelInstallation: Sendable, Equatable {
    let directoryURL: URL
    let sizeBytes: Int64
}

nonisolated struct ImportedModelInstallation: Sendable, Equatable {
    let spec: ManagedModelSpec
    let installation: LocalModelInstallation
}

nonisolated struct ManagedModelSpec: Sendable, Equatable {
    let modelID: String
    let folderName: String
    let displayName: String
    let downloadCommand: String
    let requiredFilenames: [String]
    let requiredRuntimeAssets: [String]
    let importInstructions: String
}

actor LocalModelStore {
    static let shared = LocalModelStore()

    static let assistantModel = ManagedModelSpec(
        modelID: "google/gemma-3n-E2B-it",
        folderName: "gemma-3n-e2b-it",
        displayName: "Gemma 3n E2B",
        downloadCommand: "cactus download google/gemma-3n-E2B-it",
        requiredFilenames: [
            "config.txt",
            "tokenizer.json",
            "token_embeddings.weights"
        ],
        requiredRuntimeAssets: [],
        importInstructions: """
        Import the `gemma-3n-e2b-it` folder from Files, or copy it into `YConstructionMVP` using Finder:
        iPhone > Files > YConstructionMVP.
        """
    )

    static let embeddingModel = ManagedModelSpec(
        modelID: "Qwen/Qwen3-Embedding-0.6B",
        folderName: "qwen3-embedding-0.6b",
        displayName: "Qwen3 Embedding 0.6B",
        downloadCommand: "cactus download Qwen/Qwen3-Embedding-0.6B",
        requiredFilenames: [
            "config.txt",
            "tokenizer.json",
            "token_embeddings.weights"
        ],
        requiredRuntimeAssets: [],
        importInstructions: """
        Import the `qwen3-embedding-0.6b` folder so the iPhone can answer staged-photo questions from synced history.
        """
    )

    static let supportedModels = [assistantModel, embeddingModel]

    static let modelID = assistantModel.modelID
    static let modelFolderName = assistantModel.folderName
    static let displayName = assistantModel.displayName
    static let downloadCommand = assistantModel.downloadCommand
    static let supportsDirectAudioInput = false
    static let supportsCameraContext = false
    static let importInstructions = assistantModel.importInstructions

    private let fileManager = FileManager.default

    func prepareInstalledModel() throws -> LocalModelInstallation? {
        try prepareInstalledModel(for: Self.assistantModel)
    }

    func prepareInstalledEmbeddingModel() throws -> LocalModelInstallation? {
        try prepareInstalledModel(for: Self.embeddingModel)
    }

    func prepareInstalledModel(for spec: ManagedModelSpec) throws -> LocalModelInstallation? {
        let installedURL = try managedModelDirectoryURL(for: spec)
        let installedInspection = inspectModelDirectory(at: installedURL, spec: spec)

        if installedInspection.isReady {
            return try makeInstallation(for: installedURL)
        }

        if installedInspection.hasBaseModelFiles {
            throw ModelStoreError.incompleteRuntimeAssets(spec: spec, missingFiles: installedInspection.missingRuntimeAssets)
        }

        if let promotedURL = try promoteImportedModelIfNeeded(for: spec) {
            return try makeInstallation(for: promotedURL)
        }

        return nil
    }

    func installedModelURL() throws -> URL? {
        try installedModelURL(for: Self.assistantModel)
    }

    func installedEmbeddingModelURL() throws -> URL? {
        try installedModelURL(for: Self.embeddingModel)
    }

    func installedModelURL(for spec: ManagedModelSpec) throws -> URL? {
        let installedURL = try managedModelDirectoryURL(for: spec)
        let inspection = inspectModelDirectory(at: installedURL, spec: spec)
        if inspection.isReady {
            return installedURL
        }
        if inspection.hasBaseModelFiles {
            throw ModelStoreError.incompleteRuntimeAssets(spec: spec, missingFiles: inspection.missingRuntimeAssets)
        }
        return nil
    }

    func importModel(from sourceURL: URL) throws -> LocalModelInstallation {
        try importModel(from: sourceURL, for: Self.assistantModel)
    }

    func importKnownModel(from sourceURL: URL) throws -> ImportedModelInstallation {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let resolved = try resolveKnownModelSource(from: sourceURL, supportedModels: Self.supportedModels) else {
            throw ModelStoreError.unsupportedModelFolder
        }

        let inspection = inspectModelDirectory(at: resolved.directoryURL, spec: resolved.spec)
        if !inspection.missingBaseFiles.isEmpty {
            throw ModelStoreError.invalidModelFolder(spec: resolved.spec)
        }
        if !inspection.missingRuntimeAssets.isEmpty {
            throw ModelStoreError.incompleteRuntimeAssets(spec: resolved.spec, missingFiles: inspection.missingRuntimeAssets)
        }

        let installedURL = try installModelDirectory(from: resolved.directoryURL, spec: resolved.spec)
        return ImportedModelInstallation(
            spec: resolved.spec,
            installation: try makeInstallation(for: installedURL)
        )
    }

    func importModel(from sourceURL: URL, for spec: ManagedModelSpec) throws -> LocalModelInstallation {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let resolvedSourceURL = try resolveModelSource(from: sourceURL, for: spec) else {
            throw ModelStoreError.invalidModelFolder(spec: spec)
        }

        let inspection = inspectModelDirectory(at: resolvedSourceURL, spec: spec)
        if !inspection.missingBaseFiles.isEmpty {
            throw ModelStoreError.invalidModelFolder(spec: spec)
        }
        if !inspection.missingRuntimeAssets.isEmpty {
            throw ModelStoreError.incompleteRuntimeAssets(spec: spec, missingFiles: inspection.missingRuntimeAssets)
        }

        let installedURL = try installModelDirectory(from: resolvedSourceURL, spec: spec)
        return try makeInstallation(for: installedURL)
    }

    private func promoteImportedModelIfNeeded(for spec: ManagedModelSpec) throws -> URL? {
        for candidateURL in documentImportCandidates(for: spec) {
            let inspection = inspectModelDirectory(at: candidateURL, spec: spec)
            guard inspection.hasBaseModelFiles else { continue }
            guard inspection.missingRuntimeAssets.isEmpty else {
                throw ModelStoreError.incompleteRuntimeAssets(spec: spec, missingFiles: inspection.missingRuntimeAssets)
            }
            return try installModelDirectory(from: candidateURL, spec: spec)
        }

        return nil
    }

    private func installModelDirectory(from sourceURL: URL, spec: ManagedModelSpec) throws -> URL {
        let destinationURL = try managedModelDirectoryURL(for: spec)
        let parentURL = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)

        let stagingURL = parentURL.appendingPathComponent("\(destinationURL.lastPathComponent)-incoming-\(UUID().uuidString)", isDirectory: true)
        if fileManager.fileExists(atPath: stagingURL.path) {
            try fileManager.removeItem(at: stagingURL)
        }

        try fileManager.copyItem(at: sourceURL, to: stagingURL)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.moveItem(at: stagingURL, to: destinationURL)
        try excludeFromBackup(destinationURL)

        return destinationURL
    }

    private func resolveKnownModelSource(
        from sourceURL: URL,
        supportedModels: [ManagedModelSpec]
    ) throws -> (spec: ManagedModelSpec, directoryURL: URL)? {
        for spec in supportedModels {
            if let directoryURL = try resolveModelSource(from: sourceURL, for: spec) {
                return (spec, directoryURL)
            }
        }

        return nil
    }

    private func resolveModelSource(from sourceURL: URL, for spec: ManagedModelSpec) throws -> URL? {
        let orderedCandidates = try candidateModelDirectories(from: sourceURL, spec: spec)
        for candidateURL in orderedCandidates {
            if inspectModelDirectory(at: candidateURL, spec: spec).hasBaseModelFiles {
                return candidateURL
            }
        }
        return nil
    }

    private func candidateModelDirectories(from sourceURL: URL, spec: ManagedModelSpec) throws -> [URL] {
        var candidates: [URL] = []

        if sourceURL.lastPathComponent == spec.folderName {
            candidates.append(sourceURL)
        }

        let directChildURL = sourceURL.appendingPathComponent(spec.folderName, isDirectory: true)
        if directChildURL != sourceURL {
            candidates.append(directChildURL)
        }

        let children = try? fileManager.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        if let children {
            for childURL in children where childURL.lastPathComponent == spec.folderName {
                candidates.append(childURL)
            }
        }

        return candidates.reduce(into: []) { unique, candidate in
            if !unique.contains(candidate) {
                unique.append(candidate)
            }
        }
    }

    private func inspectModelDirectory(at directoryURL: URL, spec: ManagedModelSpec) -> ModelDirectoryInspection {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return ModelDirectoryInspection(
                hasBaseModelFiles: false,
                missingBaseFiles: spec.requiredFilenames,
                missingRuntimeAssets: spec.requiredRuntimeAssets
            )
        }

        let missingBaseFiles = missingFiles(in: directoryURL, filenames: spec.requiredFilenames)
        let missingRuntimeAssets = missingFiles(in: directoryURL, filenames: spec.requiredRuntimeAssets)
        return ModelDirectoryInspection(
            hasBaseModelFiles: missingBaseFiles.isEmpty,
            missingBaseFiles: missingBaseFiles,
            missingRuntimeAssets: missingRuntimeAssets
        )
    }

    private func missingFiles(in directoryURL: URL, filenames: [String]) -> [String] {
        filenames.filter { filename in
            let fileURL = directoryURL.appendingPathComponent(filename)
            return !fileManager.fileExists(atPath: fileURL.path)
        }
    }

    private func makeInstallation(for directoryURL: URL) throws -> LocalModelInstallation {
        LocalModelInstallation(
            directoryURL: directoryURL,
            sizeBytes: try directorySizeBytes(at: directoryURL)
        )
    }

    private func managedModelDirectoryURL(for spec: ManagedModelSpec) throws -> URL {
        try applicationSupportDirectoryURL()
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(spec.folderName, isDirectory: true)
    }

    private func applicationSupportDirectoryURL() throws -> URL {
        guard let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ModelStoreError.unresolvedStorageLocation
        }

        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "YConstructionMVP"
        return baseURL.appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    private func documentImportCandidates(for spec: ManagedModelSpec) -> [URL] {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }

        return [
            documentsURL.appendingPathComponent(spec.folderName, isDirectory: true),
            documentsURL.appendingPathComponent("Models", isDirectory: true)
                .appendingPathComponent(spec.folderName, isDirectory: true),
            documentsURL.appendingPathComponent("Inbox", isDirectory: true)
                .appendingPathComponent(spec.folderName, isDirectory: true)
        ]
    }

    private func directorySizeBytes(at directoryURL: URL) throws -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var totalBytes: Int64 = 0

        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard resourceValues.isRegularFile == true else { continue }
            totalBytes += Int64(resourceValues.fileSize ?? 0)
        }

        return totalBytes
    }

    private func excludeFromBackup(_ directoryURL: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true

        var mutableURL = directoryURL
        try mutableURL.setResourceValues(values)
    }
}

nonisolated private struct ModelDirectoryInspection {
    let hasBaseModelFiles: Bool
    let missingBaseFiles: [String]
    let missingRuntimeAssets: [String]

    var isReady: Bool {
        hasBaseModelFiles && missingRuntimeAssets.isEmpty
    }
}

nonisolated enum ModelStoreError: LocalizedError {
    case invalidModelFolder(spec: ManagedModelSpec)
    case unsupportedModelFolder
    case incompleteRuntimeAssets(spec: ManagedModelSpec, missingFiles: [String])
    case unresolvedStorageLocation

    var errorDescription: String? {
        switch self {
        case .invalidModelFolder(let spec):
            return """
            The selected folder does not look like \(spec.displayName). Pick the `\(spec.folderName)` folder that contains `config.txt`, `tokenizer.json`, and `token_embeddings.weights`.
            """
        case .unsupportedModelFolder:
            let folderList = LocalModelStore.supportedModels.map(\.folderName).joined(separator: "`, `")
            return """
            The selected folder does not match a supported local model. Pick one of:
            `\(folderList)`
            """
        case .incompleteRuntimeAssets(let spec, let missingFiles):
            let missing = missingFiles.joined(separator: ", ")
            return """
            The model folder for \(spec.displayName) is missing runtime assets: \(missing).

            Redownload with:
            `\(spec.downloadCommand)`

            Then copy the extracted `\(spec.folderName)` folder onto the phone again.
            """
        case .unresolvedStorageLocation:
            return "The app could not resolve a local storage location for the model."
        }
    }
}
