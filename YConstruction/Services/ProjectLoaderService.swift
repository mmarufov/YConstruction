import Foundation
import Supabase

struct ProjectBundle: Sendable {
    let glbURL: URL
    let elementIndexURL: URL
    let source: Source

    enum Source: String, Sendable {
        case cache
        case supabase
        case bundle
    }
}

enum ProjectLoaderError: Error, LocalizedError {
    case noSource(String)

    var errorDescription: String? {
        switch self {
        case .noSource(let msg): return msg
        }
    }
}

struct ProjectLoaderService: Sendable {
    let projectId: String
    let supabase: SupabaseClientService

    init(projectId: String, supabase: SupabaseClientService = SupabaseClientService.shared) {
        self.projectId = projectId
        self.supabase = supabase
    }

    func load() async throws -> ProjectBundle {
        if let bundle = try? localCache() {
            return bundle
        }

        if let bundle = try? await fromSupabase() {
            return bundle
        }

        if projectId == AppConfig.demoProjectId, let bundle = bundledDemo() {
            return bundle
        }

        throw ProjectLoaderError.noSource("No project bundle available for \(projectId)")
    }

    private func localCache() throws -> ProjectBundle {
        let projectDir = try AppConfig.projectDirectory(projectId: projectId)
        let glb = projectDir.appendingPathComponent("duplex.glb")
        let idx = projectDir.appendingPathComponent("element_index.json")
        guard FileManager.default.fileExists(atPath: glb.path),
              FileManager.default.fileExists(atPath: idx.path) else {
            throw ProjectLoaderError.noSource("no cache")
        }
        return ProjectBundle(glbURL: glb, elementIndexURL: idx, source: .cache)
    }

    private func fromSupabase() async throws -> ProjectBundle {
        guard let client = supabase.client() else {
            throw ProjectLoaderError.noSource("supabase not configured")
        }
        let bucket = supabase.config.projectsBucket
        let projectDir = try AppConfig.projectDirectory(projectId: projectId)
        let glbRemote = "\(projectId)/duplex.glb"
        let idxRemote = "\(projectId)/element_index.json"

        let glbURL = try client.storage.from(bucket).getPublicURL(path: glbRemote)
        let idxURL = try client.storage.from(bucket).getPublicURL(path: idxRemote)

        let glbData = try await fetch(glbURL)
        let idxData = try await fetch(idxURL)

        let glbLocal = projectDir.appendingPathComponent("duplex.glb")
        let idxLocal = projectDir.appendingPathComponent("element_index.json")
        try glbData.write(to: glbLocal, options: .atomic)
        try idxData.write(to: idxLocal, options: .atomic)
        return ProjectBundle(glbURL: glbLocal, elementIndexURL: idxLocal, source: .supabase)
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
