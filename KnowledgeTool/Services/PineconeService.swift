import Foundation

/// Service for uploading character knowledge to Pinecone for RAG retrieval
actor PineconeService {
    private let apiKey: String
    private let openAIApiKey: String
    private var indexName: String
    private let baseURL = "https://api.pinecone.io"

    // Embedding settings
    private let embedModel = "text-embedding-3-large"
    private let embedDimensions = 256

    init(apiKey: String, openAIApiKey: String, indexName: String) {
        self.apiKey = apiKey
        self.openAIApiKey = openAIApiKey
        self.indexName = indexName
    }

    func updateIndexName(_ name: String) {
        self.indexName = name
    }

    // MARK: - Public API

    /// Upload knowledge documents to Pinecone
    func uploadKnowledge(
        documents: [KnowledgeDocument],
        namespace: String,
        clearExisting: Bool = false,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> UploadResult {
        // Get index host
        onProgress("Connecting to Pinecone...")
        let indexHost = try await getIndexHost()

        // Clear existing if requested
        if clearExisting {
            onProgress("Clearing existing vectors in namespace...")
            try await deleteNamespace(host: indexHost, namespace: namespace)
        }

        // Generate embeddings
        onProgress("Generating embeddings for \(documents.count) documents...")
        let embeddings = try await generateEmbeddings(for: documents, onProgress: onProgress)

        // Prepare vectors
        onProgress("Preparing vectors for upload...")
        var vectors: [[String: Any]] = []
        for (index, doc) in documents.enumerated() {
            let vector: [String: Any] = [
                "id": "\(namespace)_\(index)",
                "values": embeddings[index],
                "metadata": [
                    "content": doc.content,
                    "source": doc.source,
                    "section": doc.section ?? "",
                    "keywords": doc.keywords ?? [],
                    "format": doc.format
                ]
            ]
            vectors.append(vector)
        }

        // Upload in batches of 100
        let batchSize = 100
        var uploadedCount = 0

        for batchStart in stride(from: 0, to: vectors.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, vectors.count)
            let batch = Array(vectors[batchStart..<batchEnd])

            onProgress("Uploading batch \(batchStart/batchSize + 1) of \((vectors.count + batchSize - 1)/batchSize)...")

            try await upsertVectors(host: indexHost, vectors: batch, namespace: namespace)
            uploadedCount += batch.count
        }

        onProgress("Successfully uploaded \(uploadedCount) documents to Pinecone")

        return UploadResult(
            documentsUploaded: uploadedCount,
            namespace: namespace,
            indexName: indexName
        )
    }

    /// List record IDs in a namespace
    func listNamespaceRecords(namespace: String, limit: Int = 100) async throws -> [String] {
        let indexHost = try await getIndexHost()

        var urlComponents = URLComponents(string: "https://\(indexHost)/vectors/list")!
        urlComponents.queryItems = [
            URLQueryItem(name: "namespace", value: namespace),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PineconeError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PineconeError.apiError("List failed: \(errorBody)")
        }

        struct ListResponse: Decodable {
            let vectors: [VectorRef]?
            struct VectorRef: Decodable {
                let id: String
            }
        }

        let listResponse = try JSONDecoder().decode(ListResponse.self, from: data)
        return listResponse.vectors?.map { $0.id } ?? []
    }

    /// Fetch all memory IDs from a namespace using pagination
    func fetchAllMemoryIds(
        namespace: String,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> Set<String> {
        let indexHost = try await getIndexHost()
        var allIds: Set<String> = []
        var paginationToken: String? = nil
        var pageCount = 0

        repeat {
            pageCount += 1
            onProgress("Fetching page \(pageCount)...")

            var urlComponents = URLComponents(string: "https://\(indexHost)/vectors/list")!
            var queryItems = [
                URLQueryItem(name: "namespace", value: namespace),
                URLQueryItem(name: "limit", value: "100")
            ]
            if let token = paginationToken {
                queryItems.append(URLQueryItem(name: "paginationToken", value: token))
            }
            urlComponents.queryItems = queryItems

            var request = URLRequest(url: urlComponents.url!)
            request.httpMethod = "GET"
            request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw PineconeError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw PineconeError.apiError("List failed: \(errorBody)")
            }

            struct ListResponse: Decodable {
                let vectors: [VectorRef]?
                let pagination: Pagination?
                struct VectorRef: Decodable {
                    let id: String
                }
                struct Pagination: Decodable {
                    let next: String?
                }
            }

            let listResponse = try JSONDecoder().decode(ListResponse.self, from: data)

            if let vectors = listResponse.vectors {
                for vector in vectors {
                    allIds.insert(vector.id)
                }
            }

            paginationToken = listResponse.pagination?.next
        } while paginationToken != nil

        onProgress("Found \(allIds.count) vectors in Pinecone")
        return allIds
    }

    /// Get namespace statistics
    func getNamespaceStats(namespace: String) async throws -> NamespaceStats {
        let indexHost = try await getIndexHost()

        var request = URLRequest(url: URL(string: "https://\(indexHost)/describe_index_stats")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [:])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PineconeError.apiError("Failed to get stats")
        }

        struct StatsResponse: Decodable {
            let namespaces: [String: NamespaceInfo]?
            let totalVectorCount: Int?

            struct NamespaceInfo: Decodable {
                let vectorCount: Int?
            }
        }

        let stats = try JSONDecoder().decode(StatsResponse.self, from: data)
        let vectorCount = stats.namespaces?[namespace]?.vectorCount ?? 0

        return NamespaceStats(
            namespace: namespace,
            vectorCount: vectorCount
        )
    }

    // MARK: - Private Methods

    private func getIndexHost() async throws -> String {
        var request = URLRequest(url: URL(string: "\(baseURL)/indexes/\(indexName)")!)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PineconeError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PineconeError.apiError("Failed to get index info: \(errorBody)")
        }

        struct IndexInfo: Decodable {
            let host: String
        }

        let indexInfo = try JSONDecoder().decode(IndexInfo.self, from: data)
        return indexInfo.host
    }

    private func deleteNamespace(host: String, namespace: String) async throws {
        var request = URLRequest(url: URL(string: "https://\(host)/vectors/delete")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "deleteAll": true,
            "namespace": namespace
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PineconeError.apiError("Failed to delete namespace")
        }
    }

    private func generateEmbeddings(
        for documents: [KnowledgeDocument],
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> [[Float]] {
        let batchSize = 100
        var allEmbeddings: [[Float]] = []

        for batchStart in stride(from: 0, to: documents.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, documents.count)
            let batch = Array(documents[batchStart..<batchEnd])
            let texts = batch.map { $0.content }

            onProgress("Embedding batch \(batchStart/batchSize + 1)...")

            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/embeddings")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(openAIApiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = [
                "model": embedModel,
                "input": texts,
                "dimensions": embedDimensions
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw PineconeError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw PineconeError.apiError("Embedding failed: \(errorBody)")
            }

            struct EmbeddingResponse: Decodable {
                let data: [EmbeddingData]
                struct EmbeddingData: Decodable {
                    let embedding: [Float]
                }
            }

            let embeddingResponse = try JSONDecoder().decode(EmbeddingResponse.self, from: data)
            let embeddings = embeddingResponse.data.map { $0.embedding }
            allEmbeddings.append(contentsOf: embeddings)
        }

        return allEmbeddings
    }

    private func upsertVectors(host: String, vectors: [[String: Any]], namespace: String) async throws {
        var request = URLRequest(url: URL(string: "https://\(host)/vectors/upsert")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "vectors": vectors,
            "namespace": namespace
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PineconeError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PineconeError.apiError("Upsert failed: \(errorBody)")
        }
    }

    // MARK: - Types

    struct KnowledgeDocument {
        let content: String
        let source: String
        let section: String?
        let keywords: [String]?
        let format: String  // "character_memory" or "video_knowledge"
    }

    struct UploadResult {
        let documentsUploaded: Int
        let namespace: String
        let indexName: String
    }

    struct NamespaceStats {
        let namespace: String
        let vectorCount: Int
    }
}

