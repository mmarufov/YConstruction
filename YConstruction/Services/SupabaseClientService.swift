import Foundation
import Supabase

struct SupabaseConfig: Sendable {
    let url: URL
    let anonKey: String
    let photosBucket: String
    let issuesBucket: String
    let projectsBucket: String

    var isConfigured: Bool {
        !url.absoluteString.contains("PLACEHOLDER") &&
        !anonKey.contains("PLACEHOLDER")
    }

    static let placeholder = SupabaseConfig(
        url: URL(string: "https://PLACEHOLDER.supabase.co")!,
        anonKey: "PLACEHOLDER_ANON_KEY",
        photosBucket: "photos",
        issuesBucket: "issues",
        projectsBucket: "projects"
    )

    static func load(bundle: Bundle = .main) -> SupabaseConfig {
        guard let url = bundle.url(forResource: "SupabaseConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let supaUrlString = plist["SUPABASE_URL"] as? String,
              let supaUrl = URL(string: supaUrlString),
              let anonKey = plist["SUPABASE_ANON_KEY"] as? String
        else {
            return .placeholder
        }
        return SupabaseConfig(
            url: supaUrl,
            anonKey: anonKey,
            photosBucket: (plist["PHOTOS_BUCKET"] as? String) ?? "photos",
            issuesBucket: (plist["ISSUES_BUCKET"] as? String) ?? "issues",
            projectsBucket: (plist["PROJECTS_BUCKET"] as? String) ?? "projects"
        )
    }
}

@MainActor
final class SupabaseClientService {
    static let shared = SupabaseClientService()

    let config: SupabaseConfig
    private var cachedClient: SupabaseClient?

    var isConfigured: Bool { config.isConfigured }

    init(config: SupabaseConfig = .load()) {
        self.config = config
    }

    func client() -> SupabaseClient? {
        if let cachedClient { return cachedClient }
        guard config.isConfigured else { return nil }
        let c = SupabaseClient(supabaseURL: config.url, supabaseKey: config.anonKey)
        cachedClient = c
        return c
    }
}
