import Foundation

// MARK: - System Prompt Service

/// Service for fetching and managing system prompt templates
/// Coordinates between Supabase, local cache, and bundled fallbacks
actor SystemPromptService {

    /// Shared instance
    static let shared = SystemPromptService()

    private let cache = SystemPromptCache.shared

    private init() {}

    // MARK: - Public API

    /// Get system prompt template content for a given type
    /// Fallback chain: Cache (if fresh) -> Supabase -> Cache (stale) -> Bundled ASP1Template
    /// - Parameters:
    ///   - type: The system prompt type (ASP, CSP, RSP)
    ///   - forceRefresh: If true, skip fresh cache and fetch from Supabase
    /// - Returns: The template content string
    func getTemplate(for type: SystemPromptType, forceRefresh: Bool = false) async -> String {
        // 1. Check fresh cache (unless forcing refresh)
        if !forceRefresh {
            if let content = await cache.getTemplateContent(for: type, allowStale: false) {
                NSLog("[SystemPromptService] Using fresh cached template for \(type.rawValue)")
                return content
            }
        }

        // 2. Try to fetch from Supabase
        do {
            let template = try await fetchFromSupabase(type: type)

            // Cache the result
            await cache.cache(template)

            NSLog("[SystemPromptService] Fetched and cached template from Supabase for \(type.rawValue)")
            return template.templateContent

        } catch {
            NSLog("[SystemPromptService] Supabase fetch failed for \(type.rawValue): %@", error.localizedDescription)

            // 3. Fall back to stale cache
            if let content = await cache.getTemplateContent(for: type, allowStale: true) {
                NSLog("[SystemPromptService] Using stale cached template for \(type.rawValue)")
                return content
            }

            // 4. Fall back to bundled template
            NSLog("[SystemPromptService] Using bundled ASP1Template fallback for \(type.rawValue)")
            return ASP1Template.content
        }
    }

    /// Prefetch all system prompt types into cache
    func prefetchAllTemplates() async {
        for type in SystemPromptType.allCases {
            _ = await getTemplate(for: type, forceRefresh: false)
        }
        NSLog("[SystemPromptService] Prefetched all template types")
    }

    /// Force refresh a specific template from Supabase
    func refreshTemplate(for type: SystemPromptType) async -> String {
        await getTemplate(for: type, forceRefresh: true)
    }

    /// Clear all cached templates
    func clearCache() async {
        await cache.clearAllCache()
    }

    // MARK: - Private Methods

    /// Fetch active system prompt from Supabase
    private func fetchFromSupabase(type: SystemPromptType) async throws -> SystemPromptTemplate {
        // Check if Supabase is configured
        guard SupabaseConfig.shared != nil else {
            throw SystemPromptServiceError.supabaseNotConfigured
        }

        let service = try SupabaseService()
        return try await service.fetchActiveSystemPrompt(type: type)
    }
}

// MARK: - Errors

enum SystemPromptServiceError: LocalizedError {
    case supabaseNotConfigured
    case templateNotFound(SystemPromptType)
    case fetchFailed(String)

    var errorDescription: String? {
        switch self {
        case .supabaseNotConfigured:
            return "Supabase is not configured"
        case .templateNotFound(let type):
            return "No active template found for type: \(type.rawValue)"
        case .fetchFailed(let message):
            return "Failed to fetch template: \(message)"
        }
    }
}
