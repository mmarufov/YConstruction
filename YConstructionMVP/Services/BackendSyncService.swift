import Foundation
import Network

enum ProjectBackendConfig {
    static let supabaseURL = URL(string: "https://ammmjwpvlqugolnufdbg.supabase.co")!
    static let publishableKey = "sb_publishable_Pp5gr7p2jxvRVJf5QBnLkw_5c4ctOTV"
    static let photosBucket = "photos"
    static let issuesBucket = "issues"
    static let projectsBucket = "projects"
    static let projectID = "duplex-demo-001"
    static let reporterID = "Worker 1"
    static let ifcFilename = "duplex.ifc"
}

struct DefectSyncDraft: Sendable {
    let transcriptOriginal: String
    let transcriptEnglish: String?
    let photoLocalURL: URL?
    let timestamp: Date
    let reporter: String
    let metadataOverride: DefectCapturedMetadata?

    init(
        transcriptOriginal: String,
        transcriptEnglish: String?,
        photoLocalURL: URL?,
        timestamp: Date,
        reporter: String,
        metadataOverride: DefectCapturedMetadata? = nil
    ) {
        self.transcriptOriginal = transcriptOriginal
        self.transcriptEnglish = transcriptEnglish
        self.photoLocalURL = photoLocalURL
        self.timestamp = timestamp
        self.reporter = reporter
        self.metadataOverride = metadataOverride
    }
}

struct DefectCapturedMetadata: Equatable, Sendable {
    let guid: String?
    let storey: String?
    let space: String?
    let elementType: String?
    let orientation: String?
    let defectType: String?
    let severity: String?
    let aiSafetyNotes: String?
}

struct DefectEnqueueResult: Equatable, Sendable {
    let recordID: String
    let wasUploaded: Bool
    let photoUploaded: Bool
    let photoURL: String?
}

struct CachedProjectChangeRecord: Equatable, Identifiable, Sendable {
    let id: String
    let projectID: String
    let guid: String
    let storey: String
    let space: String?
    let elementType: String
    let orientation: String?
    let defectType: String
    let severity: String
    let aiSafetyNotes: String?
    let reporter: String
    let timestamp: Date
    let transcriptOriginal: String?
    let transcriptEnglish: String?
    let photoURL: String?
    let bcfPath: String?
    let resolved: Bool
    let synced: Bool
    let updatedAt: Date?
}

private struct ExtractedDefectMetadata: Equatable, Sendable {
    let guid: String?
    let storey: String
    let space: String?
    let elementType: String
    let orientation: String?
    let defectType: String
    let severity: String
}

private struct ProjectChangePayload: Codable, Equatable, Sendable {
    let id: String
    let projectID: String
    let guid: String
    let storey: String
    let space: String?
    let elementType: String
    let orientation: String?
    let centroidX: Double
    let centroidY: Double
    let centroidZ: Double
    let bboxMinX: Double
    let bboxMinY: Double
    let bboxMinZ: Double
    let bboxMaxX: Double
    let bboxMaxY: Double
    let bboxMaxZ: Double
    let transcriptOriginal: String?
    let transcriptEnglish: String?
    let photoPath: String?
    let photoURL: String?
    let defectType: String
    let severity: String
    let aiSafetyNotes: String?
    let reporter: String
    let timestamp: Date
    let bcfPath: String
    let resolved: Bool
    let synced: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case guid
        case storey
        case space
        case elementType = "element_type"
        case orientation
        case centroidX = "centroid_x"
        case centroidY = "centroid_y"
        case centroidZ = "centroid_z"
        case bboxMinX = "bbox_min_x"
        case bboxMinY = "bbox_min_y"
        case bboxMinZ = "bbox_min_z"
        case bboxMaxX = "bbox_max_x"
        case bboxMaxY = "bbox_max_y"
        case bboxMaxZ = "bbox_max_z"
        case transcriptOriginal = "transcript_original"
        case transcriptEnglish = "transcript_english"
        case photoPath = "photo_path"
        case photoURL = "photo_url"
        case defectType = "defect_type"
        case severity
        case aiSafetyNotes = "ai_safety_notes"
        case reporter
        case timestamp
        case bcfPath = "bcf_path"
        case resolved
        case synced
    }
}

private struct ProjectChangeRemoteRecord: Codable, Equatable, Sendable {
    let id: String
    let projectID: String
    let guid: String
    let storey: String
    let space: String?
    let elementType: String
    let orientation: String?
    let centroidX: Double
    let centroidY: Double
    let centroidZ: Double
    let bboxMinX: Double
    let bboxMinY: Double
    let bboxMinZ: Double
    let bboxMaxX: Double
    let bboxMaxY: Double
    let bboxMaxZ: Double
    let transcriptOriginal: String?
    let transcriptEnglish: String?
    let photoPath: String?
    let photoURL: String?
    let defectType: String
    let severity: String
    let aiSafetyNotes: String?
    let reporter: String
    let timestamp: Date
    let bcfPath: String?
    let resolved: Bool
    let synced: Bool
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case guid
        case storey
        case space
        case elementType = "element_type"
        case orientation
        case centroidX = "centroid_x"
        case centroidY = "centroid_y"
        case centroidZ = "centroid_z"
        case bboxMinX = "bbox_min_x"
        case bboxMinY = "bbox_min_y"
        case bboxMinZ = "bbox_min_z"
        case bboxMaxX = "bbox_max_x"
        case bboxMaxY = "bbox_max_y"
        case bboxMaxZ = "bbox_max_z"
        case transcriptOriginal = "transcript_original"
        case transcriptEnglish = "transcript_english"
        case photoPath = "photo_path"
        case photoURL = "photo_url"
        case defectType = "defect_type"
        case severity
        case aiSafetyNotes = "ai_safety_notes"
        case reporter
        case timestamp
        case bcfPath = "bcf_path"
        case resolved
        case synced
        case updatedAt = "updated_at"
    }
}

