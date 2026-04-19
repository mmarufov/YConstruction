import Foundation
import GRDB

nonisolated final class DatabaseService: @unchecked Sendable {
    static let shared: DatabaseService = {
        do {
            return try DatabaseService(filename: "yconstruction.sqlite")
        } catch {
            fatalError("Failed to open database: \(error)")
        }
    }()

    let dbPool: DatabasePool

    init(filename: String) throws {
        let docs = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dbURL = docs.appendingPathComponent(filename)

        var config = Configuration()
        config.foreignKeysEnabled = true
        self.dbPool = try DatabasePool(path: dbURL.path, configuration: config)

        try Self.migrator.migrate(dbPool)
    }

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()

        m.registerMigration("v1_create_defects") { db in
            try db.create(table: "defects") { t in
                t.column("id", .text).primaryKey()
                t.column("project_id", .text).notNull()
                t.column("guid", .text).notNull()
                t.column("storey", .text).notNull()
                t.column("space", .text)
                t.column("element_type", .text).notNull()
                t.column("orientation", .text)

                t.column("centroid_x", .double).notNull()
                t.column("centroid_y", .double).notNull()
                t.column("centroid_z", .double).notNull()

                t.column("bbox_min_x", .double).notNull()
                t.column("bbox_min_y", .double).notNull()
                t.column("bbox_min_z", .double).notNull()
                t.column("bbox_max_x", .double).notNull()
                t.column("bbox_max_y", .double).notNull()
                t.column("bbox_max_z", .double).notNull()

                t.column("transcript_original", .text)
                t.column("transcript_english", .text)

                t.column("photo_path", .text)
                t.column("photo_url", .text)

                t.column("defect_type", .text).notNull()
                t.column("severity", .text).notNull()
                t.column("ai_safety_notes", .text)

                t.column("reporter", .text).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("bcf_path", .text)

                t.column("resolved", .boolean).notNull().defaults(to: false)
                t.column("synced", .boolean).notNull().defaults(to: false)
            }

            try db.create(
                index: "idx_defects_project_storey",
                on: "defects",
                columns: ["project_id", "storey"]
            )
            try db.create(
                index: "idx_defects_synced",
                on: "defects",
                columns: ["synced"]
            )
        }

        m.registerMigration("v2_create_workers") { db in
            try db.create(table: "workers") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull().unique()
                t.column("department", .text).notNull()
                t.column("color_index", .integer).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(
                index: "idx_workers_name",
                on: "workers",
                columns: ["name"]
            )
        }

        return m
    }

    // MARK: - Workers

    func upsert(_ worker: Worker) throws {
        try dbPool.write { db in
            var w = worker
            try w.upsert(db)
        }
    }

    func allWorkers() throws -> [Worker] {
        try dbPool.read { db in
            try Worker
                .order(Worker.Columns.colorIndex.asc)
                .fetchAll(db)
        }
    }

    // MARK: - CRUD

    func insert(_ defect: Defect) throws {
        try dbPool.write { db in
            var d = defect
            try d.insert(db)
        }
    }

    func upsert(_ defect: Defect) throws {
        try dbPool.write { db in
            var d = defect
            try d.upsert(db)
        }
    }

    func update(_ defect: Defect) throws {
        try dbPool.write { db in
            try defect.update(db)
        }
    }

    func defect(id: String) throws -> Defect? {
        try dbPool.read { db in
            try Defect.fetchOne(db, key: id)
        }
    }

    func defects(projectId: String) throws -> [Defect] {
        try dbPool.read { db in
            try Defect
                .filter(Defect.Columns.projectId == projectId)
                .order(Defect.Columns.timestamp.desc)
                .fetchAll(db)
        }
    }

    func syncedDefects(projectId: String? = nil) throws -> [Defect] {
        try dbPool.read { db in
            var request = Defect
                .filter(Defect.Columns.synced == true)
                .order(Defect.Columns.timestamp.desc)
            if let projectId {
                request = request.filter(Defect.Columns.projectId == projectId)
            }
            return try request.fetchAll(db)
        }
    }

    func pendingSync() throws -> [Defect] {
        try pendingSync(projectId: nil)
    }

    func pendingSync(projectId: String?) throws -> [Defect] {
        try dbPool.read { db in
            var request = Defect
                .filter(Defect.Columns.synced == false)
                .order(Defect.Columns.timestamp.asc)

            if let projectId {
                request = request.filter(Defect.Columns.projectId == projectId)
            }

            return try request.fetchAll(db)
        }
    }

    func markSynced(id: String, photoUrl: String?, bcfPath: String? = nil) throws {
        try dbPool.write { db in
            try db.execute(
                sql: "UPDATE defects SET synced = 1, photo_url = COALESCE(?, photo_url), bcf_path = COALESCE(?, bcf_path) WHERE id = ?",
                arguments: [photoUrl, bcfPath, id]
            )
        }
    }

    func markResolved(id: String, resolved: Bool = true) throws {
        try dbPool.write { db in
            try db.execute(
                sql: "UPDATE defects SET resolved = ?, synced = 0 WHERE id = ?",
                arguments: [resolved, id]
            )
        }
    }

    func count(projectId: String) throws -> Int {
        try dbPool.read { db in
            try Defect.filter(Defect.Columns.projectId == projectId).fetchCount(db)
        }
    }

    func deleteAll() throws {
        try dbPool.write { db in
            _ = try Defect.deleteAll(db)
        }
    }
}
