import Foundation
import Combine
import GRDB

@MainActor
final class DefectStore: ObservableObject {
    @Published private(set) var defects: [Defect] = []
    @Published private(set) var pendingSyncCount: Int = 0
    @Published private(set) var lastSyncedAt: Date?

    let projectId: String
    private let database: DatabaseService
    private var cancellables: Set<AnyCancellable> = []
    private var observation: DatabaseCancellable?

    init(projectId: String = AppConfig.elementIndexProjectId,
         database: DatabaseService = .shared) {
        self.projectId = projectId
        self.database = database
        refresh()
        startObserving()
    }

    // MARK: - Queries

    func refresh() {
        do {
            let all = try database.defects(projectId: projectId)
            self.defects = all
            self.pendingSyncCount = all.filter { !$0.synced }.count
        } catch {
            self.defects = []
            self.pendingSyncCount = 0
        }
    }

    func defects(on storey: String) -> [Defect] {
        defects.filter { $0.storey == storey }
    }

    // MARK: - Mutations

    func add(_ defect: Defect) throws {
        try database.insert(defect)
        refresh()
    }

    func markResolved(_ id: String, resolved: Bool = true) throws {
        try database.markResolved(id: id, resolved: resolved)
        refresh()
    }

    func noteSynced(at date: Date = Date()) {
        self.lastSyncedAt = date
        refresh()
    }

    // MARK: - Observation

    private func startObserving() {
        let observation = ValueObservation.tracking { db in
            try Defect.filter(Defect.Columns.projectId == self.projectId).fetchAll(db)
        }
        self.observation = observation.start(
            in: database.dbPool,
            scheduling: .async(onQueue: .main),
            onError: { _ in },
            onChange: { [weak self] all in
                guard let self else { return }
                self.defects = all
                self.pendingSyncCount = all.filter { !$0.synced }.count
            }
        )
    }
}