private struct SyncedDefectRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let projectID: String
    var guid: String
    var storey: String
    var space: String?
    var elementType: String
    var orientation: String?
    var centroidX: Double
    var centroidY: Double
    var centroidZ: Double
    var bboxMinX: Double
    var bboxMinY: Double
    var bboxMinZ: Double
    var bboxMaxX: Double
    var bboxMaxY: Double
    var bboxMaxZ: Double
    var defectType: String
    var severity: String
    var aiSafetyNotes: String?
    var reporter: String
    var timestamp: Date
    var transcriptOriginal: String?
    var transcriptEnglish: String?
    var photoLocalPath: String?
    var photoPublicURL: String?
    var photoRemoteBucket: String?
    var photoRemotePath: String?
    var bcfLocalPath: String?
    var bcfRemotePath: String
    var resolved: Bool
    var synced: Bool
    var updatedAt: Date?

    init(
        id: String,
        projectID: String,
        guid: String,
        storey: String,
        space: String?,
        elementType: String,
        orientation: String?,
        centroidX: Double,
        centroidY: Double,
        centroidZ: Double,
        bboxMinX: Double,
        bboxMinY: Double,
        bboxMinZ: Double,
        bboxMaxX: Double,
        bboxMaxY: Double,
        bboxMaxZ: Double,
        defectType: String,
        severity: String,
        aiSafetyNotes: String?,
        reporter: String,
        timestamp: Date,
        transcriptOriginal: String?,
        transcriptEnglish: String?,
        photoLocalPath: String?,
        photoPublicURL: String?,
        photoRemoteBucket: String?,
        photoRemotePath: String?,
        bcfLocalPath: String?,
        bcfRemotePath: String,
        resolved: Bool,
        synced: Bool,
        updatedAt: Date?
    ) {
        self.id = id
        self.projectID = projectID
        self.guid = guid
        self.storey = storey
        self.space = space
        self.elementType = elementType
        self.orientation = orientation
        self.centroidX = centroidX
        self.centroidY = centroidY
        self.centroidZ = centroidZ
        self.bboxMinX = bboxMinX
        self.bboxMinY = bboxMinY
        self.bboxMinZ = bboxMinZ
        self.bboxMaxX = bboxMaxX
        self.bboxMaxY = bboxMaxY
        self.bboxMaxZ = bboxMaxZ
        self.defectType = defectType
        self.severity = severity
        self.aiSafetyNotes = aiSafetyNotes
        self.reporter = reporter
        self.timestamp = timestamp
        self.transcriptOriginal = transcriptOriginal
        self.transcriptEnglish = transcriptEnglish
        self.photoLocalPath = photoLocalPath
        self.photoPublicURL = photoPublicURL
        self.photoRemoteBucket = photoRemoteBucket
        self.photoRemotePath = photoRemotePath
        self.bcfLocalPath = bcfLocalPath
        self.bcfRemotePath = bcfRemotePath
        self.resolved = resolved
        self.synced = synced
        self.updatedAt = updatedAt
    }

    init(remoteRecord: ProjectChangeRemoteRecord) {
        self.init(
            id: remoteRecord.id,
            projectID: remoteRecord.projectID,
            guid: remoteRecord.guid,
            storey: remoteRecord.storey,
            space: remoteRecord.space,
            elementType: remoteRecord.elementType,
            orientation: remoteRecord.orientation,
            centroidX: remoteRecord.centroidX,
            centroidY: remoteRecord.centroidY,
            centroidZ: remoteRecord.centroidZ,
            bboxMinX: remoteRecord.bboxMinX,
            bboxMinY: remoteRecord.bboxMinY,
            bboxMinZ: remoteRecord.bboxMinZ,
            bboxMaxX: remoteRecord.bboxMaxX,
            bboxMaxY: remoteRecord.bboxMaxY,
            bboxMaxZ: remoteRecord.bboxMaxZ,
            defectType: remoteRecord.defectType,
            severity: remoteRecord.severity,
            aiSafetyNotes: remoteRecord.aiSafetyNotes,
            reporter: remoteRecord.reporter,
            timestamp: remoteRecord.timestamp,
            transcriptOriginal: remoteRecord.transcriptOriginal,
            transcriptEnglish: remoteRecord.transcriptEnglish,
            photoLocalPath: remoteRecord.photoPath,
            photoPublicURL: remoteRecord.photoURL,
            photoRemoteBucket: nil,
            photoRemotePath: remoteRecord.photoPath,
            bcfLocalPath: nil,
            bcfRemotePath: remoteRecord.bcfPath ?? "\(remoteRecord.projectID)/\(remoteRecord.id).bcfzip",
            resolved: remoteRecord.resolved,
            synced: true,
            updatedAt: remoteRecord.updatedAt
        )
    }

    func payload(photoRemotePath: String?, photoPublicURL: String?) -> ProjectChangePayload {
        ProjectChangePayload(
            id: id,
            projectID: projectID,
            guid: guid,
            storey: storey,
            space: space,
            elementType: elementType,
            orientation: orientation,
            centroidX: centroidX,
            centroidY: centroidY,
            centroidZ: centroidZ,
            bboxMinX: bboxMinX,
            bboxMinY: bboxMinY,
            bboxMinZ: bboxMinZ,
            bboxMaxX: bboxMaxX,
            bboxMaxY: bboxMaxY,
            bboxMaxZ: bboxMaxZ,
            transcriptOriginal: transcriptOriginal,
            transcriptEnglish: transcriptEnglish,
            photoPath: Self.storagePathDescriptor(bucket: photoRemoteBucket, remotePath: photoRemotePath),
            photoURL: photoPublicURL,
            defectType: defectType,
            severity: severity,
            aiSafetyNotes: aiSafetyNotes,
            reporter: reporter,
            timestamp: timestamp,
            bcfPath: bcfRemotePath,
            resolved: resolved,
            synced: false
        )
    }

    mutating func apply(remoteRecord: ProjectChangeRemoteRecord) {
        guid = remoteRecord.guid
        storey = remoteRecord.storey
        space = remoteRecord.space
        elementType = remoteRecord.elementType
        orientation = remoteRecord.orientation
        centroidX = remoteRecord.centroidX
        centroidY = remoteRecord.centroidY
        centroidZ = remoteRecord.centroidZ
        bboxMinX = remoteRecord.bboxMinX
        bboxMinY = remoteRecord.bboxMinY
        bboxMinZ = remoteRecord.bboxMinZ
        bboxMaxX = remoteRecord.bboxMaxX
        bboxMaxY = remoteRecord.bboxMaxY
        bboxMaxZ = remoteRecord.bboxMaxZ
        defectType = remoteRecord.defectType
        severity = remoteRecord.severity
        aiSafetyNotes = remoteRecord.aiSafetyNotes
        reporter = remoteRecord.reporter
        timestamp = remoteRecord.timestamp
        transcriptOriginal = remoteRecord.transcriptOriginal
        transcriptEnglish = remoteRecord.transcriptEnglish
        photoLocalPath = remoteRecord.photoPath
        photoPublicURL = remoteRecord.photoURL
        photoRemoteBucket = nil
        photoRemotePath = remoteRecord.photoPath
        if let bcfPath = remoteRecord.bcfPath {
            bcfRemotePath = bcfPath
        }
        resolved = remoteRecord.resolved
        synced = true
        updatedAt = remoteRecord.updatedAt
    }

    func asCachedProjectChangeRecord() -> CachedProjectChangeRecord {
        CachedProjectChangeRecord(
            id: id,
            projectID: projectID,
            guid: guid,
            storey: storey,
            space: space,
            elementType: elementType,
            orientation: orientation,
            defectType: defectType,
            severity: severity,
            aiSafetyNotes: aiSafetyNotes,
            reporter: reporter,
            timestamp: timestamp,
            transcriptOriginal: transcriptOriginal,
            transcriptEnglish: transcriptEnglish,
            photoURL: photoPublicURL,
            bcfPath: bcfRemotePath,
            resolved: resolved,
            synced: synced,
            updatedAt: updatedAt
        )
    }

    private static func storagePathDescriptor(bucket: String?, remotePath: String?) -> String? {
        guard let remotePath else { return nil }
        guard let bucket, !bucket.isEmpty else { return remotePath }
        if bucket == ProjectBackendConfig.photosBucket {
            return remotePath
        }
        return "\(bucket)/\(remotePath)"
    }
}

