import Foundation
import Combine
import Supabase

@MainActor
final class WorkerDirectoryService: ObservableObject {
    static let shared = WorkerDirectoryService()

    @Published private(set) var workers: [Worker] = []

    private let database: DatabaseService
    private let supabase: SupabaseClientService
    private var refreshTask: Task<Void, Never>?

    private static let fallback: [Worker] = {
        let now = Date()
        let entries: [(String, String, String, Int)] = [
            ("w-001", "Worker 1", "Structural",      0),
            ("w-002", "Worker 2", "MEP",             1),
            ("w-003", "Worker 3", "Finishes",        2),
            ("w-004", "Worker 4", "Safety",          3),
            ("w-005", "Worker 5", "Site Supervisor", 4)
        ]
        return entries.map { id, name, dept, idx in
            Worker(id: id, name: name, department: dept, colorIndex: idx, createdAt: now, updatedAt: now)
        }
    }()

    init(
        database: DatabaseService = .shared,
        supabase: SupabaseClientService = .shared
    ) {
        self.database = database
        self.supabase = supabase
        loadCachedOrFallback()
    }

    func start() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refresh()
        }
    }

    func refresh() async {
        guard supabase.isConfigured, let client = supabase.client() else { return }
        do {
            let rows: [Worker] = try await client
                .from("workers")
                .select()
                .order("color_index", ascending: true)
                .execute()
                .value
            guard !rows.isEmpty else { return }
            for row in rows {
                try? database.upsert(row)
            }
            self.workers = rows
        } catch {
            print("WorkerDirectory refresh failed: \(error)")
        }
    }

    func worker(forReporter name: String) -> Worker? {
        workers.first { $0.name == name }
    }

    func colorIndex(forReporter name: String) -> Int {
        if let w = worker(forReporter: name) { return w.colorIndex }
        return WorkerColorPalette.fallbackIndex(for: name)
    }

    private func loadCachedOrFallback() {
        if let cached = try? database.allWorkers(), !cached.isEmpty {
            self.workers = cached
        } else {
            self.workers = Self.fallback
            for w in Self.fallback {
                try? database.upsert(w)
            }
        }
    }
}
