import Foundation

struct ProcessResult: Sendable {
    let defectId: String
    let resolvedGuid: String?
    let centroid: SIMD3<Double>?
    let bboxMin: SIMD3<Double>?
    let bboxMax: SIMD3<Double>?
    let storey: String
    let bcfPath: URL?
}
