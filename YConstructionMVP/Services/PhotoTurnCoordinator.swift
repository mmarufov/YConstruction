import Foundation

nonisolated private func ycLog(_ message: String) {
    print("[YC][PhotoTurn] \(message)")
}

nonisolated enum PhotoTurnIntent: String, Codable, Equatable, Sendable {
    case report
    case query
    case unclear
}

/// Closed-set IFC vocabulary for prompt constraint. Populated from element_index.json.
nonisolated struct IFCVocabulary: Sendable, Equatable {
    let storeys: [String]
    let spaces: [String]
    let elementTypes: [String]
    let orientations: [String]

    static let empty = IFCVocabulary(storeys: [], spaces: [], elementTypes: [], orientations: [])

    var isEmpty: Bool {
        storeys.isEmpty && spaces.isEmpty && elementTypes.isEmpty && orientations.isEmpty
    }

    func promptConstraintBlock() -> String {
        guard !isEmpty else { return "" }
        var lines: [String] = [
            "IMPORTANT — closed-set vocabulary. Match the user's words to these exact strings:"
        ]
        if !storeys.isEmpty {
            lines.append("  \"storey\" MUST be exactly one of: \(quoted(storeys)), or null.")
            lines.append("    (\"first floor\" → \"Level 1\"; \"second floor\" → \"Level 2\"; \"roof\" → \"Roof\"; \"foundation\"/\"basement\" → \"T/FDN\".)")
        }
        if !spaces.isEmpty {
            let preview = spaces.count > 12 ? Array(spaces.prefix(12)) + ["…"] : spaces
            lines.append("  \"space\" MUST be exactly one of: \(quoted(preview)), or null.")
            lines.append("    (Normalize \"room 204\" → \"A204\"; \"204\" → \"A204\" when on Level 2.)")
        }
        if !elementTypes.isEmpty {
            lines.append("  \"element_type\" MUST be exactly one of: \(quoted(elementTypes)), or null.")
        }
        if !orientations.isEmpty {
            lines.append("  \"orientation\" MUST be exactly one of: \(quoted(orientations)), or null.")
        }
        lines.append("  If the worker's wording doesn't map cleanly to any listed value, use null rather than inventing one.")
        return lines.joined(separator: "\n")
    }

    private func quoted(_ values: [String]) -> String {
        values.map { "\"\($0)\"" }.joined(separator: ", ")
    }
}

nonisolated struct PhotoReportFields: Codable, Equatable, Sendable {
    var defectType: String?
    var severity: String?
    var storey: String?
    var space: String?
    var orientation: String?
    var elementType: String?
    var guid: String?
    var aiSafetyNotes: String?

    enum CodingKeys: String, CodingKey {
        case defectType = "defect_type"
        case severity
        case storey
        case space
        case orientation
        case elementType = "element_type"
        case guid
        case aiSafetyNotes = "ai_safety_notes"
    }

    func merged(with newer: PhotoReportFields) -> PhotoReportFields {
        PhotoReportFields(
            defectType: Self.preferred(newer.defectType, defectType),
            severity: Self.preferred(newer.severity, severity),
            storey: Self.preferred(newer.storey, storey),
            space: Self.preferred(newer.space, space),
            orientation: Self.preferred(newer.orientation, orientation),
            elementType: Self.preferred(newer.elementType, elementType),
            guid: Self.preferred(newer.guid, guid),
            aiSafetyNotes: Self.preferred(newer.aiSafetyNotes, aiSafetyNotes)
        )
    }

    func clearing(_ fieldNames: [String]) -> PhotoReportFields {
        var copy = self
        for fieldName in fieldNames.map(Self.normalizedFieldName) {
            switch fieldName {
            case "defect_type":
                copy.defectType = nil
            case "severity":
                copy.severity = nil
            case "storey":
                copy.storey = nil
            case "space":
                copy.space = nil
            case "orientation":
                copy.orientation = nil
            case "element_type":
                copy.elementType = nil
            case "guid":
                copy.guid = nil
            case "ai_safety_notes":
                copy.aiSafetyNotes = nil
            default:
                break
            }
        }
        return copy
    }

    func compactSummaryLines() -> [String] {
        [
            "defect_type: \(Self.displayValue(defectType))",
            "severity: \(Self.displayValue(severity))",
            "storey: \(Self.displayValue(storey))",
            "space: \(Self.displayValue(space))",
            "orientation: \(Self.displayValue(orientation))",
            "element_type: \(Self.displayValue(elementType))",
            "guid: \(Self.displayValue(guid))",
            "ai_safety_notes: \(Self.displayValue(aiSafetyNotes))"
        ]
    }

    func asSyncMetadata() -> DefectCapturedMetadata {
        DefectCapturedMetadata(
            guid: Self.normalizedText(guid),
            storey: Self.normalizedText(storey),
            space: Self.normalizedText(space),
            elementType: Self.normalizedText(elementType),
            orientation: Self.normalizedOrientation(orientation),
            defectType: Self.normalizedText(defectType),
            severity: Self.normalizedSeverity(severity),
            aiSafetyNotes: Self.normalizedText(aiSafetyNotes)
        )
    }

    static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if ["unknown", "n/a", "none", "null", "blank"].contains(lower) {
            return nil
        }
        // Reject Gemma echoes of the JSON schema placeholders themselves.
        if Self.looksLikeSchemaEcho(lower) {
            return nil
        }
        return trimmed
    }

    private static func looksLikeSchemaEcho(_ lower: String) -> Bool {
        let echoes: [String] = [
            "string or null",
            "string|null",
            "string | null",
            "low|medium|high|critical or null",
            "low|medium|high|critical",
            "low | medium | high | critical",
            "<string>",
            "<defect type>",
            "<severity>",
            "<storey>",
            "<space>",
            "<orientation>",
            "<element type>",
            "<guid>",
            "<value>",
            "field_name",
            "field name",
            "or null"
        ]
        if echoes.contains(lower) { return true }
        if lower.hasPrefix("<") && lower.hasSuffix(">") { return true }
        return false
    }

    static func normalizedSeverity(_ value: String?) -> String? {
        guard let normalized = normalizedText(value)?.lowercased() else { return nil }
        switch normalized {
        case "low", "medium", "high", "critical":
            return normalized
        default:
            return nil
        }
    }

    static func normalizedOrientation(_ value: String?) -> String? {
        normalizedText(value)?.lowercased()
    }

    private static func preferred(_ candidate: String?, _ existing: String?) -> String? {
        normalizedText(candidate) ?? normalizedText(existing)
    }

    private static func displayValue(_ value: String?) -> String {
        normalizedText(value) ?? "blank"
    }

    private static func normalizedFieldName(_ fieldName: String) -> String {
        fieldName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}

