import Foundation

enum SmokeTests {
    static let expectedNorthWallB101GUID = "2O2Fr$t4X7Zf8NOew3FNld"

    static func runAll() -> [String] {
        var results: [String] = []
        results.append(runResolverTest())
        results.append(runAmbiguousResolverTest())
        results.append(runDatabaseTest())
        results.append(runOfflinePendingTest())
        results.append(runBCFTest())
        results.append(runUnresolvedBCFTest())
        results.append(runDryRunMarkerTest())
        results.append(runCactusWeightsMissingTest())
        results.append(runSupabasePlaceholderInitTest())
        return results
    }

    // MARK: - 1. Resolver

    @discardableResult
    static func runResolverTest() -> String {
        let resolver = DefectResolverService()
        do {
            try resolver.loadFromBundle()
        } catch {
            return "[Resolver] FAIL: \(error.localizedDescription)"
        }
        let query = ElementQuery(storey: "Level 1", space: "B101", elementType: "wall", orientation: "north")
        switch resolver.resolve(query) {
        case .match(let r):
            if r.element.guid == expectedNorthWallB101GUID {
                return "[Resolver] PASS: B101 north wall → \(r.element.guid)"
            }
            return "[Resolver] FAIL: got \(r.element.guid)"
        case .ambiguous(let c):
            return "[Resolver] FAIL: ambiguous \(c.count) candidates"
        case .notFound:
            return "[Resolver] FAIL: not found"
        }
    }

    // MARK: - 2. Ambiguous resolver

    @discardableResult
    static func runAmbiguousResolverTest() -> String {
        let resolver = DefectResolverService()
        do {
            try resolver.loadFromBundle()
        } catch {
            return "[Resolver ambiguous] FAIL: \(error.localizedDescription)"
        }
        let query = ElementQuery(storey: nil, space: nil, elementType: "wall", orientation: nil)
        switch resolver.resolve(query) {
        case .ambiguous(let candidates):
            return "[Resolver ambiguous] PASS: surfaced \(candidates.count) picker candidates"
        case .match(let r):
            return "[Resolver ambiguous] FAIL: expected ambiguous, got match \(r.element.guid)"
        case .notFound:
            return "[Resolver ambiguous] FAIL: expected ambiguous, got notFound"
        }
    }

    // MARK: - 3. DB

    @discardableResult
    static func runDatabaseTest() -> String {
        do {
            let db = try DatabaseService(filename: "yconstruction-smoketest-1.sqlite")
            try db.deleteAll()
            let defect = makeFixtureDefect(id: "smoke-db-\(UUID().uuidString)")
            try db.insert(defect)
            let count = try db.count(projectId: defect.projectId)
            let pending = try db.pendingSync()
            guard count == 1, pending.count == 1, pending.first?.id == defect.id else {
                return "[DB] FAIL: count=\(count) pending=\(pending.count)"
            }
            try db.markSynced(id: defect.id, photoUrl: "https://example.com/p.jpg")
            let after = try db.pendingSync()
            guard after.isEmpty else { return "[DB] FAIL: still pending" }
            return "[DB] PASS: insert + pending + markSynced"
        } catch {
            return "[DB] FAIL: \(error.localizedDescription)"
        }
    }

    // MARK: - 4. Offline pending count

    @discardableResult
    static func runOfflinePendingTest() -> String {
        do {
            let db = try DatabaseService(filename: "yconstruction-smoketest-2.sqlite")
            try db.deleteAll()
            let a = makeFixtureDefect(id: "smoke-off-a-\(UUID().uuidString)")
            let b = makeFixtureDefect(id: "smoke-off-b-\(UUID().uuidString)")
            try db.insert(a)
            try db.insert(b)
            let pending = try db.pendingSync().count
            guard pending == 2 else { return "[Offline] FAIL: expected 2 pending, got \(pending)" }
            return "[Offline] PASS: 2 pending upload (no sync required)"
        } catch {
            return "[Offline] FAIL: \(error.localizedDescription)"
        }
    }

    // MARK: - 5. BCF

    @discardableResult
    static func runBCFTest() -> String {
        do {
            let emitter = BCFEmitterService()
            let url = try emitter.emit(from: makeFixtureDefect(id: "smoke-bcf-\(UUID().uuidString)"))
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            guard size > 0 else { return "[BCF] FAIL: empty zip" }
            return "[BCF] PASS: \(size) bytes → \(url.lastPathComponent)"
        } catch {
            return "[BCF] FAIL: \(error.localizedDescription)"
        }
    }

    @discardableResult
    static func runUnresolvedBCFTest() -> String {
        do {
            let emitter = BCFEmitterService()
            var defect = makeFixtureDefect(id: "smoke-bcf-unresolved-\(UUID().uuidString)")
            defect.guid = ""
            defect.photoPath = nil
            let url = try emitter.emit(from: defect)
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            guard size > 0 else { return "[BCF unresolved] FAIL: empty zip" }
            return "[BCF unresolved] PASS: \(size) bytes → \(url.lastPathComponent)"
        } catch {
            return "[BCF unresolved] FAIL: \(error.localizedDescription)"
        }
    }

