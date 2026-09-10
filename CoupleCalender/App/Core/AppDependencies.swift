import Foundation

struct AppDependencies {
    let supabaseDataService: SupabaseDataService?
    let configurationError: SupabaseConfigurationError?

    init(bundle: Bundle = .main) {
        do {
            supabaseDataService = SupabaseDataService(
                client: try SupabaseClientProvider.makeClient(bundle: bundle)
            )
            configurationError = nil
        } catch let error as SupabaseConfigurationError {
            supabaseDataService = nil
            configurationError = error
        } catch {
            supabaseDataService = nil
            configurationError = .invalidURL(error.localizedDescription)
        }
    }
}