nonisolated struct PhotoReportState: Equatable, Sendable {
    let createdAt: Date
    var transcriptSnippets: [String]
    var fields: PhotoReportFields
    var explicitlyUnknownFields: Set<String>
    var lastBlockingFields: [String]
    var repeatedFollowUpCount: Int

    var combinedTranscript: String {
        transcriptSnippets
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

nonisolated struct PhotoQueryState: Equatable, Sendable {
    let createdAt: Date
    var transcriptSnippets: [String]
    var questionSummary: String?
    var storey: String?
    var space: String?
    var orientation: String?
    var elementType: String?
    var timeframeHint: String?
    var ambiguityNote: String?

    var combinedTranscript: String {
        transcriptSnippets
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    func compactSummaryLines() -> [String] {
        [
            "question_summary: \(display(questionSummary))",
            "storey: \(display(storey))",
            "space: \(display(space))",
            "orientation: \(display(orientation))",
            "element_type: \(display(elementType))",
            "timeframe_hint: \(display(timeframeHint))",
            "ambiguity_note: \(display(ambiguityNote))"
        ]
    }

    private func display(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false ? trimmed : nil) ?? "blank"
    }
}

nonisolated struct PhotoIntentDecision: Sendable {
    let intent: PhotoTurnIntent
    let assistantMessage: String
}

nonisolated struct PhotoReportTurnOutcome: Sendable {
    let state: PhotoReportState
    let readyToUpload: Bool
    let assistantMessage: String
    let runtimeStats: AIRuntimeStats?
}

nonisolated struct PhotoQueryTurnOutcome: Sendable {
    let state: PhotoQueryState
    let readyToSearch: Bool
    let assistantMessage: String
    let runtimeStats: AIRuntimeStats?
}

nonisolated struct PhotoQueryAnswerOutcome: Sendable {
    let assistantMessage: String
    let summaryText: String
    let runtimeStats: AIRuntimeStats?
}

actor PhotoTurnCoordinator {
    nonisolated private struct ReportDecision: Codable {
        let readyToUpload: Bool
        let assistantMessage: String?
        let blockingMissingFields: [String]
        let explicitlyUnknownFields: [String]
        let fields: PhotoReportFields

        enum CodingKeys: String, CodingKey {
            case readyToUpload = "ready_to_upload"
            case assistantMessage = "assistant_message"
            case blockingMissingFields = "blocking_missing_fields"
            case explicitlyUnknownFields = "explicitly_unknown_fields"
            case fields
        }
    }

    nonisolated private struct QueryDecision: Codable {
        nonisolated struct StatePayload: Codable {
            let questionSummary: String?
            let storey: String?
            let space: String?
            let orientation: String?
            let elementType: String?
            let timeframeHint: String?
            let ambiguityNote: String?

            enum CodingKeys: String, CodingKey {
                case questionSummary = "question_summary"
                case storey
                case space
                case orientation
                case elementType = "element_type"
                case timeframeHint = "timeframe_hint"
                case ambiguityNote = "ambiguity_note"
            }
        }

        let readyToSearch: Bool
        let assistantMessage: String?
        let blockingMissingFields: [String]
        let state: StatePayload

        enum CodingKeys: String, CodingKey {
            case readyToSearch = "ready_to_search"
            case assistantMessage = "assistant_message"
            case blockingMissingFields = "blocking_missing_fields"
            case state
        }
    }

    private let aiService: any AIService
    private let ragService: LocalRAGService
    private let vocabulary: IFCVocabulary

    init(
        aiService: any AIService,
        ragService: LocalRAGService,
        vocabulary: IFCVocabulary = .empty
    ) {
        self.aiService = aiService
        self.ragService = ragService
        self.vocabulary = vocabulary
    }

    /// Cosine-similarity threshold above which a turn is routed to RAG.
    /// The Qwen3 embedding model normalises to ~0..1, and in practice matches
    /// on shared construction nouns land around 0.55–0.70 for real overlap.
    private static let ragRoutingScoreThreshold: Float = 0.55

    /// Decide whether the new utterance should go to RAG (query path) or to the
    /// report path. Three layers, cheapest first:
    ///
    ///  0. Explicit trigger words — "report this", "log this", "new defect",
    ///     "upload this" → REPORT. "new question", "tell me about", "why is",
    ///     "what is", "how is", "ask about", "history of" → QUERY.
    ///     These are opt-in speech triggers the worker says on purpose, not
    ///     fuzzy heuristics guessing intent. Instant, no model call.
    ///  1. Cosine gate against synced history (only when no trigger matched).
    ///     - Below threshold → REPORT.
    ///  2. Cosine above threshold but no explicit trigger → fire a tiny Gemma
    ///     tiebreaker. If Gemma is unsure, the assistant asks the worker.
    func classifyIntent(
        transcriptHistory: [String],
        cachedRecords: [CachedProjectChangeRecord],
        stagedPhotoPath: String? = nil
    ) async -> PhotoIntentDecision {
        _ = stagedPhotoPath
        let combinedTranscript = joinHistory(transcriptHistory)
        ycLog("[classifyIntent] transcript=\"\(combinedTranscript)\" cachedRecords=\(cachedRecords.count)")

        // Layer 0: explicit trigger words always win, whether or not we have history.
        if let triggered = Self.triggerIntent(from: combinedTranscript) {
            ycLog("[classifyIntent] trigger keyword → \(triggered.rawValue)")
            return PhotoIntentDecision(
                intent: triggered,
                assistantMessage: Self.intentClarificationMessage(for: triggered)
            )
        }

        // Layer 1: no data to compare against → must be a report.
        if cachedRecords.isEmpty {
            ycLog("[classifyIntent] no synced history — routing to REPORT (nothing to query)")
            return PhotoIntentDecision(
                intent: .report,
                assistantMessage: Self.intentClarificationMessage(for: .report)
            )
        }

        // Layer 1b: cosine gate — does the utterance even resemble anything we've logged?
        let topScore: Float
        do {
            let top = try await ragService.scoreUtterance(combinedTranscript, against: cachedRecords)
            topScore = top?.score ?? 0
        } catch {
            ycLog("[classifyIntent] ERROR cosine scoring failed (\(error.localizedDescription)) — defaulting to REPORT")
            return PhotoIntentDecision(
                intent: .report,
                assistantMessage: Self.intentClarificationMessage(for: .report)
            )
        }
        ycLog("[classifyIntent] cosine topScore=\(String(format: "%.3f", topScore)) threshold=\(Self.ragRoutingScoreThreshold)")

        if topScore < Self.ragRoutingScoreThreshold {
            ycLog("[classifyIntent] cosine below threshold — routing to REPORT (no semantic match)")
            return PhotoIntentDecision(
                intent: .report,
                assistantMessage: Self.intentClarificationMessage(for: .report)
            )
        }

        // Layer 2: topic matches but no explicit trigger — ask Gemma.
        let prompt = """
        A construction worker just took a photo of a site and said:
        "\(combinedTranscript)"

        Is this worker REPORTING a new defect to log, or QUERYING an existing issue from prior reports?
        Reply with exactly one lowercase word: report or query.
        """
        let started = Date()
        do {
            let response = try await aiService.send(
                request: AIRequest(prompt: prompt, maxTokens: 4),
                conversation: []
            )
            let elapsed = Date().timeIntervalSince(started)
            let replyWord = response.text
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .first(where: { !$0.isEmpty }) ?? ""
            ycLog("[classifyIntent] Gemma tiebreaker in \(String(format: "%.2f", elapsed))s → \"\(replyWord)\"")

            switch replyWord {
            case "query":
                return PhotoIntentDecision(
                    intent: .query,
                    assistantMessage: Self.intentClarificationMessage(for: .query)
                )
            case "report":
                return PhotoIntentDecision(
                    intent: .report,
                    assistantMessage: Self.intentClarificationMessage(for: .report)
                )
            default:
                ycLog("[classifyIntent] Gemma tiebreaker unclear → asking user")
                return PhotoIntentDecision(
                    intent: .unclear,
                    assistantMessage: Self.intentClarificationMessage(for: .unclear)
                )
            }
        } catch {
            let elapsed = Date().timeIntervalSince(started)
            ycLog("[classifyIntent] ERROR Gemma tiebreaker failed after \(String(format: "%.2f", elapsed))s error=\(error.localizedDescription) — defaulting to REPORT")
            return PhotoIntentDecision(
                intent: .report,
                assistantMessage: Self.intentClarificationMessage(for: .report)
            )
        }
    }

    /// Opt-in trigger keywords. Returns nil when the utterance doesn't contain
    /// an explicit cue so callers fall through to cosine/Gemma routing.
    private static func triggerIntent(from text: String) -> PhotoTurnIntent? {
        let lower = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !lower.isEmpty else { return nil }

        let reportTriggers: [String] = [
            "report this", "report it", "report that", "report the",
            "log this", "log it", "log that",
            "save this", "save it", "save that", "save to",
            "upload this", "upload it", "upload that", "upload to",
            "record this", "record it", "record that",
            "document this", "document it", "document that",
            "note this", "note that", "write this down",
            "i want to report", "i need to report",
            "i would like to report", "i'd like to report", "id like to report",
            "i want to log", "i need to log",
            "i want to upload", "i'd like to upload", "id like to upload",
            "new report", "new defect", "new issue", "new finding",
            "found a", "i found", "discovered a", "i discovered",
            "there is a new", "there's a new"
        ]
        if reportTriggers.contains(where: { lower.contains($0) }) {
            return .report
        }

        let queryTriggers: [String] = [
            "new question", "i have a question", "i've got a question",
            "ive got a question", "i have questions",
            "question about", "i want to ask", "i'd like to ask",
            "id like to ask", "let me ask", "can i ask",
            "ask about", "ask a question",
            "tell me about", "tell me more", "tell me what",
            "what is", "what was", "what happened", "what's this",
            "what is this", "whats this", "what about",
            "why is", "why was", "why did", "why does",
            "how is", "how was", "how did", "how does",
            "when was", "when did", "when is",
            "who is", "who was", "who did", "who reported", "who logged",
            "where is", "where was",
            "do you know", "does anybody know", "does anyone know",
            "any info", "any information", "more info", "any details",
            "more details", "any history", "the history",
            "already reported", "already logged", "already there"
        ]
        if queryTriggers.contains(where: { lower.contains($0) }) {
            return .query
        }

        return nil
    }

    func processReportTurn(
        existingState: PhotoReportState?,
        newTranscript: String,
        createdAt: Date,
        stagedPhotoPath: String? = nil
    ) async throws -> PhotoReportTurnOutcome {
        var state = existingState ?? PhotoReportState(
            createdAt: createdAt,
            transcriptSnippets: [],
            fields: PhotoReportFields(),
            explicitlyUnknownFields: [],
            lastBlockingFields: [],
            repeatedFollowUpCount: 0
        )
        state.transcriptSnippets.append(newTranscript)
        applyReportHeuristics(to: &state, newTranscript: newTranscript)

        // Shortcut: if the heuristics already filled every required field with a
        // real (non-echo, non-unknown) value, there's nothing for Gemma to add.
        // Skip the 10–30s model call and upload immediately.
        if blockingReportFields(for: state).isEmpty {
            ycLog("[processReportTurn] heuristic-confident: all required fields filled — skipping Gemma")
            state.lastBlockingFields = []
            state.repeatedFollowUpCount = 0
            return PhotoReportTurnOutcome(
                state: state,
                readyToUpload: true,
                assistantMessage: "Got it — uploading.",
                runtimeStats: nil
            )
        }

        var runtimeStats: AIRuntimeStats?
        var assistantMessageOverride: String?
        let prompt = makeReportPrompt(from: state)
        let imagesEnabled = LocalModelStore.supportsCameraContext
        let images = (imagesEnabled ? stagedPhotoPath.map { [$0] } : nil) ?? []
        let started = Date()
        ycLog("[processReportTurn] sending Gemma call images=\(images.count) maxTokens=160 transcript=\"\(state.combinedTranscript)\"")

        do {
            let response = try await aiService.send(
                request: AIRequest(prompt: prompt, imagePaths: images, maxTokens: 160),
                conversation: []
            )
            let elapsed = Date().timeIntervalSince(started)
            ycLog("[processReportTurn] Gemma replied in \(String(format: "%.2f", elapsed))s textLen=\(response.text.count) preview=\"\(response.text.prefix(200))\"")
            runtimeStats = response.runtimeStats
            if let decision = try? decodeReportDecision(from: response.text) {
                ycLog("[processReportTurn] decoded JSON: ready=\(decision.readyToUpload) blocking=\(decision.blockingMissingFields.joined(separator: ","))")
                state.fields = state.fields.merged(with: decision.fields)
                state.explicitlyUnknownFields.formUnion(
                    decision.explicitlyUnknownFields.map(Self.normalizedFieldName)
                )
                state.explicitlyUnknownFields.subtract(resolvedFieldNames(from: state.fields))
                let trimmedAssistantMessage = (decision.assistantMessage ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedAssistantMessage.isEmpty {
                    assistantMessageOverride = trimmedAssistantMessage
                }
            } else {
                ycLog("[processReportTurn] ERROR Gemma response was not valid JSON; falling back to heuristic")
            }
        } catch {
            let elapsed = Date().timeIntervalSince(started)
            ycLog("[processReportTurn] ERROR Gemma failed after \(String(format: "%.2f", elapsed))s error=\(error.localizedDescription)")
        }

        let blockingFields = blockingReportFields(for: state)
        let normalizedBlockingFields = blockingFields.sorted()
        if normalizedBlockingFields.isEmpty {
            state.lastBlockingFields = []
            state.repeatedFollowUpCount = 0
        } else if normalizedBlockingFields == state.lastBlockingFields {
            state.repeatedFollowUpCount += 1
        } else {
            state.lastBlockingFields = normalizedBlockingFields
            state.repeatedFollowUpCount = 0
        }

        let finalBlockingFields = blockingReportFields(for: state)
        let readyToUpload = finalBlockingFields.isEmpty
        let assistantMessage: String
        if readyToUpload {
            assistantMessage = "I have enough to upload this report."
        } else if let override = assistantMessageOverride {
            assistantMessage = override
        } else {
            assistantMessage = reportFollowUpMessage(for: finalBlockingFields, state: state)
        }

        return PhotoReportTurnOutcome(
            state: state,
            readyToUpload: readyToUpload,
            assistantMessage: assistantMessage,
            runtimeStats: runtimeStats
        )
    }

    func processQueryTurn(
        existingState: PhotoQueryState?,
        newTranscript: String,
        createdAt: Date,
        stagedPhotoPath: String? = nil
    ) async throws -> PhotoQueryTurnOutcome {
        var state = existingState ?? PhotoQueryState(
            createdAt: createdAt,
            transcriptSnippets: [],
            questionSummary: nil,
            storey: nil,
            space: nil,
            orientation: nil,
            elementType: nil,
            timeframeHint: nil,
            ambiguityNote: nil
        )
        state.transcriptSnippets.append(newTranscript)
        applyQueryHeuristics(to: &state)

        var runtimeStats: AIRuntimeStats?
        var assistantMessageOverride: String?
        let prompt = makeQueryPrompt(from: state)
        let imagesEnabled = LocalModelStore.supportsCameraContext
        let images = (imagesEnabled ? stagedPhotoPath.map { [$0] } : nil) ?? []
        let started = Date()
        ycLog("[processQueryTurn] sending Gemma call images=\(images.count) maxTokens=160 transcript=\"\(state.combinedTranscript)\"")

        do {
            let response = try await aiService.send(
                request: AIRequest(prompt: prompt, imagePaths: images, maxTokens: 160),
                conversation: []
            )
            let elapsed = Date().timeIntervalSince(started)
            ycLog("[processQueryTurn] Gemma replied in \(String(format: "%.2f", elapsed))s textLen=\(response.text.count) preview=\"\(response.text.prefix(200))\"")
            runtimeStats = response.runtimeStats
            if let decision = try? decodeQueryDecision(from: response.text) {
                ycLog("[processQueryTurn] decoded JSON: ready=\(decision.readyToSearch) summary=\"\(decision.state.questionSummary ?? "nil")\"")
                state.questionSummary = preferred(decision.state.questionSummary, state.questionSummary)
                state.storey = preferred(decision.state.storey, state.storey)
                state.space = preferred(decision.state.space, state.space)
                state.orientation = preferred(decision.state.orientation, state.orientation)
                state.elementType = preferred(decision.state.elementType, state.elementType)
                state.timeframeHint = preferred(decision.state.timeframeHint, state.timeframeHint)
                state.ambiguityNote = preferred(decision.state.ambiguityNote, state.ambiguityNote)
                let trimmedAssistantMessage = (decision.assistantMessage ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedAssistantMessage.isEmpty {
                    assistantMessageOverride = trimmedAssistantMessage
                }
            } else {
                ycLog("[processQueryTurn] ERROR Gemma response was not valid JSON; falling back to heuristic")
            }
        } catch {
            let elapsed = Date().timeIntervalSince(started)
            ycLog("[processQueryTurn] ERROR Gemma failed after \(String(format: "%.2f", elapsed))s error=\(error.localizedDescription)")
        }

        let blockingFields = blockingQueryFields(for: state)
        let readyToSearch = blockingFields.isEmpty
        let assistantMessage: String
        if readyToSearch {
            assistantMessage = "Searching the synced report history locally."
        } else if let override = assistantMessageOverride {
            assistantMessage = override
        } else {
            assistantMessage = queryFollowUpMessage(for: blockingFields, state: state)
        }

        return PhotoQueryTurnOutcome(
            state: state,
            readyToSearch: readyToSearch,
            assistantMessage: assistantMessage,
            runtimeStats: runtimeStats
        )
    }

    /// Decide if a mid-session turn should flip the existing intent, based on
    /// cosine similarity against synced history rather than keyword matches.
    ///
    /// - Returns `.query` when the user is currently in a report flow but the
    ///   new utterance semantically matches synced history above threshold.
    /// - Returns `.report` when the user is currently in a query flow but the
    ///   new utterance no longer matches anything in history (score drops).
    /// - Returns `nil` to keep the current intent.
    func pivotIntent(
        for newTranscript: String,
        currentIntent: PhotoTurnIntent,
        cachedRecords: [CachedProjectChangeRecord]
    ) async -> PhotoTurnIntent? {
        let normalized = newTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        guard !cachedRecords.isEmpty else { return nil }

        // Explicit trigger words always win mid-session too.
        if let triggered = Self.triggerIntent(from: normalized) {
            ycLog("[pivotIntent] trigger keyword → \(triggered.rawValue) (currentIntent=\(currentIntent.rawValue))")
            return triggered == currentIntent ? nil : triggered
        }

        do {
            let top = try await ragService.scoreUtterance(normalized, against: cachedRecords)
            let score = top?.score ?? 0
            ycLog("[pivotIntent] currentIntent=\(currentIntent.rawValue) utterance=\"\(normalized)\" topScore=\(String(format: "%.3f", score))")

            switch currentIntent {
            case .report:
                // Topic must overlap AND Gemma must agree this is a question.
                // Avoids "user keeps describing new damage that resembles old
                // damage" thrashing into the query path.
                guard score >= Self.ragRoutingScoreThreshold else { return nil }
                return (try await gemmaStatementVsQuestion(normalized)) == .query ? .query : nil
            case .query:
                // Drop out of RAG only if the new utterance is clearly different
                // from anything in history. Hysteresis prevents flapping.
                return score < (Self.ragRoutingScoreThreshold - 0.1) ? .report : nil
            case .unclear:
                return nil
            }
        } catch {
            ycLog("[pivotIntent] ERROR scoring utterance (\(error.localizedDescription)) — no pivot")
            return nil
        }
    }

    /// Shared Gemma statement-vs-question classifier. 4 tokens, text-only.
    /// Used by both `classifyIntent` and `pivotIntent` when cosine already
    /// says the topic matches, so we only pay the ~2s Gemma cost when needed.
    private func gemmaStatementVsQuestion(_ utterance: String) async throws -> PhotoTurnIntent {
        let prompt = """
        A construction worker said: "\(utterance)"

        Is this a REPORT of a new defect to log, or a QUERY about an existing one?
        Reply with exactly one lowercase word: report or query.
        """
        let started = Date()
        let response = try await aiService.send(
            request: AIRequest(prompt: prompt, maxTokens: 4),
            conversation: []
        )
        let elapsed = Date().timeIntervalSince(started)
        let replyWord = response.text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .first(where: { !$0.isEmpty }) ?? ""
        ycLog("[pivotIntent] Gemma tiebreaker in \(String(format: "%.2f", elapsed))s → \"\(replyWord)\"")
        switch replyWord {
        case "query": return .query
        case "report": return .report
        default: return .unclear
        }
    }

    func answerQuery(
        state: PhotoQueryState,
        cachedRecords: [CachedProjectChangeRecord],
        stagedPhotoPath: String? = nil,
        onToken: (@Sendable (String) -> Void)? = nil
    ) async throws -> PhotoQueryAnswerOutcome {
        ycLog("[answerQuery] RAG INVOKED for query=\"\(state.questionSummary ?? state.combinedTranscript)\" cachedRecords=\(cachedRecords.count)")
        let indexedCount = try await ragService.refreshIndex(from: cachedRecords)
        let queryText = queryText(for: state)
        // Use the same threshold as routing, so "routed to RAG" → "found evidence".
        let queryResult = try await ragService.query(
            question: queryText,
            topK: 3,
            scoreThreshold: Self.ragRoutingScoreThreshold
        )

        guard !queryResult.matches.isEmpty else {
            ycLog("[answerQuery] RAG returned 0 matches above threshold — skipping Gemma, returning empty-evidence reply")
            return PhotoQueryAnswerOutcome(
                assistantMessage: "I couldn't find a matching prior report in the synced history on this iPhone, so I do not have enough evidence to explain this yet.",
                summaryText: "Local question search checked \(indexedCount) synced report(s) and found no strong evidence match.",
                runtimeStats: nil
            )
        }
        ycLog("[answerQuery] RAG matched \(queryResult.matches.count) record(s); sending to Gemma with evidence")

        let evidence = queryResult.matches
            .prefix(3)
            .enumerated()
            .map { index, match in
                compactEvidenceBlock(for: match, index: index + 1)
            }
            .joined(separator: "\n\n")

        let prompt = """
        Answer a worker's question about a staged construction photo.
        You cannot inspect the image itself.
        Use only the retrieved evidence below.
        If the evidence is weak, missing, or conflicting, say that plainly.
        Reply in 2 to 4 concise sentences.

        Question:
        \(state.questionSummary ?? state.combinedTranscript)

        Search context:
        storey=\(preferred(state.storey, nil) ?? "unknown")
        space=\(preferred(state.space, nil) ?? "unknown")
        orientation=\(preferred(state.orientation, nil) ?? "unknown")
        element_type=\(preferred(state.elementType, nil) ?? "unknown")
        timeframe=\(preferred(state.timeframeHint, nil) ?? "unknown")

        Evidence:
        \(evidence)
        """

        let imagesEnabled = LocalModelStore.supportsCameraContext
        let images = (imagesEnabled ? stagedPhotoPath.map { [$0] } : nil) ?? []
        let started = Date()
        let topScore = queryResult.matches.first?.score ?? 0
        ycLog("[answerQuery] sending Gemma call indexed=\(indexedCount) matches=\(queryResult.matches.count) topScore=\(String(format: "%.3f", topScore)) images=\(images.count) streaming=\(onToken != nil)")
        let request = AIRequest(prompt: prompt, imagePaths: images, maxTokens: 160)
        let response: AIResponse
        if let onToken {
            response = try await aiService.sendStreaming(
                request: request,
                conversation: [],
                onToken: onToken
            )
        } else {
            response = try await aiService.send(request: request, conversation: [])
        }
        let elapsed = Date().timeIntervalSince(started)
        ycLog("[answerQuery] Gemma replied in \(String(format: "%.2f", elapsed))s textLen=\(response.text.count)")

        return PhotoQueryAnswerOutcome(
            assistantMessage: response.text,
            summaryText: "Local question search matched \(queryResult.matches.count) report(s) out of \(indexedCount) indexed locally.",
            runtimeStats: response.runtimeStats
        )
    }

    private func makeReportPrompt(from state: PhotoReportState) -> String {
        let vocabBlock = vocabulary.promptConstraintBlock()
        let vocabSection = vocabBlock.isEmpty ? "" : "\n\(vocabBlock)\n"
        let known = state.fields.compactSummaryLines().joined(separator: ", ")
        let unknown = state.explicitlyUnknownFields.sorted().joined(separator: ", ")
        return """
        Construction defect report. Output JSON only.

        Transcript: \(state.combinedTranscript)
        Known: \(known)
        Marked unknown: \(unknown)
        \(vocabSection)
        Required: defect_type, severity (low|medium|high|critical), storey, element_type. Optional: space, orientation, guid, ai_safety_notes.

        Use real values from the transcript or null. NEVER write "string", "or null", "<...>", or schema placeholders as values.

        If a required field is missing, set ready_to_upload=false and ask one short follow-up question in assistant_message. Otherwise ready_to_upload=true.

        Example output:
        {"ready_to_upload":false,"assistant_message":"How severe is the crack: low, medium, high, or critical?","blocking_missing_fields":["severity"],"explicitly_unknown_fields":[],"fields":{"defect_type":"crack","severity":null,"storey":"Level 1","space":null,"orientation":"west","element_type":"wall","guid":null,"ai_safety_notes":null}}
        """
    }

    private func makeQueryPrompt(from state: PhotoQueryState) -> String {
        let vocabBlock = vocabulary.promptConstraintBlock()
        let vocabSection = vocabBlock.isEmpty ? "" : "\n\(vocabBlock)\n"
        let known = state.compactSummaryLines().joined(separator: ", ")
        return """
        Worker question for prior-report search. Output JSON only.

        Transcript: \(state.combinedTranscript)
        Known: \(known)
        \(vocabSection)
        question_summary should restate the question in one sentence. storey, space, orientation, element_type, timeframe_hint, ambiguity_note are optional.

        Use real values or null. NEVER write "string", "or null", "<...>", or schema placeholders as values.

        If the question is searchable, set ready_to_search=true. Otherwise ask one short follow-up in assistant_message.

        Example output:
        {"ready_to_search":true,"assistant_message":"Searching prior reports.","blocking_missing_fields":[],"state":{"question_summary":"Why is there a crack on the west wall on level 1?","storey":"Level 1","space":null,"orientation":"west","element_type":"wall","timeframe_hint":null,"ambiguity_note":null}}
        """
    }

    private func decodeReportDecision(from rawText: String) throws -> ReportDecision? {
        guard let jsonText = extractJSONObject(from: rawText) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(ReportDecision.self, from: Data(jsonText.utf8))
        } catch {
            ycLog("[decodeReportDecision] decode error: \(error)")
            throw error
        }
    }

    private func decodeQueryDecision(from rawText: String) throws -> QueryDecision? {
        guard let jsonText = extractJSONObject(from: rawText) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(QueryDecision.self, from: Data(jsonText.utf8))
        } catch {
            ycLog("[decodeQueryDecision] decode error: \(error)")
            throw error
        }
    }

    private func extractJSONObject(from rawText: String) -> String? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") else {
            return nil
        }
        return String(trimmed[start...end])
    }

    private func fallbackReportOutcome(
        for state: PhotoReportState,
        runtimeStats: AIRuntimeStats?
    ) -> PhotoReportTurnOutcome {
        var fallbackState = state
        fallbackState.fields = fallbackState.fields.merged(with: fallbackReportFields(from: fallbackState.combinedTranscript))
        let blockingFields = blockingReportFields(for: fallbackState)

        return PhotoReportTurnOutcome(
            state: fallbackState,
            readyToUpload: blockingFields.isEmpty,
            assistantMessage: blockingFields.isEmpty
                ? "I have enough to upload this report."
                : reportFollowUpMessage(for: blockingFields, state: fallbackState),
            runtimeStats: runtimeStats
        )
    }

    private func fallbackQueryOutcome(
        for state: PhotoQueryState,
        runtimeStats: AIRuntimeStats?
    ) -> PhotoQueryTurnOutcome {
        var fallbackState = state
        if preferred(fallbackState.questionSummary, nil) == nil {
            fallbackState.questionSummary = compactLine(from: fallbackState.combinedTranscript)
        }
        if preferred(fallbackState.storey, nil) == nil {
            fallbackState.storey = fallbackStorey(from: fallbackState.combinedTranscript)
        }
        if preferred(fallbackState.space, nil) == nil {
            fallbackState.space = fallbackSpace(from: fallbackState.combinedTranscript)
        }
        if preferred(fallbackState.orientation, nil) == nil {
            fallbackState.orientation = fallbackOrientation(from: fallbackState.combinedTranscript)
        }
        if preferred(fallbackState.elementType, nil) == nil {
            fallbackState.elementType = fallbackElementType(from: fallbackState.combinedTranscript)
        }

        let blockingFields = blockingQueryFields(for: fallbackState)
        return PhotoQueryTurnOutcome(
            state: fallbackState,
            readyToSearch: blockingFields.isEmpty,
            assistantMessage: blockingFields.isEmpty
                ? "Searching the synced report history locally."
                : queryFollowUpMessage(for: blockingFields, state: fallbackState),
            runtimeStats: runtimeStats
        )
    }

    private func blockingReportFields(for state: PhotoReportState) -> [String] {
        let unknowns = state.explicitlyUnknownFields
        let candidates: [(String, String?)] = [
            ("defect_type", state.fields.defectType),
            ("severity", state.fields.severity),
            ("storey", state.fields.storey),
            ("element_type", state.fields.elementType)
        ]

        return candidates.compactMap { fieldName, value in
            if unknowns.contains(fieldName) {
                return nil
            }
            return PhotoReportFields.normalizedText(value) == nil ? fieldName : nil
        }
    }

    private func blockingQueryFields(for state: PhotoQueryState) -> [String] {
        guard let questionSummary = preferred(state.questionSummary, nil) else {
            return ["question_summary"]
        }

        let normalized = questionSummary
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if [
            "why",
            "what",
            "when",
            "how",
            "who",
            "where",
            "why?",
            "what?",
            "when?",
            "how?"
        ].contains(normalized) {
            return ["question_summary"]
        }

        if normalized.count < 10,
           !Self.containsAny(normalized, ["hole", "crack", "leak", "damage", "issue", "problem", "wall", "ceiling", "window", "door"]) {
            return ["question_summary"]
        }

        return []
    }

    private func queryText(for state: PhotoQueryState) -> String {
        [
            "question: \(state.questionSummary ?? state.combinedTranscript)",
            "storey: \(preferred(state.storey, nil) ?? "unknown")",
            "space: \(preferred(state.space, nil) ?? "unknown")",
            "orientation: \(preferred(state.orientation, nil) ?? "unknown")",
            "element_type: \(preferred(state.elementType, nil) ?? "unknown")",
            "timeframe_hint: \(preferred(state.timeframeHint, nil) ?? "unknown")"
        ]
        .joined(separator: "\n")
    }

    private static func intentClarificationMessage(for intent: PhotoTurnIntent) -> String {
        switch intent {
        case .report:
            return "I’m treating this as a new report."
        case .query:
            return "I’m treating this as a question about an existing issue."
        case .unclear:
            return "Is this a new report, or a question about an existing issue?"
        }
    }

    private func reportFollowUpMessage(for blockingFields: [String], state: PhotoReportState) -> String {
        let fields = Set(blockingFields)
        let issueLabel = preferred(state.fields.defectType, nil) ?? "issue"
        let repeated = state.repeatedFollowUpCount > 0

        if repeated {
            if fields == Set(["severity"]) {
                return "I still need the \(issueLabel) severity as low, medium, high, or critical. If you do not know, say unknown."
            }
            if fields == Set(["storey"]) {
                return "I still need the level for this \(issueLabel). If you do not know, say unknown."
            }
            if fields == Set(["element_type"]) {
                return "I still need the affected element for this \(issueLabel), like wall, ceiling, door, or window. If you do not know, say unknown."
            }
            return "I still need a few report details before I upload the photo. Answer with the missing detail, or say unknown to leave it blank."
        }

        if fields.contains("storey") && fields.contains("element_type") && fields.contains("severity") {
            return "I have this as a \(issueLabel). What level is it on, what element is affected, and how severe is it: low, medium, high, or critical?"
        }
        if fields.contains("storey") && fields.contains("element_type") {
            return "I have this as a \(issueLabel). What storey is it on, and what element is the photo showing?"
        }
        if fields.contains("defect_type") && fields.contains("severity") {
            return "What issue are you reporting here, and how severe is it?"
        }
        if fields.contains("storey") {
            return "What storey or level is this \(issueLabel) on?"
        }
        if fields.contains("element_type") {
            return "What element has the \(issueLabel), like a wall, door, window, or ceiling?"
        }
        if fields.contains("defect_type") {
            return "What issue are you reporting in the staged photo?"
        }
        if fields.contains("severity") {
            return "How severe is the \(issueLabel): low, medium, high, or critical?"
        }
        return "What detail is still missing from this report?"
    }

    private func queryFollowUpMessage(for blockingFields: [String], state: PhotoQueryState) -> String {
        if blockingFields.contains("question_summary") {
            let issueLabel = preferred(fallbackDefectType(from: state.combinedTranscript), nil) ?? "issue"
            return "What do you want to know about this \(issueLabel), like why it is there, when it appeared, or who created it?"
        }
        return "What else should I use before I search the synced report history?"
    }

    private func fallbackReportFields(from text: String) -> PhotoReportFields {
        PhotoReportFields(
            defectType: fallbackDefectType(from: text),
            severity: fallbackSeverity(from: text),
            storey: fallbackStorey(from: text),
            space: fallbackSpace(from: text),
            orientation: fallbackOrientation(from: text),
            elementType: fallbackElementType(from: text),
            guid: fallbackGUID(from: text),
            aiSafetyNotes: nil
        )
    }

    private func fallbackGUID(from text: String) -> String? {
        let pattern = #"\b[0-9A-Za-z]{20,32}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              let range = Range(match.range(at: 0), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private func fallbackStorey(from text: String) -> String? {
        let lowercased = text.lowercased()
        if Self.containsAny(lowercased, ["roof", "rooftop", "azotea"]) {
            return "Roof"
        }
        if Self.containsAny(lowercased, [
            "third floor", "3rd floor", "level 3", "level three", "third level", "tercer piso"
        ]) {
            return "Level 3"
        }
        if Self.containsAny(lowercased, [
            "second floor", "2nd floor", "level 2", "level two", "second level",
            "upstairs", "segundo piso", "segundo nivel"
        ]) {
            return "Level 2"
        }
        if Self.containsAny(lowercased, ["basement", "foundation", "fundacion", "fundación", "t/fdn"]) {
            return "T/FDN"
        }
        if Self.containsAny(lowercased, [
            "first floor", "1st floor", "level 1", "level one", "first level",
            "main floor", "ground floor", "primer piso", "primer nivel"
        ]) {
            return "Level 1"
        }
        return nil
    }

    private func fallbackElementType(from text: String) -> String? {
        // Strip storey-style "first floor / second floor / level 1 floor" so they
        // don't get classified as the "floor" element.
        let storeyAdjacentFloorPatterns = [
            "first floor", "1st floor",
            "second floor", "2nd floor",
            "third floor", "3rd floor",
            "ground floor", "main floor",
            "level 1 floor", "level 2 floor", "level 3 floor"
        ]
        var lowercased = text.lowercased()
        for pattern in storeyAdjacentFloorPatterns {
            lowercased = lowercased.replacingOccurrences(of: pattern, with: " ")
        }

        let orderedMatches: [(String, [String])] = [
            ("window", ["window", "glass", "pane", "ventana"]),
            ("door", ["door", "frame", "hinge", "puerta"]),
            ("wall", ["wall", "drywall", "stud", "muro", "pared"]),
            ("ceiling", ["ceiling", "drywall ceiling", "techo interior"]),
            ("roof", ["roof", "rooftop", "azotea"]),
            ("beam", ["beam", "viga"]),
            ("column", ["column", "pillar", "columna"]),
            ("pipe", ["pipe", "plumbing", "tuberia", "tubería"]),
            ("floor", ["floor", "tile", "slab", "piso"])
        ]

        for (candidate, patterns) in orderedMatches where Self.containsAny(lowercased, patterns) {
            return candidate
        }

        return nil
    }

    private func fallbackOrientation(from text: String) -> String? {
        let lowercased = text.lowercased()
        if Self.containsAny(lowercased, ["north", "norte"]) {
            return "north"
        }
        if Self.containsAny(lowercased, ["south", "sur"]) {
            return "south"
        }
        if Self.containsAny(lowercased, ["east", "este"]) {
            return "east"
        }
        if Self.containsAny(lowercased, ["west", "oeste"]) {
            return "west"
        }
        return nil
    }

    private func fallbackDefectType(from text: String) -> String? {
        let lowercased = text.lowercased()
        let orderedMatches: [(String, [String])] = [
            ("water damage", ["water damage", "water stain", "leak", "leaking", "moisture", "humidity", "wet", "damp", "fuga", "humedad"]),
            ("crack", ["crack", "cracked", "fracture", "grieta"]),
            ("hole", ["hole", "puncture", "opening", "hueco", "agujero"]),
            ("broken glass", ["broken glass", "shattered", "pane", "glass", "vidrio"]),
            ("alignment issue", ["doesn't close", "does not close", "misaligned", "alignment", "crooked", "sticking", "not flush"]),
            ("mold", ["mold", "mildew", "moho"]),
            ("rust", ["rust", "corrosion", "oxidation"]),
            ("peeling paint", ["peeling", "paint", "painted", "descascarada"]),
            ("stain", ["stain", "staining", "mark", "spot", "mancha"]),
            ("broken fixture", ["broken", "damaged", "loose", "detached", "unsafe"])
        ]

        for (candidate, patterns) in orderedMatches where Self.containsAny(lowercased, patterns) {
            return candidate
        }

        return nil
    }

    private func fallbackSeverity(from text: String) -> String? {
        let lowercased = text.lowercased()
        if Self.containsAny(lowercased, ["critical", "immediate danger", "emergency", "unsafe right now", "life safety"]) {
            return "critical"
        }
        if Self.containsAny(lowercased, ["high severity", "severe", "serious", "major", "large", "big", "structural", "hazard", "unsafe"]) {
            return "high"
        }
        if Self.containsAny(lowercased, ["medium severity", "moderate", "medium"]) {
            return "medium"
        }
        if Self.containsAny(lowercased, ["low severity", "minor", "small", "cosmetic", "light"]) {
            return "low"
        }
        return nil
    }

    private func fallbackSpace(from text: String) -> String? {
        let pattern = #"\b([A-Za-z]\d{3})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range]).uppercased()
    }

    private func applyReportHeuristics(to state: inout PhotoReportState, newTranscript: String) {
        let missingBefore = blockingReportFields(for: state)
        if Self.isUnknownReply(newTranscript) {
            state.explicitlyUnknownFields.formUnion(missingBefore.map(Self.normalizedFieldName))
        }

        let extractedFields = fallbackReportFields(from: state.combinedTranscript)
        state.fields = state.fields.merged(with: extractedFields)

        if PhotoReportFields.normalizedText(state.fields.severity) == nil,
           let inferredSeverity = inferHoleSeverityFromDimensions(in: state.combinedTranscript) {
            state.fields.severity = inferredSeverity
        }

        if let aiSafetyNotes = combinedSafetyNotes(from: state.combinedTranscript, existingNotes: state.fields.aiSafetyNotes) {
            state.fields.aiSafetyNotes = preferred(aiSafetyNotes, state.fields.aiSafetyNotes)
        }

        state.explicitlyUnknownFields.subtract(resolvedFieldNames(from: state.fields))
    }

    private func applyQueryHeuristics(to state: inout PhotoQueryState) {
        state.questionSummary = preferred(compactQuestionSummary(from: state.combinedTranscript), state.questionSummary)
        state.storey = preferred(fallbackStorey(from: state.combinedTranscript), state.storey)
        state.space = preferred(fallbackSpace(from: state.combinedTranscript), state.space)
        state.orientation = preferred(fallbackOrientation(from: state.combinedTranscript), state.orientation)
        state.elementType = preferred(fallbackElementType(from: state.combinedTranscript), state.elementType)
        state.timeframeHint = preferred(fallbackTimeframe(from: state.combinedTranscript), state.timeframeHint)

        if Self.containsAny(state.combinedTranscript.lowercased(), ["maybe", "not sure", "unsure", "i think"]) {
            state.ambiguityNote = preferred("The worker sounded unsure about some of the details.", state.ambiguityNote)
        }
    }

    private func compactEvidenceBlock(for match: LocalRAGMatch, index: Int) -> String {
        [
            "Match \(index) score=\(String(format: "%.3f", match.score))",
            "when: \(match.record.timestamp.ISO8601Format())",
            "location: \(match.record.storey) / \(match.record.space ?? "unknown") / \(match.record.orientation ?? "unknown")",
            "issue: \(match.record.defectType) on \(match.record.elementType) severity=\(match.record.severity) resolved=\(match.record.resolved ? "yes" : "no")",
            "report: \(trimmedEvidenceText(match.record.transcriptEnglish ?? match.record.transcriptOriginal ?? "", maxLength: 220))",
            "notes: \(trimmedEvidenceText(match.record.aiSafetyNotes ?? "", maxLength: 140))",
            "photo_url: \(match.record.photoURL ?? "")",
            "bcf_path: \(match.record.bcfPath ?? "")"
        ]
        .joined(separator: "\n")
    }

    private func trimmedEvidenceText(_ text: String, maxLength: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard collapsed.count > maxLength else {
            return collapsed
        }

        return String(collapsed.prefix(maxLength)) + "..."
    }

    private func compactQuestionSummary(from text: String) -> String? {
        guard let summary = compactLine(from: text) else {
            return nil
        }

        if summary.count <= 220 {
            return summary
        }

        return String(summary.prefix(220)) + "..."
    }

    private func fallbackTimeframe(from text: String) -> String? {
        let lowercased = text.lowercased()
        if Self.containsAny(lowercased, ["today", "this morning", "this afternoon", "right now"]) {
            return "today"
        }
        if Self.containsAny(lowercased, ["yesterday", "last night"]) {
            return "yesterday"
        }
        if Self.containsAny(lowercased, ["last week", "earlier this week"]) {
            return "last week"
        }
        if Self.containsAny(lowercased, ["before drywall", "before paint", "before inspection"]) {
            return "before a later construction step"
        }
        if Self.containsAny(lowercased, ["after drywall", "after paint", "after inspection"]) {
            return "after a later construction step"
        }
        return nil
    }

    private func fallbackSafetyNotes(from text: String) -> String? {
        let lowercased = text.lowercased()
        if Self.containsAny(lowercased, ["drilled", "cut", "demo", "demolition", "opened up", "made this hole"]) {
            return "The worker said the opening may have been intentionally created during construction work."
        }
        if Self.containsAny(lowercased, ["exposed wire", "electrical", "live wire", "unsafe", "hazard"]) {
            return "Potential safety issue mentioned in the voice note."
        }
        return nil
    }

    private func combinedSafetyNotes(from text: String, existingNotes: String?) -> String? {
        var notes: [String] = []

        if let existing = preferred(existingNotes, nil) {
            notes.append(existing)
        }

        if let fallback = fallbackSafetyNotes(from: text), !notes.contains(fallback) {
            notes.append(fallback)
        }

        if let depthNote = holeDimensionNote(from: text), !notes.contains(depthNote) {
            notes.append(depthNote)
        }

        guard !notes.isEmpty else {
            return nil
        }

        return notes.joined(separator: " ")
    }

    private func inferHoleSeverityFromDimensions(in text: String) -> String? {
        let lowercased = text.lowercased()
        // Only infer hole severity when the worker actually describes a hole or opening.
        guard Self.containsAny(lowercased, ["hole", "opening", "agujero", "hueco", "puncture", "depth", "deep", "all the way through"]) else {
            return nil
        }

        if Self.containsAny(lowercased, ["very deep", "deep hole", "through wall", "through the wall", "all the way through"]) {
            return "high"
        }

        if Self.containsAny(lowercased, ["shallow", "surface only"]) {
            return "low"
        }

        guard let measuredInches = extractApproximateInches(from: lowercased) else {
            return nil
        }

        switch measuredInches {
        case ..<2:
            return "low"
        case ..<6:
            return "medium"
        default:
            return "high"
        }
    }

    private func holeDimensionNote(from text: String) -> String? {
        let lowercased = text.lowercased()
        // Don't tag every "10 feet" sentence as a hole — require explicit opening context.
        guard Self.containsAny(lowercased, ["hole", "opening", "agujero", "hueco", "puncture", "depth", "deep", "all the way through"]) else {
            return nil
        }
        guard let measuredInches = extractApproximateInches(from: lowercased) else {
            return nil
        }

        return String(format: "The worker described the opening as about %.1f inches deep.", measuredInches)
    }

    private func extractApproximateInches(from text: String) -> Double? {
        let patterns: [(String, Double)] = [
            (#"(\d+(?:\.\d+)?)\s*(inch|inches|in\b|")"#, 1.0),
            (#"(\d+(?:\.\d+)?)\s*(foot|feet|ft\b|')"#, 12.0),
            (#"(\d+(?:\.\d+)?)\s*(cm|centimeter|centimeters)"#, 0.3937007874),
            (#"(\d+(?:\.\d+)?)\s*(mm|millimeter|millimeters)"#, 0.0393700787)
        ]

        for (pattern, multiplier) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsRange = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: nsRange),
                  let valueRange = Range(match.range(at: 1), in: text),
                  let rawValue = Double(text[valueRange]) else {
                continue
            }
            return rawValue * multiplier
        }

        return nil
    }

    private func resolvedFieldNames(from fields: PhotoReportFields) -> Set<String> {
        var resolved: Set<String> = []
        if PhotoReportFields.normalizedText(fields.defectType) != nil {
            resolved.insert("defect_type")
        }
        if PhotoReportFields.normalizedText(fields.severity) != nil {
            resolved.insert("severity")
        }
        if PhotoReportFields.normalizedText(fields.storey) != nil {
            resolved.insert("storey")
        }
        if PhotoReportFields.normalizedText(fields.space) != nil {
            resolved.insert("space")
        }
        if PhotoReportFields.normalizedText(fields.orientation) != nil {
            resolved.insert("orientation")
        }
        if PhotoReportFields.normalizedText(fields.elementType) != nil {
            resolved.insert("element_type")
        }
        if PhotoReportFields.normalizedText(fields.guid) != nil {
            resolved.insert("guid")
        }
        if PhotoReportFields.normalizedText(fields.aiSafetyNotes) != nil {
            resolved.insert("ai_safety_notes")
        }
        return resolved
    }

    private func joinHistory(_ transcriptHistory: [String]) -> String {
        transcriptHistory
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func compactLine(from text: String) -> String? {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? nil : collapsed
    }

    private func preferred(_ candidate: String?, _ existing: String?) -> String? {
        Self.nonEmpty(candidate) ?? Self.nonEmpty(existing)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedFieldName(_ fieldName: String) -> String {
        fieldName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func containsAny(_ text: String, _ candidates: [String]) -> Bool {
        candidates.contains(where: { text.contains($0) })
    }

    private static func isUnknownReply(_ text: String) -> Bool {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return [
            "unknown",
            "not sure",
            "unsure",
            "i don't know",
            "i dont know",
            "dont know",
            "no idea",
            "leave it blank",
            "blank",
            "n/a"
        ].contains(normalized)
    }

}
