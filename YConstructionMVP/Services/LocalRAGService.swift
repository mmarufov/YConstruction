import Foundation

struct LocalRAGMatch: Equatable, Sendable {
    let record: CachedProjectChangeRecord
    let document: String
    let score: Float
}

struct LocalRAGQueryResult: Equatable, Sendable {
    let queryText: String
    let matches: [LocalRAGMatch]
    let indexedRecordCount: Int
}

enum LocalRAGError: LocalizedError {
    case embeddingModelNotInstalled
    case noSyncedReports
    case indexUnavailable

    var errorDescription: String? {
        switch self {
        case .embeddingModelNotInstalled:
            return """
            Local question search needs \(LocalModelStore.embeddingModel.displayName). Import the `\(LocalModelStore.embeddingModel.folderName)` folder first.
            """
        case .noSyncedReports:
            return "There are no synced reports on this iPhone yet, so local question search has nothing to compare against."
        case .indexUnavailable:
            return "The local search index is not ready yet."
        }
    }
}

actor LocalRAGService {
    private let modelStore = LocalModelStore.shared
    private let modelSpec = LocalModelStore.embeddingModel

    private var embeddingModel: CactusModelHandle?
    private var loadedModelPath: String?
    private var indexHandle: CactusIndexHandle?
    private var indexedFingerprint: String?
    private var indexedRecordsByVectorID: [Int32: CachedProjectChangeRecord] = [:]
    private var indexedDocumentsByVectorID: [Int32: String] = [:]

    deinit {
        if let indexHandle {
            CactusRuntime.destroyIndex(indexHandle)
        }

        if let embeddingModel {
            CactusRuntime.destroyModel(embeddingModel)
        }
    }

    func statusText(for cachedRecords: [CachedProjectChangeRecord]) async -> String {
        do {
            if try await modelStore.prepareInstalledEmbeddingModel() != nil {
                if cachedRecords.isEmpty {
                    return "\(modelSpec.displayName) is ready, but there are no synced reports cached locally yet."
                }
                return "\(modelSpec.displayName) is ready for local question search over \(cachedRecords.count) synced report(s)."
            }

            return "Import `\(modelSpec.folderName)` to answer staged-photo questions from synced history."
        } catch {
            return error.localizedDescription
        }
    }

    @discardableResult
    func refreshIndex(from records: [CachedProjectChangeRecord]) async throws -> Int {
        let syncedRecords = records
            .filter(\.synced)
            .sorted {
                if $0.id == $1.id {
                    return ($0.updatedAt ?? $0.timestamp) > ($1.updatedAt ?? $1.timestamp)
                }
                return $0.id < $1.id
            }

        guard !syncedRecords.isEmpty else {
            indexedFingerprint = nil
            indexedRecordsByVectorID = [:]
            indexedDocumentsByVectorID = [:]
            destroyIndexIfNeeded()
            return 0
        }

        let fingerprint = Self.makeFingerprint(for: syncedRecords)
        if fingerprint == indexedFingerprint, indexHandle != nil {
            return syncedRecords.count
        }

        let model = try await loadEmbeddingModelIfNeeded()
        let documents = syncedRecords.map(Self.makeDocument)
        let metadatas = syncedRecords.map(Self.makeMetadataJSONString)
        let embeddings = try documents.map { try CactusRuntime.embedText(model: model, text: $0) }

        guard let embeddingDim = embeddings.first?.count, embeddingDim > 0 else {
            throw LocalRAGError.indexUnavailable
        }

        destroyIndexIfNeeded()

        let indexDirectoryURL = try indexDirectoryURL()
        if FileManager.default.fileExists(atPath: indexDirectoryURL.path) {
            try FileManager.default.removeItem(at: indexDirectoryURL)
        }
        try FileManager.default.createDirectory(at: indexDirectoryURL, withIntermediateDirectories: true)

        let indexHandle = try CactusRuntime.initializeIndex(
            at: indexDirectoryURL.path,
            embeddingDim: embeddingDim
        )

        let vectorIDs: [Int32] = Array(1...syncedRecords.count).map(Int32.init)
        try CactusRuntime.addDocumentsToIndex(
            index: indexHandle,
            ids: vectorIDs,
            documents: documents,
            metadatas: metadatas,
            embeddings: embeddings
        )

        self.indexHandle = indexHandle
        self.indexedFingerprint = fingerprint
        self.indexedRecordsByVectorID = Dictionary(uniqueKeysWithValues: zip(vectorIDs, syncedRecords))
        self.indexedDocumentsByVectorID = Dictionary(uniqueKeysWithValues: zip(vectorIDs, documents))

        return syncedRecords.count
    }

    func query(
        question: String,
        topK: Int = 5,
        scoreThreshold: Float = 0.58
    ) async throws -> LocalRAGQueryResult {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalRAGError.indexUnavailable
        }

        guard let indexHandle else {
            if indexedRecordsByVectorID.isEmpty {
                throw LocalRAGError.noSyncedReports
            }
            throw LocalRAGError.indexUnavailable
        }

        let model = try await loadEmbeddingModelIfNeeded()
        let queryEmbedding = try CactusRuntime.embedText(model: model, text: question)
        let rawMatches = try CactusRuntime.queryIndex(
            index: indexHandle,
            embedding: queryEmbedding,
            topK: topK,
            scoreThreshold: scoreThreshold
        )

        let matches = rawMatches.compactMap { rawMatch -> LocalRAGMatch? in
            guard let record = indexedRecordsByVectorID[rawMatch.id],
                  let document = indexedDocumentsByVectorID[rawMatch.id]
            else {
                return nil
            }

            return LocalRAGMatch(
                record: record,
                document: document,
                score: rawMatch.score
            )
        }

        return LocalRAGQueryResult(
            queryText: question,
            matches: matches,
            indexedRecordCount: indexedRecordsByVectorID.count
        )
    }

    private func loadEmbeddingModelIfNeeded() async throws -> CactusModelHandle {
        if let embeddingModel, loadedModelPath != nil {
            return embeddingModel
        }

        guard let installation = try await modelStore.prepareInstalledEmbeddingModel() else {
            throw LocalRAGError.embeddingModelNotInstalled
        }

        let handle = try CactusRuntime.initializeModel(at: installation.directoryURL.path)
        embeddingModel = handle
        loadedModelPath = installation.directoryURL.path
        return handle
    }

    private func destroyIndexIfNeeded() {
        if let indexHandle {
            CactusRuntime.destroyIndex(indexHandle)
        }
        indexHandle = nil
    }

    private func indexDirectoryURL() throws -> URL {
        guard let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ModelStoreError.unresolvedStorageLocation
        }

        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "YConstructionMVP"
        return baseURL
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("LocalRAG", isDirectory: true)
            .appendingPathComponent(modelSpec.folderName, isDirectory: true)
    }

    private static func makeFingerprint(for records: [CachedProjectChangeRecord]) -> String {
        records.map {
            [
                $0.id,
                $0.guid,
                $0.defectType,
                $0.severity,
                $0.storey,
                $0.space ?? "",
                $0.orientation ?? "",
                $0.elementType,
                $0.transcriptOriginal ?? "",
                $0.transcriptEnglish ?? "",
                $0.updatedAt?.ISO8601Format() ?? ""
            ].joined(separator: "|")
        }
        .joined(separator: "\n")
    }

    private static func makeDocument(for record: CachedProjectChangeRecord) -> String {
        [
            "id: \(record.id)",
            "guid: \(record.guid.isEmpty ? "unknown" : record.guid)",
            "defect_type: \(record.defectType)",
            "severity: \(record.severity)",
            "storey: \(record.storey)",
            "space: \(record.space ?? "unknown")",
            "orientation: \(record.orientation ?? "unknown")",
            "element_type: \(record.elementType)",
            "reporter: \(record.reporter)",
            "timestamp: \(record.timestamp.ISO8601Format())",
            "resolved: \(record.resolved ? "yes" : "no")",
            "transcript_original: \(record.transcriptOriginal ?? "")",
            "transcript_english: \(record.transcriptEnglish ?? "")",
            "ai_safety_notes: \(record.aiSafetyNotes ?? "")"
        ]
        .joined(separator: "\n")
    }

    private static func makeMetadataJSONString(for record: CachedProjectChangeRecord) -> String {
        let metadata: [String: String] = [
            "id": record.id,
            "photo_url": record.photoURL ?? "",
            "bcf_path": record.bcfPath ?? "",
            "updated_at": record.updatedAt?.ISO8601Format() ?? ""
        ]

        if let data = try? JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            return json
        }

        return "{}"
    }
}
