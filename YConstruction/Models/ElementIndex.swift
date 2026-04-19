import Foundation

struct ElementIndex: Decodable, Sendable {
    let projectId: String
    let schema: String
    let storeys: [Storey]
    let elements: [String: Element]

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case schema
        case storeys
        case elements
    }

    struct Storey: Decodable, Sendable {
        let name: String
        let elevation: Double
        let heightRange: [Double]

        enum CodingKeys: String, CodingKey {
            case name
            case elevation
            case heightRange = "height_range"
        }
    }

    struct Element: Decodable, Sendable, Identifiable {
        let guid: String
        let elementType: String
        let storey: String?
        let space: String?
        let orientation: String?
        let centroid: [Double]
        let bbox: [[Double]]
        let name: String?

        var id: String { guid }

        var centroidPoint: SIMD3<Double> {
            SIMD3(centroid[0], centroid[1], centroid[2])
        }

        var bboxMin: SIMD3<Double> {
            SIMD3(bbox[0][0], bbox[0][1], bbox[0][2])
        }

        var bboxMax: SIMD3<Double> {
            SIMD3(bbox[1][0], bbox[1][1], bbox[1][2])
        }
    }
}
