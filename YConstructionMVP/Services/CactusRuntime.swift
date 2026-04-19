import Foundation
import cactus

typealias CactusModelHandle = UnsafeMutableRawPointer
typealias CactusIndexHandle = UnsafeMutableRawPointer

struct CactusIndexQueryMatch: Equatable, Sendable {
    let id: Int32
    let score: Float
}

struct CactusCompletionEnvelope: Decodable, Equatable, Sendable {
    let success: Bool
    let error: String?
    let response: String?
    let cloudHandoff: Bool?
    let ramUsageMB: Double?
    let timeToFirstTokenMS: Double?
    let totalTimeMS: Double?
    let decodeTokensPerSecond: Double?

    enum CodingKeys: String, CodingKey {
        case success
        case error
        case response
        case cloudHandoff = "cloud_handoff"
        case ramUsageMB = "ram_usage_mb"
        case timeToFirstTokenMS = "time_to_first_token_ms"
        case totalTimeMS = "total_time_ms"
        case decodeTokensPerSecond = "decode_tps"
    }

    var runtimeStats: AIRuntimeStats {
        AIRuntimeStats(
            ramUsageMB: ramUsageMB,
            timeToFirstTokenMS: timeToFirstTokenMS,
            totalTimeMS: totalTimeMS,
            decodeTokensPerSecond: decodeTokensPerSecond,
            cloudHandoff: cloudHandoff ?? false
        )
    }
}

enum CactusRuntimeError: LocalizedError {
    case initializationFailed(String)
    case completionFailed(String)
    case transcriptionFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .initializationFailed(let message):
            return message
        case .completionFailed(let message):
            return message
        case .transcriptionFailed(let message):
            return message
        case .invalidResponse:
            return "Cactus returned an unreadable response."
        }
    }
}

enum CactusRuntime {
    private static let outputBufferSize = 262_144

