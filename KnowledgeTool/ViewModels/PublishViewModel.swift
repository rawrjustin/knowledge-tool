import Foundation
import CryptoKit

// MARK: - Publish State

enum PublishState: Equatable {
    case unpublished
    case clean(configId: String, publishedAt: String)
    case dirtyEdits(configId: String, publishedAt: String)
}

// MARK: - Publish ViewModel

@Observable
@MainActor
final class PublishViewModel {
    var isPublishing = false
    var publishError: String?
    var publishState: PublishState = .unpublished
    var configId: String?
    var publishedAt: String?

    private let geniesService = GeniesPersonaService.shared

    // MARK: - Load State

    func loadPublishState(for character: Character, repository: CombinedCharacterRepository) async {
        let metadata = await repository.loadPublishMetadata(characterName: character.name)

        guard let storedConfigId = metadata?.configId else {
            publishState = .unpublished
            configId = nil
            publishedAt = nil
            return
        }

        configId = storedConfigId
        publishedAt = metadata?.publishedAt

        let currentSha = Self.contentSha(for: character)
        if currentSha == metadata?.publishedSha {
            publishState = .clean(configId: storedConfigId, publishedAt: metadata?.publishedAt ?? "")
        } else {
            publishState = .dirtyEdits(configId: storedConfigId, publishedAt: metadata?.publishedAt ?? "")
        }
    }

    // MARK: - Publish (Create New)

    func publish(character: Character, overrides: GeniesConfigOverrides, repository: CombinedCharacterRepository) async {
        isPublishing = true
        publishError = nil

        do {
            let orgId = try await getOrgId()
            let config = GeniesCharacterConfig.from(character: character, overrides: overrides)
            let configName = "[\(character.systemPromptType.shortDisplayName)] \(character.name)"

            let response = try await geniesService.createConfig(
                name: configName,
                config: config,
                orgId: orgId
            )

            let sha = Self.contentSha(for: character)
            let now = ISO8601DateFormatter().string(from: Date())

            await repository.savePublishMetadata(
                configId: response.id,
                sha: sha,
                publishedAt: now,
                characterName: character.name
            )

            configId = response.id
            publishedAt = now
            publishState = .clean(configId: response.id, publishedAt: now)

            NSLog("[PublishViewModel] Published config: %@ → %@", configName, response.id)
        } catch {
            publishError = error.localizedDescription
            NSLog("[PublishViewModel] Publish failed: %@", error.localizedDescription)
        }

        isPublishing = false
    }

    // MARK: - Update Existing

    func update(character: Character, overrides: GeniesConfigOverrides, repository: CombinedCharacterRepository) async {
        guard let existingConfigId = configId else {
            publishError = "No existing config to update"
            return
        }

        isPublishing = true
        publishError = nil

        do {
            let config = GeniesCharacterConfig.from(character: character, overrides: overrides)
            let configName = "[\(character.systemPromptType.shortDisplayName)] \(character.name)"

            try await geniesService.updateConfig(
                configId: existingConfigId,
                name: configName,
                config: config
            )

            let sha = Self.contentSha(for: character)
            let now = ISO8601DateFormatter().string(from: Date())

            await repository.savePublishMetadata(
                configId: existingConfigId,
                sha: sha,
                publishedAt: now,
                characterName: character.name
            )

            publishedAt = now
            publishState = .clean(configId: existingConfigId, publishedAt: now)

            NSLog("[PublishViewModel] Updated config: %@", existingConfigId)
        } catch {
            publishError = error.localizedDescription
            NSLog("[PublishViewModel] Update failed: %@", error.localizedDescription)
        }

        isPublishing = false
    }

    // MARK: - Link to Existing

    func linkToExisting(character: Character, existingConfigId: String, repository: CombinedCharacterRepository) async {
        isPublishing = true
        publishError = nil

        do {
            // Verify the config exists
            _ = try await geniesService.getConfig(configId: existingConfigId)

            let sha = Self.contentSha(for: character)
            let now = ISO8601DateFormatter().string(from: Date())

            await repository.savePublishMetadata(
                configId: existingConfigId,
                sha: sha,
                publishedAt: now,
                characterName: character.name
            )

            configId = existingConfigId
            publishedAt = now
            publishState = .clean(configId: existingConfigId, publishedAt: now)

            NSLog("[PublishViewModel] Linked to existing config: %@", existingConfigId)
        } catch {
            publishError = "Failed to link: \(error.localizedDescription)"
        }

        isPublishing = false
    }

    // MARK: - Helpers

    var isPublished: Bool {
        configId != nil
    }

    private func getOrgId() async throws -> String {
        guard let orgId = await AuthService.shared.getStoredOrganizationId(), !orgId.isEmpty else {
            throw GeniesAPIError.unauthorized
        }
        return orgId
    }

    static func contentSha(for character: Character) -> String {
        let content = character.markdownContent + character.name + character.systemPromptType.rawValue
        let data = Data(content.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
