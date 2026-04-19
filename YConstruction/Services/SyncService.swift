import Foundation
import Network
import Combine
import Supabase

@MainActor
final class SyncService: ObservableObject {
    @Published private(set) var isOnline: Bool = false
    @Published private(set) var isOnWiFi: Bool = false
    @Published private(set) var isSyncing: Bool = false
    @Published private(set) var lastSyncedAt: Date?

    private static func lastSyncedKey(projectId: String) -> String {
        "yconstruction.lastSyncedAt.\(projectId)"
    }

    private let database: DatabaseService
    private let supabase: SupabaseClientService
    private let store: DefectStore
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.yconstruction.network")
    private var periodicTask: Task<Void, Never>?
    private var realtimeTask: Task<Void, Never>?

    init(store: DefectStore,
         database: DatabaseService = .shared,
         supabase: SupabaseClientService = .shared) {
        self.store = store
        self.database = database
        self.supabase = supabase
        if let stamp = UserDefaults.standard.object(
            forKey: Self.lastSyncedKey(projectId: store.projectId)
        ) as? Date {
            self.lastSyncedAt = stamp
        }
    }

    func start() {
        guard periodicTask == nil else { return }

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let wasOnline = self.isOnline
                let nowOnline = path.status == .satisfied
                self.isOnline = nowOnline
                self.isOnWiFi = nowOnline && path.usesInterfaceType(.wifi)
                if nowOnline && !wasOnline {
                    await self.reconnectSync()
                    self.startRealtime()
                } else if !nowOnline {
                    self.stopRealtime()
                }
            }
        }
        monitor.start(queue: monitorQueue)

        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                await self?.drainIfOnline()
            }
        }

        Task { await preflight() }
    }

    func preflight() async {
        guard supabase.isConfigured, let client = supabase.client() else { return }
        do {
            let _: [[String: AnyJSON]] = try await client
                .from("project_changes")
                .select("id")
                .limit(1)
                .execute()
                .value
            for bucket in [supabase.config.photosBucket, supabase.config.issuesBucket, supabase.config.projectsBucket] {
                _ = try await client.storage.from(bucket).list(path: "", options: SearchOptions(limit: 1))
            }
        } catch {
            print("preflight check failed: \(error)")
        }
    }

    func stop() {
        monitor.cancel()
        periodicTask?.cancel()
        periodicTask = nil
        stopRealtime()
    }

    // MARK: - Drain

    func drainIfOnline() async {
        guard isOnline else { return }
        await drain()
    }

    func drain() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        await drainPending()
    }

    private func reconnectSync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        await catchUp()
        await drainPending()
    }

    private func drainPending() async {
        guard supabase.isConfigured, let client = supabase.client() else { return }

        let pending: [Defect]
        do { pending = try database.pendingSync(projectId: store.projectId) }
        catch { return }

        for defect in pending {
            do {
                let uploaded = try await upload(defect, client: client)
                try database.markSynced(
                    id: defect.id,
                    photoUrl: publicUrl(defect: defect, client: client),
                    bcfPath: uploaded.bcfPath
                )
            } catch {
                print("sync failed for \(defect.id): \(error)")
                break
            }
        }
        store.noteSynced()
        let now = Date()
        lastSyncedAt = now
        UserDefaults.standard.set(now, forKey: Self.lastSyncedKey(projectId: store.projectId))
    }

    // MARK: - Catch-up

    func catchUp() async {
        guard supabase.isConfigured, let client = supabase.client() else { return }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let sinceString = (lastSyncedAt.map { iso.string(from: $0) }) ?? iso.string(from: Date(timeIntervalSince1970: 0))
        do {
            let rows: [[String: AnyJSON]] = try await client
                .from("project_changes")
                .select()
                .eq("project_id", value: store.projectId)
                .gt("updated_at", value: sinceString)
                .execute()
                .value
            for row in rows {
                await handleRemote(row, database: database, store: store)
            }
        } catch {
            print("catchUp error: \(error)")
        }
    }

    @discardableResult
    private func upload(_ defect: Defect, client: SupabaseClient) async throws -> Defect {
        var normalized = defect.normalizedForUpload()
        normalized.synced = true

        if let photoPath = normalized.photoPath, FileManager.default.fileExists(atPath: photoPath) {
            let remote = "\(normalized.projectId)/\(URL(fileURLWithPath: photoPath).lastPathComponent)"
            let data = try Data(contentsOf: URL(fileURLWithPath: photoPath))
            let options = FileOptions(upsert: true)
            try await client.storage.from(supabase.config.photosBucket)
                .upload(remote, data: data, options: options)
        }

        if let bcfPath = normalized.bcfPath, FileManager.default.fileExists(atPath: bcfPath) {
            let remote = "\(normalized.projectId)/\(URL(fileURLWithPath: bcfPath).lastPathComponent)"
            let data = try Data(contentsOf: URL(fileURLWithPath: bcfPath))
            let options = FileOptions(upsert: true)
            try await client.storage.from(supabase.config.issuesBucket)
                .upload(remote, data: data, options: options)
            normalized.bcfPath = remote
        }

        let row = try defectPayload(normalized)
        try await client
            .from("project_changes")
            .upsert(row, onConflict: "id")
            .execute()
        return normalized
    }

    private func defectPayload(_ d: Defect) throws -> [String: AnyJSON] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(d)
        let decoder = JSONDecoder()
        return try decoder.decode([String: AnyJSON].self, from: data)
    }

    private func publicUrl(defect: Defect, client: SupabaseClient) -> String? {
        guard let photoPath = defect.photoPath else { return nil }
        let remote = "\(defect.projectId)/\(URL(fileURLWithPath: photoPath).lastPathComponent)"
        let url = try? client.storage.from(supabase.config.photosBucket).getPublicURL(path: remote)
        return url?.absoluteString
    }

    // MARK: - Realtime

    private func startRealtime() {
        guard supabase.isConfigured, let client = supabase.client() else { return }
        realtimeTask?.cancel()

        let projectId = store.projectId
        let database = self.database
        let store = self.store
        realtimeTask = Task {
            do {
                let channel = client.realtimeV2.channel("project_changes:\(projectId)")
                let changes = channel.postgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: "project_changes",
                    filter: "project_id=eq.\(projectId)"
                )
                try await channel.subscribe()
                for await change in changes {
                    switch change {
                    case .insert(let action):
                        await handleRemote(action.record, database: database, store: store)
                    case .update(let action):
                        await handleRemote(action.record, database: database, store: store)
                    default:
                        break
                    }
                }
            } catch {
                print("realtime error: \(error)")
            }
        }
    }

    private func stopRealtime() {
        realtimeTask?.cancel()
        realtimeTask = nil
    }

    private func handleRemote(
        _ record: [String: AnyJSON],
        database: DatabaseService,
        store: DefectStore
    ) async {
        do {
            let jsonObject = record.mapValues { $0.value }
            let data = try JSONSerialization.data(withJSONObject: jsonObject)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var defect = try decoder.decode(Defect.self, from: data)
            defect.synced = true
            try database.upsert(defect)
            await MainActor.run { store.refresh() }
        } catch {
            print("failed to decode remote defect: \(error)")
        }
    }
}
