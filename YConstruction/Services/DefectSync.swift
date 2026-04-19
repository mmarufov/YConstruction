import Foundation
import Combine

enum ProjectBackendConfig {
    static let reporterID = "Worker 1"
}

struct DefectSyncDraft: Sendable {
    let transcriptOriginal: String
    let transcriptEnglish: String?
    let photoLocalURL: URL?
    let timestamp: Date
    let reporter: String
    let metadataOverride: DefectCapturedMetadata?

    init(
        transcriptOriginal: String,
        transcriptEnglish: String?,
        photoLocalURL: URL?,
        timestamp: Date,
        reporter: String,
        metadataOverride: DefectCapturedMetadata? = nil
    ) {
        self.transcriptOriginal = transcriptOriginal
        self.transcriptEnglish = transcriptEnglish
        self.photoLocalURL = photoLocalURL
        self.timestamp = timestamp
        self.reporter = reporter
        self.metadataOverride = metadataOverride
    }
}

struct DefectCapturedMetadata: Equatable, Sendable {
    let guid: String?
    let storey: String?
    let space: String?
    let elementType: String?
    let orientation: String?
    let defectType: String?
    let severity: String?
    let aiSafetyNotes: String?
}

struct DefectEnqueueResult: Equatable, Sendable {
    let recordID: String
    let wasUploaded: Bool
    let photoUploaded: Bool
    let photoURL: String?
}

struct CachedProjectChangeRecord: Equatable, Identifiable, Sendable {
    let id: String
    let projectID: String
    let guid: String
    let storey: String
    let space: String?
    let elementType: String
    let orientation: String?
    let defectType: String
    let severity: String
    let aiSafetyNotes: String?
    let reporter: String
    let timestamp: Date
    let transcriptOriginal: String?
    let transcriptEnglish: String?
    let photoURL: String?
    let bcfPath: String?
    let resolved: Bool
    let synced: Bool
    let updatedAt: Date?

    init(from defect: Defect) {
        self.id = defect.id
        self.projectID = defect.projectId
        self.guid = defect.guid
        self.storey = defect.storey
        self.space = defect.space
        self.elementType = defect.elementType
        self.orientation = defect.orientation
        self.defectType = defect.defectType
        self.severity = defect.severity.rawValue
        self.aiSafetyNotes = defect.aiSafetyNotes
        self.reporter = defect.reporter
        self.timestamp = defect.timestamp
        self.transcriptOriginal = defect.transcriptOriginal
        self.transcriptEnglish = defect.transcriptEnglish
        self.photoURL = defect.photoUrl
        self.bcfPath = defect.bcfPath
        self.resolved = defect.resolved
        self.synced = defect.synced
        self.updatedAt = nil
    }
}

@MainActor
final class DefectSyncService: ObservableObject {
    @Published private(set) var backendStatusText: String = "Ready"
    @Published private(set) var syncStatusText: String = "Idle"
    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var isOnline: Bool = false
    @Published private(set) var isOnWiFi: Bool = false
    @Published private(set) var isPreferredSyncNetwork: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var isBackendReady: Bool = false

    private let store: DefectStore
    private let syncService: SyncService
    private let database: DatabaseService
    private let resolver: DefectResolverService?

