import Foundation
import GRDB

struct Defect: Codable, Equatable, Identifiable, FetchableRecord, MutablePersistableRecord, Sendable {
    var id: String
    var projectId: String
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

    var transcriptOriginal: String?
    var transcriptEnglish: String?

    var photoPath: String?
    var photoUrl: String?

    var defectType: String
    var severity: Severity
    var aiSafetyNotes: String?

    var reporter: String
    var timestamp: Date
    var bcfPath: String?

    var resolved: Bool
    var synced: Bool

    static let databaseTableName = "defects"

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
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
        case photoUrl = "photo_url"
        case defectType = "defect_type"
        case severity
        case aiSafetyNotes = "ai_safety_notes"
        case reporter
        case timestamp
        case bcfPath = "bcf_path"
        case resolved
        case synced
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let projectId = Column(CodingKeys.projectId)
        static let guid = Column(CodingKeys.guid)
        static let storey = Column(CodingKeys.storey)
        static let space = Column(CodingKeys.space)
        static let elementType = Column(CodingKeys.elementType)
        static let orientation = Column(CodingKeys.orientation)
        static let timestamp = Column(CodingKeys.timestamp)
        static let synced = Column(CodingKeys.synced)
        static let resolved = Column(CodingKeys.resolved)
    }
}

struct VoiceReport: Codable, Sendable {
    var transcriptOriginal: String
    var transcriptEnglish: String?

    var storey: String
    var space: String?
    var elementType: String
    var orientation: String?

    var defectType: String
    var severity: Severity
    var aiSafetyNotes: String?

    var photoPath: String?
    var reporter: String
    var timestamp: Date
}
