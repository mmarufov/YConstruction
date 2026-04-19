import Foundation

nonisolated enum GemmaServiceError: Error, LocalizedError {
    case invalidResponse(String)
    case inferenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let msg): return "Invalid Gemma response: \(msg)"
        case .inferenceFailed(let msg): return "Gemma inference failed: \(msg)"
        }
    }
}

nonisolated struct ExtractedDefect: Codable, Sendable {
    var storey: String
    var space: String?
    var elementType: String
    var orientation: String?
    var defectType: String
    var severity: String
}

nonisolated struct PhotoRequest: Codable, Sendable {
    var reason: String
}

nonisolated struct PhotoAnalysis: Codable, Sendable {
    var visibleDefectCount: Int
    var severityAssessment: String
    var safetyNotes: String
}

nonisolated struct AudioTurnResult: Sendable {
    let transcriptEnglish: String?
    let extraction: ExtractedDefect?
    let photoRequest: PhotoRequest?
    let raw: String
}

nonisolated struct VisionTurnResult: Sendable {
    let analysis: PhotoAnalysis?
    let raw: String
}

actor GemmaService {
    static let shared = GemmaService()

    private let cactus: CactusService

    private init(cactus: CactusService = .shared) {
        self.cactus = cactus
    }

    // MARK: - Prompts

    private static let systemPromptAudio = """
    You are an assistant for a construction defect reporting app. A field worker speaks \
    in Spanish or English about a building defect. ALWAYS call `extractDefect` exactly once. \
    If visual confirmation would add value (visible damage, structural concern, hazard), \
    ALSO call `requestPhoto`.

    Respond with the English translation of the transcript as your message `content`, \
    then the tool calls.

    ─── ALLOWED ENUM VALUES ── never invent values outside these sets ───
    - storey:      "T/FDN" | "Level 1" | "Level 2" | "Roof"
    - elementType: "wall" | "door" | "window" | "space"
    - orientation: "north" | "south" | "east" | "west" | null
    - severity:    "low" | "medium" | "high" | "critical"
    - space:       short alphanumeric code like "A101", "B204", or null if not mentioned.
    - defectType:  short lowercase label like "crack", "water damage", "broken glass", \
                   "alignment issue", "stain", "peeling paint".

    ─── STOREY MAPPING (Spanish ↔ English) ───
    - "sótano" / "fundación" / "basement" / "foundation"                       → "T/FDN"
    - "planta baja" / "primer piso" / "primer nivel" / "ground floor" / "first floor" → "Level 1"
    - "segundo piso" / "segundo nivel" / "planta alta" / "second floor"        → "Level 2"
    - "azotea" / "techo" (as roof) / "roof" / "rooftop"                        → "Roof"

    ─── ORIENTATION MAPPING ───
    - "norte" / "N" / "north" → "north"
    - "sur"   / "S" / "south" → "south"
    - "este"  / "E" / "east"  → "east"
    - "oeste" / "O" / "W" / "west" → "west"
    - If the worker did NOT explicitly name a compass direction (e.g. "back wall", \
      "pared del fondo", "la pared de atrás"), set orientation to null. \
      NEVER infer orientation from context.

    ─── SEVERITY RUBRIC ───
    - critical: structural collapse risk or immediate safety hazard
    - high:     structural concern, hazardous damage, or anything needing urgent attention
    - medium:   functional issue, degraded condition, minor safety concern
    - low:      cosmetic only

    Ask for a photo when visual confirmation adds real value. Do NOT ask for one for purely \
    functional complaints like "door doesn't close" unless visible damage is implied.

    ─── EXAMPLES ───

    Worker: "Hay una grieta en la pared norte del baño B101, parece estructural."
    Response:
      content: "There is a crack in the north wall of bathroom B101, looks structural."
      extractDefect(storey="Level 1", space="B101", elementType="wall", orientation="north",
                    defectType="crack", severity="high")
      requestPhoto(reason="Confirm crack pattern for structural assessment")

    Worker: "La puerta de la habitación A205 no cierra bien en el segundo piso."
    Response:
      content: "The door in room A205 doesn't close properly on the second floor."
      extractDefect(storey="Level 2", space="A205", elementType="door", orientation=null,
                    defectType="alignment issue", severity="low")

    Worker: "The east window in room A102 has a broken pane."
    Response:
      content: "The east window in room A102 has a broken pane."
      extractDefect(storey="Level 1", space="A102", elementType="window", orientation="east",
                    defectType="broken glass", severity="high")
      requestPhoto(reason="Assess glass breakage and safety hazard")

    Worker: "Hay manchas de humedad en la pared del fondo del comedor A104, planta baja."
    Response:
      content: "There is damp staining on the back wall of dining room A104 on the ground floor."
      extractDefect(storey="Level 1", space="A104", elementType="wall", orientation=null,
                    defectType="water damage", severity="medium")
      requestPhoto(reason="Visual extent of water intrusion")
    """

    private static let systemPromptVision = """
    You are analyzing a construction site photo of a reported defect. Call `analyzePhoto` \
    exactly once.

    FIELDS:
    - visibleDefectCount: integer count of distinct visible defects in the photo (0 if none).
    - severityAssessment: "low" | "medium" | "high" | "critical"
    - safetyNotes: ONE short paragraph (1–3 sentences) describing visible safety concerns.

    ─── SEVERITY RUBRIC ───
    - critical: imminent collapse risk, large structural cracks >5mm or propagating, severe \
                active water pooling, exposed rebar with corrosion, broken load-bearing element.
    - high:     widening cracks 3–5mm, significant water damage, unstable fixtures, broken \
                safety glass, compromised fire barrier.
    - medium:   localized damage, surface cracks <3mm, stains without active leak, minor \
                functional issues.
    - low:      cosmetic flaws only (chipped paint, minor scuffs, surface discoloration).

    BE CONSERVATIVE when the image is unclear or blurry — err toward a LOWER severity and \
    note the uncertainty in safetyNotes rather than guessing. Do NOT speculate about defects \
    not visible in the photo.
    """

    private static let toolsJson: String = {
        let tools: [[String: Any]] = [
            [
                "type": "function",
                "function": [
                    "name": "extractDefect",
                    "description": "Extract structured defect information from the worker's description.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "storey": ["type": "string", "description": "Building level"],
                            "space": ["type": ["string", "null"], "description": "Room/space code like A101"],
                            "elementType": ["type": "string", "description": "Building element type"],
                            "orientation": ["type": ["string", "null"], "description": "Orientation of the element"],
                            "defectType": ["type": "string", "description": "Short defect label, e.g. 'crack'"],
                            "severity": ["type": "string", "description": "Severity level"]
                        ],
                        "required": ["storey", "elementType", "defectType", "severity"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "requestPhoto",
                    "description": "Ask the worker to take a photo for visual confirmation.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "reason": ["type": "string", "description": "Short reason for the photo request"]
                        ],
                        "required": ["reason"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "analyzePhoto",
                    "description": "Analyze a site photo of the reported defect.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "visibleDefectCount": ["type": "integer"],
                            "severityAssessment": ["type": "string"],
                            "safetyNotes": ["type": "string"]
                        ],
                        "required": ["visibleDefectCount", "severityAssessment", "safetyNotes"]
                    ]
                ]
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: tools),
              let s = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return s
    }()

    // MARK: - API

    func audioTurn(transcriptOriginal: String, languageHint: String?) async throws -> AudioTurnResult {
        let model = try await cactus.loadGemma()

        let langLine = languageHint.map { "Detected language: \($0).\n" } ?? ""
        let user = "\(langLine)Worker transcript: \"\(transcriptOriginal)\""

        let messages: [[String: Any]] = [
            ["role": "system", "content": Self.systemPromptAudio],
            ["role": "user", "content": user]
        ]

        let options: [String: Any] = [
            "max_tokens": 512,
            "temperature": 0.1,
            "auto_handoff": false
        ]

        let raw = try runComplete(model: model, messages: messages, options: options)
        let (response, functionCalls) = try Self.parseResponse(raw)

        var extraction: ExtractedDefect?
        var photoRequest: PhotoRequest?
        for call in functionCalls {
            switch call.name {
            case "extractDefect":
                extraction = try? call.decode(ExtractedDefect.self)
            case "requestPhoto":
                photoRequest = try? call.decode(PhotoRequest.self)
            default:
                break
            }
        }

        let english = response.isEmpty ? nil : response
        return AudioTurnResult(
            transcriptEnglish: english,
            extraction: extraction,
            photoRequest: photoRequest,
            raw: raw
        )
    }

    func visionTurn(photoPath: String, context: String) async throws -> VisionTurnResult {
        let model = try await cactus.loadGemma()

        let messages: [[String: Any]] = [
            ["role": "system", "content": Self.systemPromptVision],
            ["role": "user", "content": context, "images": [photoPath]]
        ]

        let options: [String: Any] = [
            "max_tokens": 512,
            "temperature": 0.1,
            "auto_handoff": false,
            "force_tools": true
        ]

        let raw = try runComplete(model: model, messages: messages, options: options)
        let (_, functionCalls) = try Self.parseResponse(raw)

        let analysis = functionCalls
            .first { $0.name == "analyzePhoto" }
            .flatMap { try? $0.decode(PhotoAnalysis.self) }

        return VisionTurnResult(analysis: analysis, raw: raw)
    }

    // MARK: - Internals

    private func runComplete(
        model: CactusModelT,
        messages: [[String: Any]],
        options: [String: Any]
    ) throws -> String {
        let messagesJson = try Self.jsonString(messages)
        let optionsJson = try Self.jsonString(options)
        do {
            return try cactusComplete(model, messagesJson, optionsJson, Self.toolsJson, nil, nil)
        } catch {
            throw GemmaServiceError.inferenceFailed(error.localizedDescription)
        }
    }

    private static func jsonString(_ any: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: any, options: [])
        guard let s = String(data: data, encoding: .utf8) else {
            throw GemmaServiceError.invalidResponse("non-utf8 JSON")
        }
        return s
    }

    // MARK: - Response parsing

    struct FunctionCall {
        let name: String
        let arguments: Any

        func decode<T: Decodable>(_ type: T.Type) throws -> T {
            let data: Data
            if let str = arguments as? String {
                data = Data(str.utf8)
            } else {
                data = try JSONSerialization.data(withJSONObject: arguments, options: [])
            }
            return try JSONDecoder().decode(T.self, from: data)
        }
    }

    private static func parseResponse(_ raw: String) throws -> (response: String, functionCalls: [FunctionCall]) {
        guard let data = raw.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw GemmaServiceError.invalidResponse("top-level JSON parse failed")
        }

        if let success = obj["success"] as? Bool, success == false {
            let err = (obj["error"] as? String) ?? "unknown"
            throw GemmaServiceError.inferenceFailed(err)
        }

        let response = (obj["response"] as? String) ?? ""
        let rawCalls = (obj["function_calls"] as? [[String: Any]]) ?? []
        let calls: [FunctionCall] = rawCalls.compactMap { call in
            guard let name = call["name"] as? String else { return nil }
            let args = call["arguments"] ?? [:]
            return FunctionCall(name: name, arguments: args)
        }
        return (response, calls)
    }
}
