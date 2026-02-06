import Foundation

// MARK: - System Prompt Cache

/// Actor that manages UserDefaults-based caching of system prompts
actor SystemPromptCache {

    /// Shared instance
    static let shared = SystemPromptCache()

    private let userDefaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        // Configure date encoding/decoding
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Cache Keys

    /// Generate cache key for a prompt type
    private func cacheKey(for type: SystemPromptType) -> String {
        "cached_system_prompts_\(type.rawValue)"
    }

    // MARK: - Cache Operations

    /// Get cached prompt for a type (returns nil if not cached or expired)
    func getCached(for type: SystemPromptType, allowStale: Bool = false) -> CachedSystemPrompt? {
        let key = cacheKey(for: type)

        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }

        do {
            let cached = try decoder.decode(CachedSystemPrompt.self, from: data)

            // Return nil if stale and stale not allowed
            if cached.isStale && !allowStale {
                return nil
            }

            return cached
        } catch {
            NSLog("[SystemPromptCache] Failed to decode cached prompt for \(type.rawValue): %@", error.localizedDescription)
            return nil
        }
    }

    /// Cache a system prompt template
    func cache(_ template: SystemPromptTemplate) {
        guard let type = template.systemPromptType else {
            NSLog("[SystemPromptCache] Cannot cache template with unknown type: %@", template.promptType)
            return
        }

        let key = cacheKey(for: type)
        let cached = CachedSystemPrompt(template: template)

        do {
            let data = try encoder.encode(cached)
            userDefaults.set(data, forKey: key)
            NSLog("[SystemPromptCache] Cached prompt for \(type.rawValue)")
        } catch {
            NSLog("[SystemPromptCache] Failed to cache prompt for \(type.rawValue): %@", error.localizedDescription)
        }
    }

    /// Clear cache for a specific type
    func clearCache(for type: SystemPromptType) {
        let key = cacheKey(for: type)
        userDefaults.removeObject(forKey: key)
        NSLog("[SystemPromptCache] Cleared cache for \(type.rawValue)")
    }

    /// Clear all cached prompts
    func clearAllCache() {
        for type in SystemPromptType.allCases {
            clearCache(for: type)
        }
        NSLog("[SystemPromptCache] Cleared all cached prompts")
    }

    /// Get template content from cache (convenience method)
    func getTemplateContent(for type: SystemPromptType, allowStale: Bool = false) -> String? {
        getCached(for: type, allowStale: allowStale)?.template.templateContent
    }
}
