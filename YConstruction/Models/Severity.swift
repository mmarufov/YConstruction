import Foundation

enum Severity: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
    case critical
}
