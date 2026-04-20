import Foundation
import Network
import Combine
import Supabase

@MainActor
final class SyncService: ObservableObject {
    private enum SyncFailure: LocalizedError {
        case uploadedPhotoUnavailable(path: String)

        var errorDescription: String? {
            switch self {
            case .uploadedPhotoUnavailable(let path):
                return "The uploaded photo could not be verified in Supabase Storage: \(path)"
            }
        }
    }

    @Published private(set) var isOnline: Bool = false
    @Published private(set) var isOnWiFi: Bool = false
    @Published private(set) var isSyncing: Bool = false
    @Published private(set) var lastSyncedAt: Date?
    /// Monotonic counter bumped whenever the cached project bundle (GLB +
    /// element index) on disk is dropped because the cloud has no manifest
    /// for this project. UI layers should observe this and re-run their
    /// bootstrap so the 3D model clears without an app relaunch.
    @Published private(set) var bundleInvalidationTick: Int = 0

    private static func lastSyncedKey(projectId: String) -> String {
        "yconstruction.lastSyncedAt.\(projectId)"
    }

    private let database: DatabaseService
    private let supabase: SupabaseClientService
    private let store: DefectStore
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.yconstruction.network")
    private var periodicTask: Task<Void, Never>?

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
        // Proactively drop any stale cursor from an older build.
        UserDefaults.standard.removeObject(forKey: "yconstruction.catchUpCursor.\(store.projectId)")
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
                }
            }
        }
        monitor.start(queue: monitorQueue)

        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                // 5 s matches the Blender plugin's poll cadence. Pure
                // stateless re-fetch — no cursor, no realtime — so a missed
                // row simply shows up on the next tick.
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self?.syncIfOnline()
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
    }

    // MARK: - Public orchestration

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

    func catchUp() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        await catchUpRemote()
        await reconcileWithCloud()
    }

    /// Project-bundle reconciliation: if the `projects` manifest row for this
    /// project is gone, drop the cached GLB + element index on disk and bump
    /// `bundleInvalidationTick` so MainView re-runs boot. Defect reconciliation
    /// lives in `catchUpRemote()` now — it already re-fetches the full list
    /// each tick and prunes anything the cloud doesn't have.
    func reconcileWithCloud() async {
        guard supabase.isConfigured, let client = supabase.client() else { return }

        do {
            let projectRows: [[String: AnyJSON]] = try await client
                .from("projects")
                .select("id")
                .eq("id", value: store.projectId)
                .limit(1)
                .execute()
                .value
            if projectRows.isEmpty {
                let dir = try AppConfig.projectDirectory(projectId: store.projectId)
                let fm = FileManager.default
                var cleared = false
                for name in ["duplex.glb", "element_index.json", "cache_meta.json"] {
                    let url = dir.appendingPathComponent(name)
                    if fm.fileExists(atPath: url.path) {
                        try? fm.removeItem(at: url)
                        cleared = true
                    }
                }
                if cleared {
                    bundleInvalidationTick += 1
                    print("[Sync] project manifest gone — cleared bundle cache, tick=\(bundleInvalidationTick)")
                }
            }
        } catch {
            print("[Sync] reconcile (manifest) failed: \(error)")
        }
    }

    func syncIfOnline() async {
        guard isOnline, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        await drainPending()
        await catchUpRemote()
    }

    private func reconnectSync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        await catchUpRemote()
        await drainPending()
    }

    // MARK: - Drain

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
                    photoUrl: DefectNormalization.normalizedValue(uploaded.photoUrl),
                    bcfPath: uploaded.bcfPath
                )
            } catch {
                print("sync failed for \(defect.id): \(error)")
                break
            }
        }
        store.noteSynced()
        stampLastSynced()
    }

    // MARK: - Catch-up (stateless full-list poll, Blender-style)

    /// Re-fetches the entire `project_changes` list for this project, upserts
    /// each row locally, and prunes anything the cloud no longer has. No
    /// cursor, no realtime — each tick is independent and self-correcting, so
    /// a missed or failed row always retries on the next tick.
    private func catchUpRemote() async {
        guard supabase.isConfigured, let client = supabase.client() else { return }
        do {
            let rows: [[String: AnyJSON]] = try await client
                .from("project_changes")
                .select()
                .eq("project_id", value: store.projectId)
                .order("updated_at", ascending: true)
                .execute()
                .value

            var cloudIds = Set<String>()
            for row in rows {
                if let id = row["id"]?.stringValue {
                    cloudIds.insert(id)
                }
                await handleRemote(row)
            }

            // Prune local rows missing upstream. Keep unsynced rows — they're
            // uploads still queued for drain.
            let localIds = Set((try? database.ids(projectId: store.projectId)) ?? [])
            for id in localIds.subtracting(cloudIds) {
                if let d = try? database.defect(id: id), !d.synced { continue }
                try? database.delete(id: id)
            }
            store.refresh()
            stampLastSynced()
        } catch {
            print("[Sync] catchUp error: \(error)")
        }
    }

    private func stampLastSynced() {
        let now = Date()
        lastSyncedAt = now
        UserDefaults.standard.set(
            now,
            forKey: Self.lastSyncedKey(projectId: store.projectId)
        )
    }

    @discardableResult
    private func upload(_ defect: Defect, client: SupabaseClient) async throws -> Defect {
        var normalized = defect.normalizedForUpload()
        normalized.synced = true

        if let photoPath = normalized.photoPath {
            if FileManager.default.fileExists(atPath: photoPath) {
                let remote = "\(normalized.projectId)/\(URL(fileURLWithPath: photoPath).lastPathComponent)"
                let data = try Data(contentsOf: URL(fileURLWithPath: photoPath))
                let options = FileOptions(upsert: true)
                try await client.storage.from(supabase.config.photosBucket)
                    .upload(remote, data: data, options: options)
                guard try await client.storage.from(supabase.config.photosBucket).exists(path: remote) else {
                    throw SyncFailure.uploadedPhotoUnavailable(path: remote)
                }
                normalized.photoPath = remote
                normalized.photoUrl = try await signedPhotoURL(
                    remotePath: remote,
                    bucket: supabase.config.photosBucket,
                    client: client
                )
            } else if !photoPath.hasPrefix("/") {
                // Photo is already in Storage (row received from another device
                // or re-synced after local file was purged). Refresh photo_url
                // if the row doesn't have one yet.
                if DefectNormalization.normalizedValue(normalized.photoUrl) == nil {
                    normalized.photoUrl = try? await signedPhotoURL(
                        remotePath: photoPath,
                        bucket: supabase.config.photosBucket,
                        client: client
                    )
                }
            }
            // else: absolute local path but file is gone — skip the photo step
            // and still upsert the row so non-photo fields (resolved, etc.) sync.
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

    private func signedPhotoURL(
        remotePath: String,
        bucket: String,
        client: SupabaseClient
    ) async throws -> String {
        try await client.storage
            .from(bucket)
            .createSignedURL(path: remotePath, expiresIn: 60 * 60 * 24 * 30)
            .absoluteString
    }

    // MARK: - Remote → local apply

    /// Upserts a single row from `project_changes` into the local DB,
    /// preserving the local photo path when the file is already cached on
    /// device. Silent on failure — the next poll tick will retry.
    private func handleRemote(_ record: [String: AnyJSON]) async {
        do {
            let jsonObject = record.mapValues { $0.value }
            let data = try JSONSerialization.data(withJSONObject: jsonObject)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var defect = try decoder.decode(Defect.self, from: data)
            let existingDefect = try database.defect(id: defect.id)
            if let localPhotoPath = existingDefect?.photoPath,
               FileManager.default.fileExists(atPath: localPhotoPath) {
                defect.photoPath = localPhotoPath
            } else {
                defect.photoPath = DefectNormalization.normalizedValue(defect.photoPath)
            }
            if DefectNormalization.normalizedValue(defect.photoUrl) == nil {
                defect.photoUrl = existingDefect?.photoUrl
            }
            defect.synced = true
            try database.upsert(defect)
        } catch {
            let id = record["id"]?.stringValue ?? "?"
            print("[Sync] failed to persist remote defect id=\(id): \(error)")
        }
    }
}
