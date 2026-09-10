import Foundation
import Supabase

enum SupabaseConfigurationError: LocalizedError {
    case missingURL
    case invalidURL(String)
    case missingPublishableKey
    case privilegedKeyDetected

    var errorDescription: String? {
        switch self {
        case .missingURL:
            "Supabase URL is missing. Copy Config/Local.xcconfig.example to Config/Local.xcconfig and fill in SUPABASE_URL."
        case let .invalidURL(value):
            "Supabase URL is invalid: \(value)"
        case .missingPublishableKey:
            "Supabase publishable key is missing. Set SUPABASE_PUBLISHABLE_KEY in Config/Local.xcconfig."
        case .privilegedKeyDetected:
            "A privileged Supabase key was configured in the iOS client. Use only a publishable key."
        }
    }
}

struct SupabaseConfiguration: Sendable {
    let projectURL: URL
    let publishableKey: String

    init(bundle: Bundle = .main) throws {
        let rawURL = (bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawKey = (bundle.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !rawURL.isEmpty else {
            throw SupabaseConfigurationError.missingURL
        }

        guard let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased(),
              let host = url.host,
              scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1"].contains(host))
        else {
            throw SupabaseConfigurationError.invalidURL(rawURL)
        }

        guard !rawKey.isEmpty else {
            throw SupabaseConfigurationError.missingPublishableKey
        }

        let lowercasedKey = rawKey.lowercased()
        guard !lowercasedKey.contains("service_role"),
              !lowercasedKey.contains("secret")
        else {
            throw SupabaseConfigurationError.privilegedKeyDetected
        }

        projectURL = url
        publishableKey = rawKey
    }
}

enum SupabaseClientProvider {
    static func makeClient(bundle: Bundle = .main) throws -> SupabaseClient {
        let configuration = try SupabaseConfiguration(bundle: bundle)
        return SupabaseClient(
            supabaseURL: configuration.projectURL,
            supabaseKey: configuration.publishableKey
        )
    }
}