    private static let frameworkInitialized: Void = {
        cactus_set_telemetry_environment("swift", nil, nil)

        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            bundleIdentifier.withCString { cactus_set_app_id($0) }
        }
    }()

    static func initializeModel(at modelPath: String) throws -> CactusModelHandle {
        _ = frameworkInitialized

        guard let model = cactus_init(modelPath, nil, false) else {
            throw CactusRuntimeError.initializationFailed(lastError(or: "Failed to initialize Cactus model."))
        }

        return model
    }

    static func destroyModel(_ model: CactusModelHandle) {
        cactus_destroy(model)
    }

    static func resetModel(_ model: CactusModelHandle) {
        cactus_reset(model)
    }

    static func complete(
        model: CactusModelHandle,
        messagesJSON: String,
        optionsJSON: String?,
        toolsJSON: String? = nil,
        pcmData: Data? = nil
    ) throws -> String {
        var outputBuffer = [CChar](repeating: 0, count: outputBufferSize)

        let result = outputBuffer.withUnsafeMutableBufferPointer { buffer in
            if let pcmData, !pcmData.isEmpty {
                return pcmData.withUnsafeBytes { pcmBuffer in
                    cactus_complete(
                        model,
                        messagesJSON,
                        buffer.baseAddress,
                        buffer.count,
                        optionsJSON,
                        toolsJSON,
                        nil,
                        nil,
                        pcmBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        pcmData.count
                    )
                }
            }

            return cactus_complete(
                model,
                messagesJSON,
                buffer.baseAddress,
                buffer.count,
                optionsJSON,
                toolsJSON,
                nil,
                nil,
                nil,
                0
            )
        }

        guard result >= 0 else {
            let responseText = String(cString: outputBuffer)
            if let structuredError = errorMessage(from: responseText) {
                throw CactusRuntimeError.completionFailed(structuredError)
            }
            if !responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw CactusRuntimeError.completionFailed(responseText)
            }
            throw CactusRuntimeError.completionFailed(lastError(or: "Cactus completion failed."))
        }

        return String(cString: outputBuffer)
    }

    static func transcribe(
        model: CactusModelHandle,
        audioPath: String? = nil,
        prompt: String? = nil,
        optionsJSON: String?,
        pcmData: Data? = nil
    ) throws -> String {
        var outputBuffer = [CChar](repeating: 0, count: outputBufferSize)

        let result = outputBuffer.withUnsafeMutableBufferPointer { buffer in
            if let pcmData, !pcmData.isEmpty {
                return pcmData.withUnsafeBytes { pcmBuffer in
                    cactus_transcribe(
                        model,
                        audioPath,
                        prompt,
                        buffer.baseAddress,
                        buffer.count,
                        optionsJSON,
                        nil,
                        nil,
                        pcmBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        pcmData.count
                    )
                }
            }

            return cactus_transcribe(
                model,
                audioPath,
                prompt,
                buffer.baseAddress,
                buffer.count,
                optionsJSON,
                nil,
                nil,
                nil,
                0
            )
        }

        guard result >= 0 else {
            let responseText = String(cString: outputBuffer)
            if let structuredError = errorMessage(from: responseText) {
                throw CactusRuntimeError.transcriptionFailed(structuredError)
            }
            if !responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw CactusRuntimeError.transcriptionFailed(responseText)
            }
            throw CactusRuntimeError.transcriptionFailed(lastError(or: "Cactus transcription failed."))
        }

        return String(cString: outputBuffer)
    }

    static func decodeCompletionEnvelope(from rawJSONString: String) throws -> CactusCompletionEnvelope {
        let data = Data(rawJSONString.utf8)
        return try JSONDecoder().decode(CactusCompletionEnvelope.self, from: data)
    }

    static func embedText(
        model: CactusModelHandle,
        text: String,
        normalize: Bool = true
    ) throws -> [Float] {
        var embeddingBuffer = [Float](repeating: 0, count: 4_096)
        var embeddingDim = 0

        let result = embeddingBuffer.withUnsafeMutableBufferPointer { buffer in
            cactus_embed(model, text, buffer.baseAddress, buffer.count, &embeddingDim, normalize)
        }

        guard result >= 0 else {
            throw CactusRuntimeError.completionFailed(lastError(or: "Cactus embedding failed."))
        }

        return Array(embeddingBuffer.prefix(embeddingDim))
    }

    static func initializeIndex(
        at directoryPath: String,
        embeddingDim: Int
    ) throws -> CactusIndexHandle {
        guard let index = cactus_index_init(directoryPath, embeddingDim) else {
            throw CactusRuntimeError.initializationFailed(lastError(or: "Failed to initialize the local Cactus index."))
        }

        return index
    }

    static func destroyIndex(_ index: CactusIndexHandle) {
        cactus_index_destroy(index)
    }

    static func addDocumentsToIndex(
        index: CactusIndexHandle,
        ids: [Int32],
        documents: [String],
        metadatas: [String]?,
        embeddings: [[Float]]
    ) throws {
        guard !ids.isEmpty, ids.count == documents.count, ids.count == embeddings.count else {
            throw CactusRuntimeError.invalidResponse
        }

        let embeddingDim = embeddings.first?.count ?? 0
        guard embeddingDim > 0 else {
            throw CactusRuntimeError.invalidResponse
        }

        var idArray = ids
        var documentPointers = documents.map { strdup($0) }
        let metadataPointers = metadatas?.map { strdup($0) }
        var embeddingPointers = embeddings.map { embedding -> UnsafePointer<Float>? in
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: embedding.count)
            pointer.initialize(from: embedding, count: embedding.count)
            return UnsafePointer(pointer)
        }

        defer {
            documentPointers.forEach { free($0) }
            metadataPointers?.forEach { free($0) }
            embeddingPointers.forEach { pointer in
                if let pointer {
                    UnsafeMutablePointer(mutating: pointer).deallocate()
                }
            }
        }

        let result = idArray.withUnsafeMutableBufferPointer { idBuffer in
            documentPointers.withUnsafeMutableBufferPointer { documentBuffer in
                embeddingPointers.withUnsafeMutableBufferPointer { embeddingBuffer in
                    if let metadataPointers {
                        var metadataCopy = metadataPointers
                        return metadataCopy.withUnsafeMutableBufferPointer { metadataBuffer in
                            cactus_index_add(
                                index,
                                idBuffer.baseAddress,
                                unsafeBitCast(documentBuffer.baseAddress, to: UnsafeMutablePointer<UnsafePointer<CChar>?>?.self),
                                unsafeBitCast(metadataBuffer.baseAddress, to: UnsafeMutablePointer<UnsafePointer<CChar>?>?.self),
                                embeddingBuffer.baseAddress,
                                ids.count,
                                embeddingDim
                            )
                        }
                    }

                    return cactus_index_add(
                        index,
                        idBuffer.baseAddress,
                        unsafeBitCast(documentBuffer.baseAddress, to: UnsafeMutablePointer<UnsafePointer<CChar>?>?.self),
                        nil,
                        embeddingBuffer.baseAddress,
                        ids.count,
                        embeddingDim
                    )
                }
            }
        }

        guard result >= 0 else {
            throw CactusRuntimeError.completionFailed(lastError(or: "Failed to add documents to the local Cactus index."))
        }
    }

    static func queryIndex(
        index: CactusIndexHandle,
        embedding: [Float],
        topK: Int,
        scoreThreshold: Float
    ) throws -> [CactusIndexQueryMatch] {
        guard !embedding.isEmpty else {
            return []
        }

        let resultCapacity = max(topK, 1)
        var embeddingCopy = embedding
        var idBuffer = [Int32](repeating: 0, count: resultCapacity)
        var scoreBuffer = [Float](repeating: 0, count: resultCapacity)
        var idBufferSize = resultCapacity
        var scoreBufferSize = resultCapacity
        let optionsJSON = #"{"top_k":\#(topK),"score_threshold":\#(scoreThreshold)}"#

        let result = embeddingCopy.withUnsafeMutableBufferPointer { embeddingBuffer in
            idBuffer.withUnsafeMutableBufferPointer { idResultBuffer in
                scoreBuffer.withUnsafeMutableBufferPointer { scoreResultBuffer in
                    var embeddingPointer: UnsafePointer<Float>? = embeddingBuffer.baseAddress.map { UnsafePointer($0) }
                    var idPointer: UnsafeMutablePointer<Int32>? = idResultBuffer.baseAddress
                    var scorePointer: UnsafeMutablePointer<Float>? = scoreResultBuffer.baseAddress

                    return withUnsafeMutablePointer(to: &embeddingPointer) { embeddingPointerPointer in
                        withUnsafeMutablePointer(to: &idPointer) { idPointerPointer in
                            withUnsafeMutablePointer(to: &scorePointer) { scorePointerPointer in
                                withUnsafeMutablePointer(to: &idBufferSize) { idSizePointer in
                                    withUnsafeMutablePointer(to: &scoreBufferSize) { scoreSizePointer in
                                        optionsJSON.withCString { optionsCString in
                                            cactus_index_query(
                                                index,
                                                embeddingPointerPointer,
                                                1,
                                                embedding.count,
                                                optionsCString,
                                                idPointerPointer,
                                                idSizePointer,
                                                scorePointerPointer,
                                                scoreSizePointer
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        guard result >= 0 else {
            throw CactusRuntimeError.completionFailed(lastError(or: "Local Cactus index query failed."))
        }

        return Array(zip(idBuffer.prefix(idBufferSize), scoreBuffer.prefix(scoreBufferSize))).map {
            CactusIndexQueryMatch(id: $0.0, score: $0.1)
        }
    }

    private static func errorMessage(from responseText: String) -> String? {
        guard !responseText.isEmpty,
              let data = responseText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        if let error = json["error"] as? String, !error.isEmpty {
            return error
        }

        return nil
    }

    private static func lastError(or fallback: String) -> String {
        let cactusError = String(cString: cactus_get_last_error())
        return cactusError.isEmpty ? fallback : cactusError
    }
}
