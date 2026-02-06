import Foundation

// MARK: - Multi-Source Augmentation Service

/// Service for processing multiple sources and merging results with deduplication
actor MultiSourceAugmentationService {
    private let openAIApiKey: String
    private let assemblyAIApiKey: String?
    private let contextBuilder: TranscriptContextBuilder

    init(openAIApiKey: String, assemblyAIApiKey: String? = nil) {
        self.openAIApiKey = openAIApiKey
        self.assemblyAIApiKey = assemblyAIApiKey
        self.contextBuilder = TranscriptContextBuilder()
    }

    // MARK: - Process Multiple Sources

    /// Process multiple sources and merge results
    /// - Parameters:
    ///   - character: The character to augment
    ///   - sources: Array of brain sources to process
    ///   - onSourceProgress: Callback for per-source progress updates
    ///   - onOverallProgress: Callback for overall progress updates
    /// - Returns: Merged augmentation result with deduplication applied
    func processMultipleSources(
        character: Character,
        sources: [BrainSource],
        onSourceProgress: @escaping @Sendable (UUID, String) -> Void,
        onOverallProgress: @escaping @Sendable (String) -> Void
    ) async throws -> (results: [UUID: AugmentationAnalysisResult], merged: MergedAugmentationResult) {
        var results: [UUID: AugmentationAnalysisResult] = [:]

        let augmentationService = AugmentationService(
            openAIApiKey: openAIApiKey,
            assemblyAIApiKey: assemblyAIApiKey
        )

        // Process each source
        for (index, source) in sources.enumerated() {
            onOverallProgress("Processing source \(index + 1) of \(sources.count)")
            onSourceProgress(source.id, "Starting...")

            do {
                let result = try await processSource(
                    source,
                    character: character,
                    using: augmentationService,
                    onProgress: { message in
                        onSourceProgress(source.id, message)
                    }
                )

                results[source.id] = result
                onSourceProgress(source.id, "Complete")

            } catch {
                onSourceProgress(source.id, "Failed: \(error.localizedDescription)")
                throw error
            }
        }

        // Merge all results
        onOverallProgress("Merging results...")
        let merged = mergeResults(Array(results.values), sourceIds: Array(results.keys))

        return (results, merged)
    }

    // MARK: - Process Single Source (Incremental)

    /// Process a single source incrementally, merging with existing results
    /// - Parameters:
    ///   - source: The source to process
    ///   - character: The character to augment
    ///   - existingResults: Optional existing merged results to add to
    ///   - onProgress: Progress callback
    /// - Returns: Updated merged result
    func processSingleSource(
        _ source: BrainSource,
        character: Character,
        existingResults: MergedAugmentationResult?,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> MergedAugmentationResult {
        let augmentationService = AugmentationService(
            openAIApiKey: openAIApiKey,
            assemblyAIApiKey: assemblyAIApiKey
        )

        let result = try await processSource(
            source,
            character: character,
            using: augmentationService,
            onProgress: onProgress
        )

        // Merge with existing or create new
        if var existing = existingResults {
            return mergeSingleResult(result, sourceId: source.id, into: &existing)
        } else {
            return mergeResults([result], sourceIds: [source.id])
        }
    }

    // MARK: - Private Processing

    private func processSource(
        _ source: BrainSource,
        character: Character,
        using service: AugmentationService,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> AugmentationAnalysisResult {
        switch source.sourceType {
        case .youtubeVideo:
            return try await service.processYouTubeVideo(
                character: character,
                videoURL: source.content,
                onProgress: onProgress
            )

        case .webLink:
            return try await service.processWebLink(
                character: character,
                url: source.content,
                onProgress: onProgress
            )

        case .rawTranscript, .freeformText:
            return try await service.analyzeForAugmentation(
                character: character,
                sourceType: source.sourceType == .rawTranscript ? .text : .text,
                content: source.content,
                sourceTitle: source.label,
                onProgress: onProgress
            )
        }
    }

    // MARK: - Merge Results

    /// Merge results from multiple sources, deduping by confidence
    func mergeResults(
        _ results: [AugmentationAnalysisResult],
        sourceIds: [UUID]
    ) -> MergedAugmentationResult {
        var allAugmentations: [PersonaAugmentation] = []
        var allRagEntries: [AugmentationKnowledgeEntry] = []
        var contributions: [UUID: SourceContribution] = [:]
        var duplicatesRemoved = 0

        for (index, result) in results.enumerated() {
            let sourceId = sourceIds[index]

            // Add augmentations, checking for duplicates
            var sourceAugmentationIds: [UUID] = []
            for augmentation in result.augmentations {
                if let existingIndex = findSimilarAugmentation(augmentation, in: allAugmentations) {
                    // Keep the one with higher confidence
                    if augmentation.confidence > allAugmentations[existingIndex].confidence {
                        allAugmentations[existingIndex] = augmentation
                        sourceAugmentationIds.append(augmentation.id)
                    }
                    duplicatesRemoved += 1
                } else {
                    allAugmentations.append(augmentation)
                    sourceAugmentationIds.append(augmentation.id)
                }
            }

            // Add RAG entries (dedupe by content similarity)
            var sourceRagIds: [String] = []
            for entry in result.ragEntries {
                if !hasSimilarRagEntry(entry, in: allRagEntries) {
                    allRagEntries.append(entry)
                    sourceRagIds.append(entry.id)
                } else {
                    duplicatesRemoved += 1
                }
            }

            // Record contribution
            contributions[sourceId] = SourceContribution(
                sourceId: sourceId,
                sourceLabel: result.sourceTitle,
                augmentationIds: sourceAugmentationIds,
                ragEntryIds: sourceRagIds,
                processedAt: Date()
            )
        }

        return MergedAugmentationResult(
            allAugmentations: allAugmentations,
            allRagEntries: allRagEntries,
            sourceContributions: contributions,
            duplicatesRemoved: duplicatesRemoved
        )
    }

    /// Merge a single result into existing merged results
    private func mergeSingleResult(
        _ result: AugmentationAnalysisResult,
        sourceId: UUID,
        into existing: inout MergedAugmentationResult
    ) -> MergedAugmentationResult {
        var newAugmentations = existing.allAugmentations
        var newRagEntries = existing.allRagEntries
        var newContributions = existing.sourceContributions
        var totalDupes = existing.duplicatesRemoved

        var sourceAugmentationIds: [UUID] = []
        for augmentation in result.augmentations {
            if let existingIndex = findSimilarAugmentation(augmentation, in: newAugmentations) {
                if augmentation.confidence > newAugmentations[existingIndex].confidence {
                    newAugmentations[existingIndex] = augmentation
                    sourceAugmentationIds.append(augmentation.id)
                }
                totalDupes += 1
            } else {
                newAugmentations.append(augmentation)
                sourceAugmentationIds.append(augmentation.id)
            }
        }

        var sourceRagIds: [String] = []
        for entry in result.ragEntries {
            if !hasSimilarRagEntry(entry, in: newRagEntries) {
                newRagEntries.append(entry)
                sourceRagIds.append(entry.id)
            } else {
                totalDupes += 1
            }
        }

        newContributions[sourceId] = SourceContribution(
            sourceId: sourceId,
            sourceLabel: result.sourceTitle,
            augmentationIds: sourceAugmentationIds,
            ragEntryIds: sourceRagIds,
            processedAt: Date()
        )

        return MergedAugmentationResult(
            allAugmentations: newAugmentations,
            allRagEntries: newRagEntries,
            sourceContributions: newContributions,
            duplicatesRemoved: totalDupes
        )
    }

    // MARK: - Deduplication Helpers

    /// Find similar augmentation by comparing section and content
    private func findSimilarAugmentation(
        _ augmentation: PersonaAugmentation,
        in existing: [PersonaAugmentation]
    ) -> Int? {
        for (index, existing) in existing.enumerated() {
            if existing.section == augmentation.section {
                // Same section - check content similarity
                let similarity = contentSimilarity(existing.suggestedAddition, augmentation.suggestedAddition)
                if similarity > 0.8 {
                    return index
                }
            }
        }
        return nil
    }

    /// Check if a similar RAG entry exists
    private func hasSimilarRagEntry(
        _ entry: AugmentationKnowledgeEntry,
        in existing: [AugmentationKnowledgeEntry]
    ) -> Bool {
        for existingEntry in existing {
            let similarity = contentSimilarity(existingEntry.content, entry.content)
            if similarity > 0.85 {
                return true
            }
        }
        return false
    }

    /// Simple content similarity using Jaccard index on words
    private func contentSimilarity(_ text1: String, _ text2: String) -> Double {
        let words1 = Set(text1.lowercased().components(separatedBy: .whitespaces).filter { $0.count > 2 })
        let words2 = Set(text2.lowercased().components(separatedBy: .whitespaces).filter { $0.count > 2 })

        guard !words1.isEmpty || !words2.isEmpty else { return 0 }

        let intersection = words1.intersection(words2).count
        let union = words1.union(words2).count

        return Double(intersection) / Double(union)
    }
}
