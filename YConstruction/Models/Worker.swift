import Foundation
import SwiftUI
import UIKit
import GRDB

nonisolated struct Worker: Codable, Equatable, Identifiable, FetchableRecord, MutablePersistableRecord, Sendable {
    var id: String
    var name: String
    var department: String
    var colorIndex: Int
    var createdAt: Date
    var updatedAt: Date

    static let databaseTableName = "workers"

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case department
        case colorIndex = "color_index"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let colorIndex = Column(CodingKeys.colorIndex)
    }
}

nonisolated enum WorkerColorPalette {
    static let hex: [UInt32] = [
        0x4E79A7, // 0 blue
        0xF28E2B, // 1 orange
        0xE15759, // 2 red
        0x76B7B2, // 3 teal
        0x59A14F, // 4 green
        0xEDC948, // 5 yellow
        0xB07AA1, // 6 purple
        0xFF9DA7, // 7 pink
        0x9C755F, // 8 brown
        0x17BECF  // 9 cyan
    ]

    static func uiColor(for index: Int) -> UIColor {
        let slot = ((index % hex.count) + hex.count) % hex.count
        let rgb = hex[slot]
        return UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    static func color(for index: Int) -> Color {
        Color(uiColor(for: index))
    }

    static func fallbackIndex(for name: String) -> Int {
        var hash: UInt32 = 5381
        for byte in name.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt32(byte)
        }
        return Int(hash % UInt32(hex.count))
    }
}