private struct DefectSyncSnapshot: Sendable {
    let records: [SyncedDefectRecord]

    var pendingCount: Int {
        records.filter { !$0.synced }.count
    }
}

private enum DefectMetadataExtractor {
    static func extract(from transcript: String) -> ExtractedDefectMetadata {
        let lowercased = transcript.lowercased()

        return ExtractedDefectMetadata(
            guid: nil,
            storey: storey(from: lowercased),
            space: spaceCode(from: transcript),
            elementType: elementType(from: lowercased),
            orientation: orientation(from: lowercased),
            defectType: defectType(from: lowercased),
            severity: severity(from: lowercased)
        )
    }

    private static func storey(from text: String) -> String {
        if containsAny(text, ["roof", "rooftop", "azotea"]) {
            return "Roof"
        }
        if containsAny(text, ["second floor", "2nd floor", "level 2", "second level", "upstairs", "segundo piso", "segundo nivel"]) {
            return "Level 2"
        }
        if containsAny(text, ["basement", "foundation", "fundacion", "fundación", "t/fdn"]) {
            return "T/FDN"
        }
        return "Level 1"
    }

    private static func elementType(from text: String) -> String {
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

        for (candidate, patterns) in orderedMatches where containsAny(text, patterns) {
            return candidate
        }

        return "wall"
    }

    private static func orientation(from text: String) -> String? {
        if containsAny(text, ["north", "norte"]) {
            return "north"
        }
        if containsAny(text, ["south", "sur"]) {
            return "south"
        }
        if containsAny(text, ["east", "este"]) {
            return "east"
        }
        if containsAny(text, ["west", "oeste"]) {
            return "west"
        }
        return nil
    }

    private static func defectType(from text: String) -> String {
        let orderedMatches: [(String, [String])] = [
            ("water damage", ["water damage", "water stain", "leak", "leaking", "moisture", "humidity", "wet", "damp", "fuga", "humedad"]),
            ("crack", ["crack", "cracked", "fracture", "grieta"]),
            ("hole", ["hole", "puncture", "opening", "hueco", "agujero"]),
            ("broken glass", ["broken glass", "shattered", "pane", "glass", "vidrio"]),
            ("alignment issue", ["doesn't close", "does not close", "misaligned", "alignment", "crooked", "sticking", "not flush"]),
            ("mold", ["mold", "mildew", "moho"]),
            ("rust", ["rust", "corrosion", "oxidation", "corrosion"]),
            ("peeling paint", ["peeling", "paint", "painted", "descascarada"]),
            ("stain", ["stain", "staining", "mark", "spot", "mancha"]),
            ("broken fixture", ["broken", "damaged", "loose", "detached", "unsafe"])
        ]

        for (candidate, patterns) in orderedMatches where containsAny(text, patterns) {
            return candidate
        }

        return "field note"
    }