// MARK: - Errors

enum PineconeError: LocalizedError {
    case invalidResponse
    case apiError(String)
    case noDocuments

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Pinecone"
        case .apiError(let message):
            return message
        case .noDocuments:
            return "No documents to upload"
        }
    }
}

// MARK: - Knowledge Document Parsing

extension PineconeService {
    /// Parse JSONL file into knowledge documents
    static func parseJSONLFile(at url: URL) throws -> [KnowledgeDocument] {
        let content = try String(contentsOf: url, encoding: .utf8)
        var documents: [KnowledgeDocument] = []

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            guard let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // Character memory format
            if let contentText = json["content"] as? String {
                let doc = KnowledgeDocument(
                    content: contentText,
                    source: url.lastPathComponent,
                    section: json["section"] as? String,
                    keywords: json["keywords"] as? [String],
                    format: "character_memory"
                )
                documents.append(doc)
            }
            // Video knowledge format
            else if let text = json["text"] as? String {
                let doc = KnowledgeDocument(
                    content: text,
                    source: url.lastPathComponent,
                    section: json["chunk_summary"] as? String,
                    keywords: json["tags"] as? [String],
                    format: "video_knowledge"
                )
                documents.append(doc)
            }
        }

        return documents
    }

    /// Parse all knowledge files for a character
    static func parseCharacterKnowledge(knowledgeFiles: [KnowledgeFile]) throws -> [KnowledgeDocument] {
        var documents: [KnowledgeDocument] = []

        for file in knowledgeFiles {
            // Only process JSONL files
            guard file.fileName.hasSuffix(".jsonl") else { continue }

            let lines = file.content.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }

                guard let data = trimmed.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }

                // Character memory format
                if let contentText = json["content"] as? String {
                    let doc = KnowledgeDocument(
                        content: contentText,
                        source: file.fileName,
                        section: json["section"] as? String,
                        keywords: json["keywords"] as? [String],
                        format: "character_memory"
                    )
                    documents.append(doc)
                }
                // Video knowledge format
                else if let text = json["text"] as? String {
                    let doc = KnowledgeDocument(
                        content: text,
                        source: file.fileName,
                        section: json["chunk_summary"] as? String,
                        keywords: json["tags"] as? [String],
                        format: "video_knowledge"
                    )
                    documents.append(doc)
                }
            }
        }

        return documents
    }
}
