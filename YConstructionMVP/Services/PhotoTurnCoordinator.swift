import Foundation

enum PhotoTurnIntent: String, Codable, Equatable, Sendable {
    case report
    case query
    case unclear
}

struct PhotoReportFields: Codable, Equatable, Sendable {
    var defectType: String?
    var severity: String?
    var storey: String?
    var space: String?
    var orientation: String?
    var elementType: String?
    var guid: String?
    var aiSafetyNotes: String?

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
        if ["unknown", "n/a", "none", "null", "blank"].contains(trimmed.lowercased()) {
            return nil
        }
        return trimmed
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

struct PhotoReportState: Equatable, Sendable {
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

struct PhotoQueryState: Equatable, Sendable {
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

struct PhotoIntentDecision: Sendable {
    let intent: PhotoTurnIntent
    let assistantMessage: String
}

struct PhotoReportTurnOutcome: Sendable {
    let state: PhotoReportState
    let readyToUpload: Bool
    let assistantMessage: String
    let runtimeStats: AIRuntimeStats?
}

struct PhotoQueryTurnOutcome: Sendable {
    let state: PhotoQueryState
    let readyToSearch: Bool
    let assistantMessage: String
    let runtimeStats: AIRuntimeStats?
}

struct PhotoQueryAnswerOutcome: Sendable {
    let assistantMessage: String
    let summaryText: String
    let runtimeStats: AIRuntimeStats?
}

actor PhotoTurnCoordinator {
    private struct ReportDecision: Codable {
        let readyToUpload: Bool
        let assistantMessage: String
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

    private struct QueryDecision: Codable {
        struct StatePayload: Codable {
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
        let assistantMessage: String
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

    init(aiService: any AIService, ragService: LocalRAGService) {
        self.aiService = aiService
        self.ragService = ragService
    }

    func classifyIntent(transcriptHistory: [String]) async -> PhotoIntentDecision {
        let combinedTranscript = joinHistory(transcriptHistory)
        let heuristicIntent = Self.fallbackIntent(from: combinedTranscript)
        if heuristicIntent != .unclear {
            return PhotoIntentDecision(
                intent: heuristicIntent,
                assistantMessage: Self.intentClarificationMessage(for: heuristicIntent)
            )
        }

        let prompt = """
        Classify this staged-photo construction turn.
        Reply with one lowercase word only: report, query, or unclear.

        \(combinedTranscript)
        """

        do {
            let response = try await aiService.send(
                request: AIRequest(prompt: prompt, maxTokens: 8),
                conversation: []
            )
            let intent = Self.parseIntent(from: response.text) ?? Self.fallbackIntent(from: combinedTranscript)
            return PhotoIntentDecision(
                intent: intent,
                assistantMessage: Self.intentClarificationMessage(for: intent)
            )
        } catch {
            let intent = Self.fallbackIntent(from: combinedTranscript)
            return PhotoIntentDecision(
                intent: intent,
                assistantMessage: Self.intentClarificationMessage(for: intent)
            )
        }
    }

    func processReportTurn(
        existingState: PhotoReportState?,
        newTranscript: String,
        createdAt: Date
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
        let readyToUpload = blockingFields.isEmpty
        let assistantMessage = readyToUpload
            ? "I have enough to upload this report."
            : reportFollowUpMessage(for: blockingFields, state: state)

        return PhotoReportTurnOutcome(
            state: state,
            readyToUpload: readyToUpload,
            assistantMessage: assistantMessage,
            runtimeStats: nil
        )
    }

    func processQueryTurn(
        existingState: PhotoQueryState?,
        newTranscript: String,
        createdAt: Date
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

        let blockingFields = blockingQueryFields(for: state)
        let readyToSearch = blockingFields.isEmpty
        let assistantMessage = readyToSearch
            ? "Searching the synced report history locally."
            : queryFollowUpMessage(for: blockingFields, state: state)

        return PhotoQueryTurnOutcome(
            state: state,
            readyToSearch: readyToSearch,
            assistantMessage: assistantMessage,
            runtimeStats: nil
        )
    }

    func pivotIntent(for newTranscript: String, currentIntent: PhotoTurnIntent) -> PhotoTurnIntent? {
        let normalized = newTranscript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else {
            return nil
        }

        switch currentIntent {
        case .report:
            return Self.looksLikeQuestion(normalized) ? .query : nil
        case .query:
            return Self.looksLikeExplicitReport(normalized) ? .report : nil
        case .unclear:
            return nil
        }
    }

    func answerQuery(
        state: PhotoQueryState,
        cachedRecords: [CachedProjectChangeRecord]
    ) async throws -> PhotoQueryAnswerOutcome {
        let indexedCount = try await ragService.refreshIndex(from: cachedRecords)
        let queryText = queryText(for: state)
        let queryResult = try await ragService.query(question: queryText, topK: 3, scoreThreshold: 0.60)

        guard !queryResult.matches.isEmpty else {
            return PhotoQueryAnswerOutcome(
                assistantMessage: "I couldn't find a matching prior report in the synced history on this iPhone, so I do not have enough evidence to explain this yet.",
                summaryText: "Local question search checked \(indexedCount) synced report(s) and found no strong evidence match.",
                runtimeStats: nil
            )
        }

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

        let response = try await aiService.send(
            request: AIRequest(prompt: prompt, maxTokens: 96),
            conversation: []
        )

        return PhotoQueryAnswerOutcome(
            assistantMessage: response.text,
            summaryText: "Local question search matched \(queryResult.matches.count) report(s) out of \(indexedCount) indexed locally.",
            runtimeStats: response.runtimeStats
        )
    }

    private func makeReportPrompt(from state: PhotoReportState) -> String {
        """
        You are completing a staged-photo construction report for these Supabase columns:
        - defect_type
        - severity
        - storey
        - space
        - orientation
        - element_type
        - guid
        - ai_safety_notes

        You cannot inspect the image pixels. Use only the worker's spoken words. You may refer to the staged photo conversationally.

        Current known values:
        \(state.fields.compactSummaryLines().joined(separator: "\n"))

        Explicitly unknown fields:
        \(state.explicitlyUnknownFields.sorted().joined(separator: ", "))

        Worker transcript history:
        \(state.combinedTranscript)

        Return ONLY valid JSON with this exact shape:
        {
          "ready_to_upload": true,
          "assistant_message": "short message",
          "blocking_missing_fields": ["field_name"],
          "explicitly_unknown_fields": ["field_name"],
          "fields": {
            "defect_type": "string or null",
            "severity": "low|medium|high|critical or null",
            "storey": "string or null",
            "space": "string or null",
            "orientation": "string or null",
            "element_type": "string or null",
            "guid": "string or null",
            "ai_safety_notes": "string or null"
          }
        }

        Rules:
        - Merge the newest answer with the earlier transcript history.
        - Ask at most two concise follow-up questions when detail is still missing.
        - If the worker says unknown, not sure, no, or blank for a field, keep it null and include that field in explicitly_unknown_fields.
        - Try to fill defect_type, severity, storey, and element_type first.
        - space, orientation, guid, and ai_safety_notes are optional.
        - If required fields are still unknown and not explicitly marked unknown, set ready_to_upload to false.
        - If enough information is present, set ready_to_upload to true.
        - Do not mention JSON.
        """
    }

    private func makeQueryPrompt(from state: PhotoQueryState) -> String {
        """
        You are preparing a staged-photo construction question for local report search.

        The worker is asking about an existing issue. You cannot inspect the image pixels. Use only the transcript.

        Current known values:
        \(state.compactSummaryLines().joined(separator: "\n"))

        Worker transcript history:
        \(state.combinedTranscript)

        Return ONLY valid JSON with this exact shape:
        {
          "ready_to_search": true,
          "assistant_message": "short message",
          "blocking_missing_fields": ["field_name"],
          "state": {
            "question_summary": "string or null",
            "storey": "string or null",
            "space": "string or null",
            "orientation": "string or null",
            "element_type": "string or null",
            "timeframe_hint": "string or null",
            "ambiguity_note": "string or null"
          }
        }

        Rules:
        - question_summary should restate the worker's question for search.
        - storey, space, orientation, element_type, and timeframe_hint are optional hints.
        - Ask a short follow-up only if the question is too vague to search.
        - If the question is already usable, set ready_to_search to true.
        - Do not mention JSON.
        """
    }

    private func decodeReportDecision(from rawText: String) throws -> ReportDecision? {
        guard let jsonText = extractJSONObject(from: rawText) else {
            return nil
        }
        return try JSONDecoder().decode(ReportDecision.self, from: Data(jsonText.utf8))
    }

    private func decodeQueryDecision(from rawText: String) throws -> QueryDecision? {
        guard let jsonText = extractJSONObject(from: rawText) else {
            return nil
        }
        return try JSONDecoder().decode(QueryDecision.self, from: Data(jsonText.utf8))
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

    private static func parseIntent(from rawText: String) -> PhotoTurnIntent? {
        let normalized = rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let tokens = normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        for token in tokens {
            if let intent = PhotoTurnIntent(rawValue: token) {
                return intent
            }
        }
        return nil
    }

    private static func fallbackIntent(from text: String) -> PhotoTurnIntent {
        let lowercased = text.lowercased()
        if Self.containsAny(lowercased, [
            "why", "when", "how", "what", "who", "where", "did", "does", "is there", "was there", "what happened"
        ]) || lowercased.contains("?") {
            return .query
        }

        if Self.containsAny(lowercased, [
            "report", "found", "there is", "there's", "i made", "i found", "hole", "crack", "leak", "broken", "damage", "issue", "problem"
        ]) {
            return .report
        }

        return .unclear
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
        if Self.containsAny(lowercased, ["second floor", "2nd floor", "level 2", "second level", "upstairs", "segundo piso", "segundo nivel"]) {
            return "Level 2"
        }
        if Self.containsAny(lowercased, ["basement", "foundation", "fundacion", "fundación", "t/fdn"]) {
            return "T/FDN"
        }
        if Self.containsAny(lowercased, ["first floor", "1st floor", "level 1", "main floor", "ground floor"]) {
            return "Level 1"
        }
        return nil
    }

    private func fallbackElementType(from text: String) -> String? {
        let lowercased = text.lowercased()
        let orderedMatches: [(String, [String])] = [
            ("window", ["window", "glass", "pane", "ventana"]),
            ("door", ["door", "frame", "hinge", "puerta"]),
            ("ceiling", ["ceiling", "drywall ceiling", "techo interior"]),
            ("floor", ["floor", "tile", "slab", "piso"]),
            ("roof", ["roof", "rooftop", "azotea"]),
            ("beam", ["beam", "viga"]),
            ("column", ["column", "pillar", "columna"]),
            ("pipe", ["pipe", "plumbing", "tuberia", "tubería"]),
            ("wall", ["wall", "drywall", "stud", "muro", "pared"])
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
        guard Self.containsAny(lowercased, ["hole", "opening", "agujero", "hueco", "depth", "deep", "inch", "inches", "cm", "foot", "feet"]) else {
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
        guard let measuredInches = extractApproximateInches(from: text.lowercased()) else {
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

    private static func looksLikeQuestion(_ text: String) -> Bool {
        if text.contains("?") {
            return true
        }

        let questionPrefixes = [
            "why",
            "what",
            "when",
            "how",
            "who",
            "where",
            "did",
            "does",
            "do ",
            "is ",
            "was ",
            "are ",
            "can ",
            "could ",
            "should ",
            "would "
        ]

        if questionPrefixes.contains(where: { text.hasPrefix($0) }) {
            return true
        }

        return containsAny(text, [
            "i want to ask",
            "i am asking",
            "i'm asking",
            "i have a question",
            "question about",
            "want to know",
            "need to know"
        ])
    }

    private static func looksLikeExplicitReport(_ text: String) -> Bool {
        guard !looksLikeQuestion(text) else {
            return false
        }

        return containsAny(text, [
            "report this",
            "report it",
            "new report",
            "for a report",
            "this is a report",
            "log this",
            "log it",
            "save this",
            "save it",
            "upload this",
            "upload it",
            "i want to report",
            "i need to report",
            "this is a new issue",
            "it's a new issue"
        ])
    }
}
