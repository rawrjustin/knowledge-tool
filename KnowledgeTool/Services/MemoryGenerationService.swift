import Foundation

/// Service for generating retrieval-optimized memories from character personas
actor MemoryGenerationService {
    private let openAIApiKey: String
    private let model = "gpt-5"

    init(openAIApiKey: String) {
        self.openAIApiKey = openAIApiKey
    }

    // MARK: - Public API

    /// Generate memories from free-form text content
    func generateMemoriesFromText(
        characterName: String,
        text: String,
        sourceLabel: String,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> [MemoryEntry] {
        onProgress("Processing text for \(characterName)...")

        let prompt = buildTextPrompt(characterName: characterName, sourceLabel: sourceLabel)

        onProgress("Generating retrieval-optimized memories...")

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(openAIApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": text]
            ],
            "max_tokens": 8000
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MemoryGenerationError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw MemoryGenerationError.apiError("OpenAI error: \(errorBody)")
        }

        struct ChatResponse: Decodable {
            let choices: [Choice]
            struct Choice: Decodable {
                let message: Message
            }
            struct Message: Decodable {
                let content: String
            }
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        var jsonlContent = chatResponse.choices.first?.message.content ?? ""

        // Clean up response (remove markdown code fences if present)
        if jsonlContent.hasPrefix("```") {
            let lines = jsonlContent.components(separatedBy: "\n")
            var cleanLines = lines
            if cleanLines.first?.hasPrefix("```") == true {
                cleanLines.removeFirst()
            }
            if cleanLines.last?.hasPrefix("```") == true {
                cleanLines.removeLast()
            }
            jsonlContent = cleanLines.joined(separator: "\n")
        }

        // Parse JSONL into memory entries
        onProgress("Parsing generated memories...")
        var memories: [MemoryEntry] = []

        for (lineNum, line) in jsonlContent.components(separatedBy: .newlines).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            guard let data = trimmed.data(using: .utf8) else { continue }

            do {
                let entry = try JSONDecoder().decode(MemoryEntry.self, from: data)
                memories.append(entry)
            } catch {
                print("Warning: Failed to parse line \(lineNum + 1): \(error)")
                continue
            }
        }

        guard !memories.isEmpty else {
            throw MemoryGenerationError.noMemoriesGenerated
        }

        onProgress("Generated \(memories.count) memory entries")
        return memories
    }

    /// Generate memories from a character's persona content
    func generateMemories(
        characterName: String,
        personaContent: String,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> [MemoryEntry] {
        onProgress("Analyzing persona for \(characterName)...")

        let prompt = buildPrompt(characterName: characterName)

        onProgress("Generating retrieval-optimized memories...")

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(openAIApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": personaContent]
            ],
            "max_tokens": 8000
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MemoryGenerationError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw MemoryGenerationError.apiError("OpenAI error: \(errorBody)")
        }

        struct ChatResponse: Decodable {
            let choices: [Choice]
            struct Choice: Decodable {
                let message: Message
            }
            struct Message: Decodable {
                let content: String
            }
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        var jsonlContent = chatResponse.choices.first?.message.content ?? ""

        // Clean up response (remove markdown code fences if present)
        if jsonlContent.hasPrefix("```") {
            let lines = jsonlContent.components(separatedBy: "\n")
            var cleanLines = lines
            if cleanLines.first?.hasPrefix("```") == true {
                cleanLines.removeFirst()
            }
            if cleanLines.last?.hasPrefix("```") == true {
                cleanLines.removeLast()
            }
            jsonlContent = cleanLines.joined(separator: "\n")
        }

        // Parse JSONL into memory entries
        onProgress("Parsing generated memories...")
        var memories: [MemoryEntry] = []

        for (lineNum, line) in jsonlContent.components(separatedBy: .newlines).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            guard let data = trimmed.data(using: .utf8) else { continue }

            do {
                let entry = try JSONDecoder().decode(MemoryEntry.self, from: data)
                memories.append(entry)
            } catch {
                print("Warning: Failed to parse line \(lineNum + 1): \(error)")
                continue
            }
        }

        guard !memories.isEmpty else {
            throw MemoryGenerationError.noMemoriesGenerated
        }

        onProgress("Generated \(memories.count) memory entries")
        return memories
    }

    /// Convert memory entries to JSONL string
    func memoriesToJSONL(_ memories: [MemoryEntry]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [] // Compact format

        return memories.compactMap { entry -> String? in
            guard let data = try? encoder.encode(entry),
                  let json = String(data: data, encoding: .utf8) else {
                return nil
            }
            return json
        }.joined(separator: "\n")
    }

    // MARK: - Private

    private func buildTextPrompt(characterName: String, sourceLabel: String) -> String {
        return """
You are building a **retrieval-augmented knowledge base for the character \(characterName)** using the provided text content.

Source: \(sourceLabel)

Your task is to **process the text into multiple independent knowledge base entries**, where **each entry represents a single retrievable unit** suitable for semantic + keyword search.

---

### **Core Requirements**

#### **1. Output Format**

* Output must be a **JSONL file** (one valid JSON object per line).
* Each line represents **one knowledge base entry**.
* Do **not** wrap the output in markdown or code fences.

#### **2. Sectioning**

* Break the content into **logical sections** that should exist as **standalone retrievable entries**.
* Prefer **fine-grained, concept-focused entries** over large, mixed sections.
* Each entry should answer **one clear retrieval intent**.

#### **3. Narrative Voice**

* Rewrite every entry as a **single coherent paragraph**.
* Write **from \(characterName)'s point of view in third person**.
* Use constructions such as:

  * *"\(characterName) is…"*
  * *"\(characterName) has…"*
  * *"\(characterName) believes…"*
  * *"\(characterName) often…"*
* Do **not** quote or reference the original document directly.

#### **4. Content Fidelity**

* Preserve factual accuracy from the text.
* Do **not** invent traits, events, or motivations not supported by the text.
* You may **synthesize and rephrase**, but must remain grounded in the source.

---

### **Keyword Optimization (Critical for Retrieval)**

Each entry must include a **carefully curated `keywords` array** designed to maximize retrieval quality.

When generating keywords:

* Include **explicit terms** present in the text (names, titles, places, roles).
* Add **implicit or inferred search terms** that users are likely to query.
* Include **user-centric phrasing**, not just canonical labels.
* Prefer **searchable, human-likely phrases** over abstract tags.

Aim for **5–12 keywords per entry**, ordered by importance.

---

### **Schema**

Each JSONL entry must follow this structure:

```json
{
  "id": "<stable_snake_case_identifier>",
  "section": "<Human-readable section title>",
  "content": "<Single paragraph written in third-person from \(characterName)'s POV>",
  "keywords": ["keyword1", "keyword2", "..."]
}
```

* `id`: concise, stable, snake_case, suitable for indexing.
* `section`: short, descriptive title.
* `content`: exactly one paragraph.
* `keywords`: retrieval-optimized as described above.

Now process the following text and generate the JSONL knowledge base:
"""
    }

    private func buildPrompt(characterName: String) -> String {
        return """
You are building a **retrieval-augmented knowledge base for the character \(characterName)** using the provided document.

Your task is to **process the document into multiple independent knowledge base entries**, where **each entry represents a single retrievable unit** suitable for semantic + keyword search.

---

### **Core Requirements**

#### **1. Output Format**

* Output must be a **JSONL file** (one valid JSON object per line).
* Each line represents **one knowledge base entry**.
* Do **not** wrap the output in markdown or code fences.

#### **2. Sectioning**

* Break the document into **logical sections** that should exist as **standalone retrievable entries** (e.g., overview, personality, leadership style, relationships, values, fears, habits, hobbies, skills, appearance, media appearances, etc.).
* Prefer **fine-grained, concept-focused entries** over large, mixed sections.
* Each entry should answer **one clear retrieval intent**.

#### **3. Narrative Voice**

* Rewrite every entry as a **single coherent paragraph**.
* Write **from \(characterName)'s point of view in third person**.
* Use constructions such as:

  * *"\(characterName) is…"*
  * *"\(characterName) has…"*
  * *"\(characterName) believes…"*
  * *"\(characterName) often…"*
* Do **not** quote or reference the original document directly.

#### **4. Content Fidelity**

* Preserve factual accuracy from the document.
* Do **not** invent traits, events, or motivations not supported by the text.
* You may **synthesize and rephrase**, but must remain grounded in the source.

---

### **Keyword Optimization (Critical for Retrieval)**

Each entry must include a **carefully curated `keywords` array** designed to maximize retrieval quality.

When generating keywords:

* Include **explicit terms** present in the document (names, titles, places, roles).
* Add **implicit or inferred search terms** that users are likely to query even if the document does not use those exact words.

  * Example:

    * Leadership described → include `"leadership"`, `"team leader"`, `"authority"`
    * Enjoyment or recurring activities → include `"hobbies"`, `"interests"`
    * Protective or loyal behavior → include `"loyalty"`, `"protective"`, `"friendship"`
* Include **user-centric phrasing**, not just canonical labels:

  * `"\(characterName) personality"`
  * `"how \(characterName) acts"`
  * `"what \(characterName) cares about"`
* Prefer **searchable, human-likely phrases** over abstract tags.

Aim for **5–12 keywords per entry**, ordered by importance.

---

### **Schema**

Each JSONL entry must follow this structure:

```json
{
  "id": "<stable_snake_case_identifier>",
  "section": "<Human-readable section title>",
  "content": "<Single paragraph written in third-person from \(characterName)'s POV>",
  "keywords": ["keyword1", "keyword2", "..."]
}
```

* `id`: concise, stable, snake_case, suitable for indexing.
* `section`: short, descriptive title.
* `content`: exactly one paragraph.
* `keywords`: retrieval-optimized as described above.

---

### **Expected Output Example (Illustrative Only)**

```json
{"id":"overview","section":"Overview","content":"\(characterName) is a central figure known for their distinctive personality and approach to life. They value authenticity, hard work, and standing up for what they believe in.","keywords":["\(characterName)","overview","main character","personality","\(characterName) personality"]}
```

Now process the following document and generate the JSONL knowledge base:
"""
    }

    // MARK: - Types

    struct MemoryEntry: Codable {
        let id: String
        let section: String
        let content: String
        let keywords: [String]
    }
}

// MARK: - Errors

enum MemoryGenerationError: LocalizedError {
    case invalidResponse
    case apiError(String)
    case noMemoriesGenerated

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from OpenAI"
        case .apiError(let message):
            return message
        case .noMemoriesGenerated:
            return "No memory entries were generated"
        }
    }
}