    init(
        store: DefectStore,
        syncService: SyncService,
        database: DatabaseService = .shared,
        resolver: DefectResolverService? = nil
    ) {
        self.store = store
        self.syncService = syncService
        self.database = database
        self.resolver = resolver

        syncService.$isOnline
            .receive(on: DispatchQueue.main)
            .assign(to: &$isOnline)
        syncService.$isOnWiFi
            .receive(on: DispatchQueue.main)
            .assign(to: &$isOnWiFi)
        syncService.$isSyncing
            .receive(on: DispatchQueue.main)
            .map { $0 ? "Syncing..." : "Idle" }
            .assign(to: &$syncStatusText)
        syncService.$lastSyncedAt
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastSyncedAt)
        store.$defects
            .receive(on: DispatchQueue.main)
            .map { $0.filter { !$0.synced }.count }
            .assign(to: &$pendingCount)
    }

    func prepare() async {
        await syncService.preflight()
        isBackendReady = true
        backendStatusText = "Supabase ready"
    }

    func persistCapturedPhoto(from sourceURL: URL) async throws -> URL {
        try ArtifactStore.persistPhotoCopy(from: sourceURL)
    }

    func cachedProjectChangesForRetrieval() async -> [CachedProjectChangeRecord] {
        guard let defects = try? database.syncedDefects(projectId: store.projectId) else { return [] }
        return defects.map { CachedProjectChangeRecord(from: $0) }
    }

    func enqueue(draft: DefectSyncDraft) async throws -> DefectEnqueueResult {
        var defect = makeDefect(from: draft)

        if let bcfURL = try? BCFEmitterService().emit(from: defect) {
            defect.bcfPath = bcfURL.path
        }

        do {
            try database.insert(defect)
            store.refresh()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
        await syncService.drainIfOnline()
        let stored = try? database.defect(id: defect.id)
        return DefectEnqueueResult(
            recordID: defect.id,
            wasUploaded: stored?.synced ?? false,
            photoUploaded: (stored?.photoUrl != nil),
            photoURL: stored?.photoUrl
        )
    }

    func syncNow(manualOverride: Bool = true) async {
        await syncService.drain()
        await syncService.catchUp()
    }

    private func makeDefect(from draft: DefectSyncDraft) -> Defect {
        let meta = draft.metadataOverride
        let severity = DefectNormalization.normalizedSeverity(meta?.severity) ?? .medium
        let elementType = DefectNormalization.normalizedElementType(meta?.elementType) ?? "surface"
        let defectType = DefectNormalization.normalizedDefectType(meta?.defectType) ?? "field note"
        let storey = DefectNormalization.normalizedValue(meta?.storey) ?? "Ground"
        let space = DefectNormalization.normalizedValue(meta?.space)
        let orientation = DefectNormalization.normalizedValue(meta?.orientation)
        let guidOverride = DefectNormalization.normalizedValue(meta?.guid) ?? ""

        let position: PositionResolution?
        if let resolver {
            if resolver.index == nil {
                print("[DefectSync] resolver present but index not loaded — falling back to (0,0,0)")
                position = nil
            } else {
                position = resolver.bestPosition(
                    storey: storey,
                    space: space,
                    elementType: elementType,
                    orientation: orientation
                )
            }
        } else {
            print("[DefectSync] resolver instance is nil — DefectSyncService was built without one")
            position = nil
        }
        let centroid = position?.centroid ?? SIMD3<Double>(0, 0, 0)
        let bboxMin = position?.bboxMin ?? SIMD3<Double>(0, 0, 0)
        let bboxMax = position?.bboxMax ?? SIMD3<Double>(0, 0, 0)
        let resolvedGuid = guidOverride.isEmpty ? (position?.matchedGuid ?? "") : guidOverride

        if let position {
            print("[DefectSync] resolver tier=\(position.tier.rawValue) storey=\(storey) space=\(space ?? "-") type=\(elementType) orient=\(orientation ?? "-") centroid=\(centroid)")
        }

        return Defect(
            id: UUID().uuidString.lowercased(),
            projectId: store.projectId,
            guid: resolvedGuid,
            storey: storey,
            space: space,
            elementType: elementType,
            orientation: orientation,
            centroidX: centroid.x, centroidY: centroid.y, centroidZ: centroid.z,
            bboxMinX: bboxMin.x, bboxMinY: bboxMin.y, bboxMinZ: bboxMin.z,
            bboxMaxX: bboxMax.x, bboxMaxY: bboxMax.y, bboxMaxZ: bboxMax.z,
            transcriptOriginal: DefectNormalization.normalizedValue(draft.transcriptOriginal),
            transcriptEnglish: DefectNormalization.normalizedValue(draft.transcriptEnglish),
            photoPath: draft.photoLocalURL?.path,
            photoUrl: nil,
            defectType: defectType,
            severity: severity,
            aiSafetyNotes: DefectNormalization.normalizedValue(meta?.aiSafetyNotes),
            reporter: draft.reporter,
            timestamp: draft.timestamp,
            bcfPath: nil,
            resolved: false,
            synced: false
        )
    }
}