    private static func severity(from text: String) -> String {
        if containsAny(text, ["collapse", "fire", "smoke", "gas leak", "exposed wire", "electrical hazard", "immediate danger"]) {
            return "critical"
        }
        if containsAny(text, ["structural", "large crack", "broken glass", "unsafe", "hazard", "major leak", "flooding"]) {
            return "high"
        }
        if containsAny(text, ["crack", "leak", "water damage", "water", "mold", "hole", "broken", "rust", "stain"]) {
            return "medium"
        }
        return "low"
    }

    private static func spaceCode(from text: String) -> String? {
        let pattern = #"\b([A-Za-z]\d{3})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let nsrange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsrange),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return text[range].uppercased()
    }

    private static func containsAny(_ text: String, _ candidates: [String]) -> Bool {
        candidates.contains(where: { text.contains($0) })
    }
}

private enum BackendDateCoder {
    static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let standardFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func string(from date: Date) -> String {
        fractionalFormatter.string(from: date)
    }

    static func parse(_ text: String) -> Date? {
        fractionalFormatter.date(from: text) ?? standardFormatter.date(from: text)
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(string(from: date))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = parse(raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported date format: \(raw)")
        }
        return decoder
    }
}

private actor DefectSyncStore {
    private let fileManager = FileManager.default

    func snapshot() throws -> DefectSyncSnapshot {
        DefectSyncSnapshot(records: try loadRecords())
    }

    func persistPhotoCopy(from sourceURL: URL) throws -> URL {
        let directories = try ensureDirectories()
        let ext = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension
        let destinationURL = directories.photos.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    func bcfOutputURL(for topicID: String) throws -> URL {
        let directories = try ensureDirectories()
        return directories.issues.appendingPathComponent(topicID).appendingPathExtension("bcfzip")
    }

    func upsert(_ record: SyncedDefectRecord) throws {
        var records = try loadRecords()
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
        }
        try saveRecords(records)
    }

    func pendingRecords() throws -> [SyncedDefectRecord] {
        try loadRecords()
            .filter { !$0.synced }
            .sorted { $0.timestamp < $1.timestamp }
    }

    func record(id: String) throws -> SyncedDefectRecord? {
        try loadRecords().first(where: { $0.id == id })
    }

    func cachedRecordsForRetrieval() throws -> [CachedProjectChangeRecord] {
        try loadRecords()
            .filter(\.synced)
            .sorted { lhs, rhs in
                (lhs.updatedAt ?? lhs.timestamp) > (rhs.updatedAt ?? rhs.timestamp)
            }
            .map { $0.asCachedProjectChangeRecord() }
    }

    func markSynced(
        id: String,
        photoPublicURL: String?,
        photoRemoteBucket: String?,
        photoRemotePath: String?,
        updatedAt: Date?
    ) throws {
        var records = try loadRecords()
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            return
        }

        records[index].synced = true
        records[index].updatedAt = updatedAt
        if let photoPublicURL {
            records[index].photoPublicURL = photoPublicURL
        }
        if let photoRemoteBucket {
            records[index].photoRemoteBucket = photoRemoteBucket
        }
        if let photoRemotePath {
            records[index].photoRemotePath = photoRemotePath
        }
        try saveRecords(records)
    }

    func mergeRemote(_ remoteRecords: [ProjectChangeRemoteRecord]) throws -> Int {
        var records = try loadRecords()
        var mergedCount = 0

        for remoteRecord in remoteRecords {
            if let index = records.firstIndex(where: { $0.id == remoteRecord.id }) {
                let before = records[index]
                records[index].apply(remoteRecord: remoteRecord)
                if records[index] != before {
                    mergedCount += 1
                }
            } else {
                records.append(SyncedDefectRecord(remoteRecord: remoteRecord))
                mergedCount += 1
            }
        }

        try saveRecords(records)
        return mergedCount
    }

    private func loadRecords() throws -> [SyncedDefectRecord] {
        let queueURL = try queueFileURL()
        guard fileManager.fileExists(atPath: queueURL.path) else {
            return []
        }

        let data = try Data(contentsOf: queueURL)
        return try BackendDateCoder.makeDecoder().decode([SyncedDefectRecord].self, from: data)
    }

    private func saveRecords(_ records: [SyncedDefectRecord]) throws {
        let queueURL = try queueFileURL()
        let data = try BackendDateCoder.makeEncoder().encode(records.sorted { $0.timestamp > $1.timestamp })
        try data.write(to: queueURL, options: .atomic)
    }

    private func queueFileURL() throws -> URL {
        try ensureDirectories().root.appendingPathComponent("queue.json")
    }

    private func ensureDirectories() throws -> (root: URL, photos: URL, issues: URL) {
        guard let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "YConstructionMVP"
        let root = applicationSupport
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("BackendSync", isDirectory: true)
        let photos = root.appendingPathComponent("Photos", isDirectory: true)
        let issues = root.appendingPathComponent("Issues", isDirectory: true)

        try fileManager.createDirectory(at: photos, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: issues, withIntermediateDirectories: true)
        return (root, photos, issues)
    }
}

private enum SupabaseRESTError: LocalizedError {
    case requestFailed(String)
    case unexpectedStatus(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .requestFailed(let message):
            return message
        case .unexpectedStatus(let code, let message):
            return "Supabase returned HTTP \(code). \(message)"
        case .invalidResponse:
            return "Supabase returned an unreadable response."
        }
    }
}

