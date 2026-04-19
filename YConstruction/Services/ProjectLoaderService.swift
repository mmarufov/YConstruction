import Foundation
import Supabase

nonisolated struct ProjectBundle: Sendable {
    let glbURL: URL
    let elementIndexURL: URL
    let source: Source

    enum Source: String, Sendable {
        case cache
        case supabase
        case bundle
    }
}

nonisolated enum ProjectLoaderError: Error, LocalizedError {
    case noSource(String)

    var errorDescription: String? {
        switch self {
        case .noSource(let msg): return msg
        }
    }
}

nonisolated struct ProjectLoaderService: Sendable {
    let projectId: String
    let supabase: SupabaseClientService

    init(projectId: String, supabase: SupabaseClientService = SupabaseClientService.shared) {
        self.projectId = projectId
        self.supabase = supabase
    }

    func load() async throws -> ProjectBundle {
        if let client = supabase.client(),
           let manifest = try? await fetchManifest(client: client) {
            if let bundle = try? localCache(matching: manifest) {
                return bundle
            }
            return try await fromSupabase(client: client, manifest: manifest)
        }

        if let bundle = try? localCache(matching: nil) {
            return bundle
        }

        throw ProjectLoaderError.noSource("No project bundle available for \(projectId)")
    }

    private func localCache(matching manifest: ProjectManifest?) throws -> ProjectBundle {
        let projectDir = try AppConfig.projectDirectory(projectId: projectId)
        let glb = projectDir.appendingPathComponent("duplex.glb")
        let idx = projectDir.appendingPathComponent("element_index.json")
        let meta = projectDir.appendingPathComponent("cache_meta.json")
        guard FileManager.default.fileExists(atPath: glb.path),
              FileManager.default.fileExists(atPath: idx.path) else {
            throw ProjectLoaderError.noSource("no cache")
        }
        let idxData = try Data(contentsOf: idx)
        _ = try JSONDecoder().decode(ElementIndex.self, from: idxData)
        if let manifest {
            guard FileManager.default.fileExists(atPath: meta.path) else {
                throw ProjectLoaderError.noSource("cache missing meta")
            }
            let cached = try JSONDecoder().decode(CacheMeta.self, from: try Data(contentsOf: meta))
            guard cached.updatedAt == manifest.updatedAt else {
                throw ProjectLoaderError.noSource("cache stale")
            }
        }
        return ProjectBundle(glbURL: glb, elementIndexURL: idx, source: .cache)
    }

    private struct ProjectManifest: Decodable {
        let id: String
        let name: String
        let modelPath: String
        let elementIndexPath: String?
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case modelPath = "model_path"
            case elementIndexPath = "element_index_path"
            case updatedAt = "updated_at"
        }
    }

    private struct CacheMeta: Codable {
        let updatedAt: String
    }

    private func emptyElementIndexData() -> Data {
        let escaped = projectId
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let json = """
        {"project_id":"\(escaped)","schema":"1.0","storeys":[{"name":"Ground","elevation":0.0,"height_range":[0.0,10.0]}],"elements":{}}
        """
        return Data(json.utf8)
    }

    private func fromSupabase(client: SupabaseClient, manifest: ProjectManifest) async throws -> ProjectBundle {
        let bucket = supabase.config.projectsBucket
        let projectDir = try AppConfig.projectDirectory(projectId: projectId)

        let glbURL = try client.storage.from(bucket).getPublicURL(path: manifest.modelPath)
        let glbData = try await fetch(glbURL)
        let glbLocal = projectDir.appendingPathComponent("duplex.glb")
        try glbData.write(to: glbLocal, options: .atomic)

        let idxLocal = projectDir.appendingPathComponent("element_index.json")
        if let idxRemote = manifest.elementIndexPath {
            let idxURL = try client.storage.from(bucket).getPublicURL(path: idxRemote)
            let idxData = try await fetch(idxURL)
            try idxData.write(to: idxLocal, options: .atomic)
        } else {
            try emptyElementIndexData().write(to: idxLocal, options: .atomic)
        }

        let metaLocal = projectDir.appendingPathComponent("cache_meta.json")
        let metaData = try JSONEncoder().encode(CacheMeta(updatedAt: manifest.updatedAt))
        try metaData.write(to: metaLocal, options: .atomic)

        return ProjectBundle(glbURL: glbLocal, elementIndexURL: idxLocal, source: .supabase)
    }

    private func fetchManifest(client: SupabaseClient) async throws -> ProjectManifest {
        let rows: [ProjectManifest] = try await client
            .from("projects")
            .select()
            .eq("id", value: projectId)
            .limit(1)
            .execute()
            .value
        guard let manifest = rows.first else {
            throw ProjectLoaderError.noSource("no manifest for \(projectId)")
        }
        return manifest
    }

    private func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw ProjectLoaderError.noSource("HTTP \(http.statusCode) from \(url.absoluteString)")
        }
        return data
    }

    private func bundledDemo() -> ProjectBundle? {
        let glb = Bundle.main.url(forResource: "duplex", withExtension: "glb", subdirectory: "DemoProject")
            ?? Bundle.main.url(forResource: "duplex", withExtension: "glb")
        let idx = Bundle.main.url(forResource: "element_index", withExtension: "json", subdirectory: "DemoProject")
            ?? Bundle.main.url(forResource: "element_index", withExtension: "json")
        guard let glb, let idx else { return nil }
        return ProjectBundle(glbURL: glb, elementIndexURL: idx, source: .bundle)
    }
}
