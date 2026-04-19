import Foundation
import Combine

@MainActor
final class ProjectsStore: ObservableObject {
    @Published private(set) var projects: [SavedProject] = []

    private let storageKey = "yconstruction.projects.v1"

    init() {
        reload()
    }

    func reload() {
        projects = loadPersisted()
    }

    @discardableResult
    func add(id rawId: String, name rawName: String) -> Bool {
        let id = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return false }
        guard !projects.contains(where: { $0.id == id }) else { return false }

        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = SavedProject(id: id, name: trimmedName.isEmpty ? id : trimmedName)
        projects.append(project)
        persist()
        return true
    }

    func remove(id: String) {
        projects.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        let custom = projects.filter { !$0.isDemo }
        guard let data = try? JSONEncoder().encode(custom) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadPersisted() -> [SavedProject] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SavedProject].self, from: data) else {
            return []
        }
        return decoded
    }
}
