import Foundation

struct SavedProject: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var isDemo: Bool

    init(id: String, name: String, isDemo: Bool = false) {
        self.id = id
        self.name = name
        self.isDemo = isDemo
    }
}