private struct SupabaseRESTClient {
    let baseURL: URL
    let apiKey: String

    private let fieldSelection = "id,project_id,guid,storey,space,element_type,orientation,centroid_x,centroid_y,centroid_z,bbox_min_x,bbox_min_y,bbox_min_z,bbox_max_x,bbox_max_y,bbox_max_z,transcript_original,transcript_english,photo_path,photo_url,defect_type,severity,ai_safety_notes,reporter,timestamp,bcf_path,resolved,synced,updated_at"

    func verifyProjectChangesContract() async throws {
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/project_changes"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "select", value: fieldSelection),
            URLQueryItem(name: "limit", value: "1")
        ]

        guard let url = components?.url else {
            throw SupabaseRESTError.invalidResponse
        }

        let request = makeRESTRequest(url: url, method: "GET")
        _ = try await perform(request)
    }

    func verifyBucketExists(named bucket: String) async throws {
        let url = baseURL.appendingPathComponent("/storage/v1/object/list/\(bucket)")
        let body = Data(#"{"prefix":"","limit":1,"offset":0}"#.utf8)
        var request = makeStorageRequest(url: url, method: "POST")
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await perform(request)
    }

    func uploadObject(
        data: Data,
        bucket: String,
        remotePath: String,
        contentType: String,
        upsert: Bool = true
    ) async throws {
        let encodedPath = encodePath(remotePath)
        let url = baseURL.appendingPathComponent("/storage/v1/object/\(bucket)/\(encodedPath)")
        var request = makeStorageRequest(url: url, method: "POST")
        request.httpBody = data
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if upsert {
            request.setValue("true", forHTTPHeaderField: "x-upsert")
        }
        _ = try await perform(request)
    }

    func createSignedObjectURL(bucket: String, remotePath: String, expiresIn: Int) async throws -> URL {
        struct SignedObjectResponse: Decodable {
            let signedURL: String

            enum CodingKeys: String, CodingKey {
                case signedURL = "signedURL"
            }
        }

        let encodedPath = encodePath(remotePath)
        let url = baseURL.appendingPathComponent("/storage/v1/object/sign/\(bucket)/\(encodedPath)")
        var request = makeStorageRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["expiresIn": expiresIn])

        let data = try await perform(request)
        let response = try JSONDecoder().decode(SignedObjectResponse.self, from: data)
        guard let absoluteURL = URL(string: "/storage/v1\(response.signedURL)", relativeTo: baseURL)?.absoluteURL else {
            throw SupabaseRESTError.invalidResponse
        }
        return absoluteURL
    }

    func upsertProjectChange(_ payload: ProjectChangePayload) async throws -> ProjectChangeRemoteRecord? {
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/project_changes"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "on_conflict", value: "id")
        ]

        guard let url = components?.url else {
            throw SupabaseRESTError.invalidResponse
        }

        var request = makeRESTRequest(url: url, method: "POST")
        request.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try BackendDateCoder.makeEncoder().encode([payload])

        let data = try await perform(request)
        let rows = try BackendDateCoder.makeDecoder().decode([ProjectChangeRemoteRecord].self, from: data)
        return rows.first
    }

    func fetchRemoteChanges(projectID: String, updatedAfter: Date?) async throws -> [ProjectChangeRemoteRecord] {
        var queryItems = [
            URLQueryItem(name: "select", value: fieldSelection),
            URLQueryItem(name: "project_id", value: "eq.\(projectID)"),
            URLQueryItem(name: "order", value: "updated_at.desc")
        ]

        if let updatedAfter {
            queryItems.append(URLQueryItem(name: "updated_at", value: "gt.\(BackendDateCoder.string(from: updatedAfter))"))
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/project_changes"), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw SupabaseRESTError.invalidResponse
        }

        let request = makeRESTRequest(url: url, method: "GET")
        let data = try await perform(request)
        return try BackendDateCoder.makeDecoder().decode([ProjectChangeRemoteRecord].self, from: data)
    }

    func publicObjectURL(bucket: String, remotePath: String) -> URL {
        baseURL.appendingPathComponent("/storage/v1/object/public/\(bucket)/\(encodePath(remotePath))")
    }

    private func makeRESTRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("public", forHTTPHeaderField: "Accept-Profile")
        request.setValue("public", forHTTPHeaderField: "Content-Profile")
        return request
    }

    private func makeStorageRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SupabaseRESTError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "No response body."
                throw SupabaseRESTError.unexpectedStatus(httpResponse.statusCode, message)
            }

            return data
        } catch let error as SupabaseRESTError {
            throw error
        } catch {
            throw SupabaseRESTError.requestFailed(error.localizedDescription)
        }
    }

    private func encodePath(_ path: String) -> String {
        path
            .split(separator: "/")
            .map { segment in
                String(segment).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(segment)
            }
            .joined(separator: "/")
    }
}

private struct SupabaseContractVerifier {
    let client: SupabaseRESTClient

    func verify() async throws {
        try await client.verifyProjectChangesContract()
        try await client.verifyBucketExists(named: ProjectBackendConfig.photosBucket)
        try await client.verifyBucketExists(named: ProjectBackendConfig.issuesBucket)
        try await client.verifyBucketExists(named: ProjectBackendConfig.projectsBucket)
    }
}