    // MARK: - 6. Dry-run marker (resolver + DB insert, no STT/LM)

    @discardableResult
    static func runDryRunMarkerTest() -> String {
        let resolver = DefectResolverService()
        do {
            try resolver.loadFromBundle()
        } catch {
            return "[DryRun] FAIL: resolver load \(error.localizedDescription)"
        }

        let query = ElementQuery(storey: "Level 1", space: "B101", elementType: "wall", orientation: "north")
        guard case .match(let resolved) = resolver.resolve(query) else {
            return "[DryRun] FAIL: resolver did not match"
        }

        do {
            let db = try DatabaseService(filename: "yconstruction-smoketest-3.sqlite")
            try db.deleteAll()

            let defect = Defect(
                id: "smoke-dryrun-\(UUID().uuidString)",
                projectId: AppConfig.elementIndexProjectId,
                guid: resolved.element.guid,
                storey: resolved.element.storey ?? "Level 1",
                space: resolved.element.space,
                elementType: resolved.element.elementType,
                orientation: resolved.element.orientation,
                centroidX: resolved.element.centroid[0],
                centroidY: resolved.element.centroid[1],
                centroidZ: resolved.element.centroid[2],
                bboxMinX: resolved.element.bbox[0][0],
                bboxMinY: resolved.element.bbox[0][1],
                bboxMinZ: resolved.element.bbox[0][2],
                bboxMaxX: resolved.element.bbox[1][0],
                bboxMaxY: resolved.element.bbox[1][1],
                bboxMaxZ: resolved.element.bbox[1][2],
                transcriptOriginal: "Hay una grieta en la pared norte del baño B101.",
                transcriptEnglish: "There is a crack in the north wall of bathroom B101.",
                photoPath: nil,
                photoUrl: nil,
                defectType: "crack",
                severity: .high,
                aiSafetyNotes: "(dry-run)",
                reporter: AppConfig.reporterId,
                timestamp: Date(),
                bcfPath: nil,
                resolved: false,
                synced: false
            )
            try db.insert(defect)

            let saved = try db.defect(id: defect.id)
            guard let saved, saved.guid == expectedNorthWallB101GUID else {
                return "[DryRun] FAIL: persisted row did not round-trip"
            }
            return "[DryRun] PASS: VoiceReport → resolver → DB row → marker-ready (guid \(saved.guid))"
        } catch {
            return "[DryRun] FAIL: \(error.localizedDescription)"
        }
    }

    // MARK: - 7. Weights missing → clean throw

    @discardableResult
    static func runCactusWeightsMissingTest() -> String {
        guard !CactusService.gemmaWeightsAvailable(), !CactusService.whisperWeightsAvailable() else {
            return "[CactusWeights] SKIP: weights present on device; nothing to test"
        }

        let gemmaOK = throwsMissingWeightsError {
            _ = try CactusService.validatedGemmaModelPath()
        }
        let whisperOK = throwsMissingWeightsError {
            _ = try CactusService.validatedWhisperModelPath()
        }

        if gemmaOK && whisperOK {
            return "[CactusWeights] PASS: both models throw modelWeightsMissing cleanly"
        }
        return "[CactusWeights] FAIL: gemma=\(gemmaOK) whisper=\(whisperOK)"
    }

    // MARK: - 8. Supabase placeholder init

    @discardableResult
    static func runSupabasePlaceholderInitTest() -> String {
        let svc = SupabaseClientService(config: .placeholder)
        let client = svc.client()
        if svc.isConfigured {
            return "[Supabase] FAIL: placeholder should not be marked configured"
        }
        if client != nil {
            return "[Supabase] FAIL: placeholder should not produce a live client"
        }
        return "[Supabase] PASS: placeholder init is safe (no live client, no crash)"
    }

    // MARK: - Fixtures

    private static func throwsMissingWeightsError(_ work: () throws -> Void) -> Bool {
        do {
            try work()
            return false
        } catch let err as CactusServiceError {
            if case .modelWeightsMissing = err {
                return true
            }
            return false
        } catch {
            return false
        }
    }

    private static func makeFixtureDefect(id: String = "smoke-\(UUID().uuidString)") -> Defect {
        Defect(
            id: id,
            projectId: AppConfig.elementIndexProjectId,
            guid: expectedNorthWallB101GUID,
            storey: "Level 1",
            space: "B101",
            elementType: "wall",
            orientation: "north",
            centroidX: 2.538, centroidY: -2.208, centroidZ: 1.397,
            bboxMinX: 2.476, bboxMinY: -4.0, bboxMinZ: 0.0,
            bboxMaxX: 2.6, bboxMaxY: -0.417, bboxMaxZ: 2.795,
            transcriptOriginal: "Hay una grieta en la pared norte del baño B101",
            transcriptEnglish: "There is a crack in the north wall of bathroom B101",
            photoPath: nil,
            photoUrl: nil,
            defectType: "crack",
            severity: .high,
            aiSafetyNotes: "Possible structural concern; recommend inspection.",
            reporter: AppConfig.reporterId,
            timestamp: Date(),
            bcfPath: nil,
            resolved: false,
            synced: false
        )
    }
}