@MainActor
final class DefectSyncService: ObservableObject {
    @Published private(set) var backendStatusText = "Checking Supabase contract..."
    @Published private(set) var syncStatusText = "No queued captures yet."
    @Published private(set) var pendingCount = 0
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var isOnline = false
    @Published private(set) var isPreferredSyncNetwork = false
    @Published private(set) var lastError: String?
    @Published private(set) var isBackendReady = false

    private static let lastSyncedKey = "YConstructionMVP.backend.lastSyncedAt"

    private let store: DefectSyncStore
    private let client: SupabaseRESTClient
    private let verifier: SupabaseContractVerifier
    private let emitter: BCFEmitterService
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "YConstructionMVP.backend.network")

    private var didStart = false
    private var periodicSyncTask: Task<Void, Never>?
    private var isSyncing = false
    private var lastVerifiedAt: Date?

    init() {
        let store = DefectSyncStore()
        let client = SupabaseRESTClient(
            baseURL: ProjectBackendConfig.supabaseURL,
            apiKey: ProjectBackendConfig.publishableKey
        )
        let emitter = BCFEmitterService()

        self.store = store
        self.client = client
        self.verifier = SupabaseContractVerifier(client: client)
        self.emitter = emitter
        self.lastSyncedAt = UserDefaults.standard.object(forKey: Self.lastSyncedKey) as? Date
    }

    deinit {
        monitor.cancel()
        periodicSyncTask?.cancel()
    }

    func prepare() async {
        await refreshSnapshot()
        _ = await verifyBackend(force: false)
        startMonitoringIfNeeded()
    }

    func persistCapturedPhoto(from sourceURL: URL) async throws -> URL {
        try await store.persistPhotoCopy(from: sourceURL)
    }

    func cachedProjectChangesForRetrieval() async -> [CachedProjectChangeRecord] {
        do {
            return try await store.cachedRecordsForRetrieval()
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    func enqueue(draft: DefectSyncDraft) async throws -> DefectEnqueueResult {
        do {
            let metadata = resolvedMetadata(for: draft)
            let record = try await makeQueuedRecord(from: draft, metadata: metadata)
            try await store.upsert(record)
            await refreshSnapshot()
            syncStatusText = pendingCount == 1
                ? "1 capture queued for Supabase/Bonsai."
                : "\(pendingCount) captures queued for Supabase/Bonsai."

            var latestRecord = record
            if isPreferredSyncNetwork {
                await syncNow(manualOverride: false)
                if let syncedRecord = try await store.record(id: record.id) {
                    latestRecord = syncedRecord
                }
            }

            return DefectEnqueueResult(
                recordID: latestRecord.id,
                wasUploaded: latestRecord.synced,
                photoUploaded: latestRecord.photoPublicURL != nil,
                photoURL: latestRecord.photoPublicURL
            )
        } catch {
            lastError = error.localizedDescription
            syncStatusText = "Capture saved locally, but the backend bundle could not be prepared."
            throw error
        }
    }

    func syncNow(manualOverride: Bool = true) async {
        guard !isSyncing else { return }

        guard isOnline else {
            syncStatusText = "Offline. The queue stays on this iPhone until you reconnect."
            return
        }

        guard await verifyBackend(force: manualOverride) else {
            return
        }

        isSyncing = true
        syncStatusText = manualOverride ? "Syncing queued captures now..." : "Auto-syncing over Wi-Fi..."
        lastError = nil

        defer {
            isSyncing = false
        }

        do {
            let pendingRecords = try await store.pendingRecords()
            if pendingRecords.isEmpty {
                await catchUpRemoteChanges()
                syncStatusText = "All synced. Nothing is waiting in the queue."
                return
            }

            for record in pendingRecords {
                try await upload(record: record)
            }

            let now = Date()
            lastSyncedAt = now
            UserDefaults.standard.set(now, forKey: Self.lastSyncedKey)
            await catchUpRemoteChanges()
            await refreshSnapshot()
            syncStatusText = pendingCount == 0
                ? "All queued captures reached Supabase."
                : "\(pendingCount) captures are still waiting to sync."
        } catch {
            lastError = error.localizedDescription
            await refreshSnapshot()
            syncStatusText = "Sync stopped before the queue finished."
        }
    }

    private func startMonitoringIfNeeded() {
        guard !didStart else { return }
        didStart = true

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isOnline = path.status == .satisfied
                self.isPreferredSyncNetwork = path.usesInterfaceType(.wifi)

                if self.isOnline {
                    let networkText = self.isPreferredSyncNetwork ? "Wi-Fi available for auto-sync." : "Online. Auto-sync waits for Wi-Fi."
                    self.syncStatusText = self.pendingCount > 0 ? networkText : "Online and ready to sync."
                    if self.isPreferredSyncNetwork {
                        await self.syncNow(manualOverride: false)
                    } else {
                        await self.catchUpRemoteChanges()
                    }
                } else {
                    self.syncStatusText = self.pendingCount > 0
                        ? "\(self.pendingCount) captures are queued locally while offline."
                        : "Offline. New captures will stay on this iPhone until you reconnect."
                }
            }
        }

        monitor.start(queue: monitorQueue)

        periodicSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                await MainActor.run {
                    guard let self, self.isPreferredSyncNetwork else { return }
                    Task {
                        await self.syncNow(manualOverride: false)
                    }
                }
            }
        }
    }

    private func verifyBackend(force: Bool) async -> Bool {
        if !force, let lastVerifiedAt, Date().timeIntervalSince(lastVerifiedAt) < 300, isBackendReady {
            return true
        }

        backendStatusText = "Verifying Supabase table and storage buckets..."
        do {
            try await verifier.verify()
            isBackendReady = true
            lastVerifiedAt = Date()
            lastError = nil
            backendStatusText = "Supabase and Bonsai contract verified."
            return true
        } catch {
            isBackendReady = false
            lastError = error.localizedDescription
            backendStatusText = "Supabase contract verification failed."
            return false
        }
    }

    private func refreshSnapshot() async {
        do {
            let snapshot = try await store.snapshot()
            pendingCount = snapshot.pendingCount
            if pendingCount == 0 && !isSyncing && lastError == nil {
                syncStatusText = isOnline ? "All synced." : "No queued captures yet."
            }
        } catch {
            pendingCount = 0
            lastError = error.localizedDescription
        }
    }

    private struct UploadedPhotoReference {
        let bucket: String
        let remotePath: String
        let accessURL: String
    }

    private struct PhotoStorageDestination: Equatable {
        let bucket: String
        let remotePath: String
    }

    private func upload(record: SyncedDefectRecord) async throws {
        let uploadedPhoto = try await uploadPhoto(for: record)

        if let bcfLocalPath = record.bcfLocalPath,
           FileManager.default.fileExists(atPath: bcfLocalPath) {
            let bcfURL = URL(fileURLWithPath: bcfLocalPath)
            let bcfData = try Data(contentsOf: bcfURL)
            try await client.uploadObject(
                data: bcfData,
                bucket: ProjectBackendConfig.issuesBucket,
                remotePath: record.bcfRemotePath,
                contentType: "application/zip",
                upsert: true
            )
        }

        let effectivePhotoBucket = uploadedPhoto?.bucket ?? record.photoRemoteBucket
        let effectivePhotoRemotePath = uploadedPhoto?.remotePath ?? record.photoRemotePath
        let effectivePhotoURL = uploadedPhoto?.accessURL ?? record.photoPublicURL

        let remoteRecord = try await client.upsertProjectChange(
            record.payload(
                photoRemotePath: effectivePhotoRemotePath,
                photoPublicURL: effectivePhotoURL
            )
        )

        try await store.markSynced(
            id: record.id,
            photoPublicURL: effectivePhotoURL,
            photoRemoteBucket: effectivePhotoBucket,
            photoRemotePath: effectivePhotoRemotePath,
            updatedAt: remoteRecord?.updatedAt
        )
    }

    private func uploadPhoto(for record: SyncedDefectRecord) async throws -> UploadedPhotoReference? {
        guard let photoLocalPath = record.photoLocalPath,
              FileManager.default.fileExists(atPath: photoLocalPath) else {
            return nil
        }

        let photoURL = URL(fileURLWithPath: photoLocalPath)
        let photoData = try Data(contentsOf: photoURL)
        let primaryBucket = record.photoRemoteBucket ?? ProjectBackendConfig.photosBucket
        let primaryPath = record.photoRemotePath ?? "\(ProjectBackendConfig.projectID)/\(photoURL.lastPathComponent)"
        let fallbackPath = "\(ProjectBackendConfig.projectID)/photos/\(photoURL.lastPathComponent)"

        let destinations = [
            PhotoStorageDestination(bucket: primaryBucket, remotePath: primaryPath),
            PhotoStorageDestination(bucket: ProjectBackendConfig.issuesBucket, remotePath: fallbackPath)
        ].reduce(into: [PhotoStorageDestination]()) { unique, destination in
            if !unique.contains(destination) {
                unique.append(destination)
            }
        }

        var lastUploadError: Error?

        for destination in destinations {
            do {
                try await client.uploadObject(
                    data: photoData,
                    bucket: destination.bucket,
                    remotePath: destination.remotePath,
                    contentType: "image/jpeg",
                    upsert: destination.bucket != ProjectBackendConfig.photosBucket
                )
                let accessURL = try await resolvePhotoAccessURL(
                    bucket: destination.bucket,
                    remotePath: destination.remotePath
                )
                return UploadedPhotoReference(
                    bucket: destination.bucket,
                    remotePath: destination.remotePath,
                    accessURL: accessURL.absoluteString
                )
            } catch SupabaseRESTError.unexpectedStatus(let code, _) where destination.bucket == ProjectBackendConfig.photosBucket && code == 409 {
                let accessURL = try await resolvePhotoAccessURL(
                    bucket: destination.bucket,
                    remotePath: destination.remotePath
                )
                return UploadedPhotoReference(
                    bucket: destination.bucket,
                    remotePath: destination.remotePath,
                    accessURL: accessURL.absoluteString
                )
            } catch {
                lastUploadError = error
                print("Photo upload failed for \(record.id) into \(destination.bucket): \(error.localizedDescription)")
            }
        }

        throw lastUploadError ?? SupabaseRESTError.invalidResponse
    }

    private func resolvePhotoAccessURL(bucket: String, remotePath: String) async throws -> URL {
        do {
            return try await client.createSignedObjectURL(
                bucket: bucket,
                remotePath: remotePath,
                expiresIn: 31_536_000
            )
        } catch {
            if bucket == ProjectBackendConfig.photosBucket {
                return client.publicObjectURL(bucket: bucket, remotePath: remotePath)
            }
            throw error
        }
    }

    private func catchUpRemoteChanges() async {
        guard isOnline else { return }
        guard await verifyBackend(force: false) else { return }

        do {
            let remoteRows = try await client.fetchRemoteChanges(
                projectID: ProjectBackendConfig.projectID,
                updatedAfter: lastSyncedAt
            )

            let mergedCount = try await store.mergeRemote(remoteRows)
            if let mostRecent = remoteRows.compactMap(\.updatedAt).max() {
                lastSyncedAt = max(lastSyncedAt ?? .distantPast, mostRecent)
                UserDefaults.standard.set(lastSyncedAt, forKey: Self.lastSyncedKey)
            }

            if mergedCount > 0 {
                syncStatusText = "Fetched \(mergedCount) remote update(s) from Supabase."
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func makeQueuedRecord(from draft: DefectSyncDraft, metadata: ExtractedDefectMetadata) async throws -> SyncedDefectRecord {
        let topicID = UUID().uuidString.lowercased()
        let photoRemotePath = draft.photoLocalURL.map { "\(ProjectBackendConfig.projectID)/\($0.lastPathComponent)" }
        let bcfRemotePath = "\(ProjectBackendConfig.projectID)/\(topicID).bcfzip"
        let bcfOutputURL = try await store.bcfOutputURL(for: topicID)

        let photoData = draft.photoLocalURL.flatMap { try? Data(contentsOf: $0) }
        let snapshotFilename = draft.photoLocalURL.map { sourceURL in
            let ext = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension.lowercased()
            return "snapshot.\(ext)"
        }
        let title = "\(metadata.defectType) - \(metadata.elementType)"
        let description = makeBCFDescription(
            transcriptOriginal: draft.transcriptOriginal,
            transcriptEnglish: draft.transcriptEnglish,
            metadata: metadata
        )

        let bcfInput = BCFInput(
            topicGuid: topicID,
            ifcGuid: nil,
            ifcFilename: ProjectBackendConfig.ifcFilename,
            title: title,
            description: description,
            topicType: "Defect",
            topicStatus: "Open",
            priority: priority(for: metadata.severity),
            author: draft.reporter,
            creationDate: draft.timestamp,
            cameraViewPoint: (0, 0, 2),
            cameraDirection: (0, 0, -1),
            cameraUpVector: (0, 1, 0),
            fieldOfView: 60,
            snapshotPNG: photoData,
            snapshotFilename: snapshotFilename
        )
        _ = try emitter.emit(bcfInput, to: bcfOutputURL)

        return SyncedDefectRecord(
            id: topicID,
            projectID: ProjectBackendConfig.projectID,
            guid: metadata.guid ?? "",
            storey: metadata.storey,
            space: metadata.space,
            elementType: metadata.elementType,
            orientation: metadata.orientation,
            centroidX: 0,
            centroidY: 0,
            centroidZ: 0,
            bboxMinX: 0,
            bboxMinY: 0,
            bboxMinZ: 0,
            bboxMaxX: 0,
            bboxMaxY: 0,
            bboxMaxZ: 0,
            defectType: metadata.defectType,
            severity: metadata.severity,
            aiSafetyNotes: normalizedValue(draft.metadataOverride?.aiSafetyNotes) ?? "Captured on iPhone. IFC alignment is still pending on the backend.",
            reporter: draft.reporter,
            timestamp: draft.timestamp,
            transcriptOriginal: draft.transcriptOriginal,
            transcriptEnglish: draft.transcriptEnglish,
            photoLocalPath: draft.photoLocalURL?.path,
            photoPublicURL: nil,
            photoRemoteBucket: draft.photoLocalURL == nil ? nil : ProjectBackendConfig.photosBucket,
            photoRemotePath: photoRemotePath,
            bcfLocalPath: bcfOutputURL.path,
            bcfRemotePath: bcfRemotePath,
            resolved: false,
            synced: false,
            updatedAt: nil
        )
    }

    private func resolvedMetadata(for draft: DefectSyncDraft) -> ExtractedDefectMetadata {
        let extracted = DefectMetadataExtractor.extract(from: draft.transcriptOriginal)
        let override = draft.metadataOverride

        return ExtractedDefectMetadata(
            guid: normalizedValue(override?.guid),
            storey: normalizedValue(override?.storey) ?? extracted.storey,
            space: normalizedValue(override?.space),
            elementType: normalizedElementType(override?.elementType) ?? extracted.elementType,
            orientation: normalizedValue(override?.orientation) ?? extracted.orientation,
            defectType: normalizedDefectType(override?.defectType) ?? extracted.defectType,
            severity: normalizedSeverity(override?.severity) ?? extracted.severity
        )
    }

    private func normalizedValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedElementType(_ value: String?) -> String? {
        guard let normalized = normalizedValue(value) else { return nil }
        return normalized.lowercased() == "unknown" ? "surface" : normalized
    }

    private func normalizedDefectType(_ value: String?) -> String? {
        guard let normalized = normalizedValue(value) else { return nil }
        return normalized.lowercased() == "unknown" ? "field note" : normalized
    }

    private func normalizedSeverity(_ value: String?) -> String? {
        guard let normalized = normalizedValue(value)?.lowercased() else { return nil }
        switch normalized {
        case "low", "medium", "high", "critical":
            return normalized
        case "unknown":
            return "medium"
        default:
            return nil
        }
    }

    private func makeBCFDescription(
        transcriptOriginal: String,
        transcriptEnglish: String?,
        metadata: ExtractedDefectMetadata
    ) -> String {
        var lines: [String] = []
        lines.append("Original: \(transcriptOriginal)")
        if let transcriptEnglish, transcriptEnglish != transcriptOriginal {
            lines.append("English: \(transcriptEnglish)")
        }
        lines.append("Location: \(metadata.storey) > \(metadata.space ?? "-") > \(metadata.orientation ?? "-") \(metadata.elementType)")
        lines.append("Severity: \(metadata.severity)")
        return lines.joined(separator: "\n")
    }

    private func priority(for severity: String) -> String {
        switch severity.lowercased() {
        case "critical":
            return "Critical"
        case "high":
            return "High"
        case "medium":
            return "Normal"
        default:
            return "Low"
        }
    }
}
