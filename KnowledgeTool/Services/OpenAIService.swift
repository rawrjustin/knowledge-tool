import Foundation

actor OpenAIService {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1"
    private let model: String

    init(apiKey: String, model: String = "gpt-4o") {
        self.apiKey = apiKey
        self.model = model
    }

    // MARK: - Chat Completion
    func chat(messages: [[String: String]], model: String? = nil) async throws -> String {
        let targetModel = model ?? self.model

        let requestBody: [String: Any] = [
            "model": targetModel,
            "messages": messages
        ]

        let requestData = try JSONSerialization.data(withJSONObject: requestBody)

        var request = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw KnowledgeToolError.apiError("OpenAI chat request failed: \(errorMessage)")
        }

        struct ChatResponse: Codable {
            let choices: [Choice]
            struct Choice: Codable {
                let message: Message
                struct Message: Codable {
                    let content: String
                }
            }
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)

        guard let content = chatResponse.choices.first?.message.content else {
            throw KnowledgeToolError.summarizationFailed("No response content received")
        }

        return content
    }

    // MARK: - Summarize Text
    func summarize(text: String, contentType: ContentType) async throws -> String {
        let prompt = createSummarizationPrompt(for: contentType)
        return try await generateCompletion(systemPrompt: prompt, userContent: text)
    }

    // MARK: - Generate Structured Knowledge Base
    func generateStructuredKnowledgeBase(
        characterName: String,
        fullTranscript: String,
        speakerLabels: [SpeakerUtterance]?,
        videoURL: String,
        videoTitle: String
    ) async throws -> String {
        // Build transcript with timestamps if available
        var formattedTranscript = ""
        if let speakerLabels = speakerLabels, !speakerLabels.isEmpty {
            for utterance in speakerLabels {
                let timestamp = formatTimestamp(utterance.start)
                formattedTranscript += "[\(timestamp)] \(utterance.speaker): \(utterance.text)\n\n"
            }
        } else {
            formattedTranscript = fullTranscript
        }

        let prompt = """
        You are helping build a structured knowledge base for an **AI character**.

        This knowledge base will help the character answer factual questions about themselves, their world, and all related media.

        You will be given:
        * `character_name` — the name of the AI character
        * `full_transcript` — the **entire video transcript with timestamps** (may or may not include timestamps)

        ---

        ## **Your Task**

        ### 1. Process the transcript into **sliding 10-minute windows**

        Use a **10-minute window** with a **5-minute offset**, producing segments like:

        * `0–10`
        * `5–15`
        * `10–20`
        * `15–25`
        * …continue until the transcript ends.

        If timestamps exist, use them.
        If timestamps do **not** exist, approximate by splitting the transcript into evenly sized consecutive chunks that simulate 5-minute shifts and 10-minute spans.

        ---

        ### 2. For **each window**, create **exactly one retrieval entry**.

        ---

        ### 3. Output **one JSON object per line (JSONL)** — one per window, in chronological order.

        ---

        ## **STRICT RULES**

        1. **Write entirely in the character's third-person POV**, using phrasing like:

           * "\(characterName) is…"
           * "\(characterName) has…"
           * "\(characterName) explains…"
           * "\(characterName) remembers…"

        2. The `text` field must be **one clear paragraph (120–160 words)** summarizing the factual content of that sliding 10-minute window in the character's voice.

        3. **No bullet points, lists, headings, or dialogue-style formatting.**
           Only flowing, natural prose.

        4. **Output only valid JSONL** — no markdown, no commentary, no metadata outside the JSON.

        ---

        ## **Each JSON object must contain EXACTLY these fields:**

        ### **`id`**

        Format: `"t{start}-{end}"`
        Examples: `"t0-10"`, `"t5-15"`, `"t10-20"`

        ### **`url`**
        \(videoURL)

        ### **`title`**
        \(videoTitle)

        ### **`chunk_summary`**

        A short descriptive title capturing the main idea of **that specific window** only.

        ### **`background`**

        A 1–2 sentence explanation of **how the content of this window connects to the overall narrative or themes of the entire video**.
        This should capture the broader significance of the window.

        ### **`text`**

        A 120–160 word paragraph written in the third-person POV of `\(characterName)`, summarizing the factual content inside this specific window.

        ### **`tags`**

        An array of **2–5 short keywords**.

        ---

        ## **Goal**

        Produce **clean, factual, retrieval-ready entries**—one for each sliding 10-minute window—so the AI character can later retrieve and integrate this knowledge to answer questions grounded in the full video content.
        Always generate the full JSONL as a single file. Do not ask questions. Generate for entire transcript. One json entry per line.
        """

        return try await generateCompletion(
            systemPrompt: prompt,
            userContent: "Character name: \(characterName)\n\nFull transcript:\n\n\(formattedTranscript)"
        )
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }

    // MARK: - Analyze Text Snippet
    func analyzeTextSnippet(_ text: String) async throws -> String {
        let prompt = createSummarizationPrompt(for: .textSnippet)
        return try await generateCompletion(systemPrompt: prompt, userContent: text)
    }

    // MARK: - Identify Interviewee
    func identifyInterviewee(title: String, description: String?, transcriptPreview: String) async throws -> String? {
        let descriptionText = description ?? "No description available"

        let prompt = """
        You are analyzing an interview video to identify the main interviewee (the person being interviewed, NOT the interviewer/host).

        Video Title: \(title)
        Video Description: \(descriptionText)

        Transcript Preview (first portion):
        \(transcriptPreview)

        Based on the title, description, and transcript content, identify the FULL NAME of the main interviewee.

        ## Guidelines:
        - Look for the person who is the subject of the interview (being interviewed, not conducting it)
        - Use the full proper name (e.g., "Shawn Mendes", "Elon Musk", "Taylor Swift")
        - If there are multiple people being interviewed, choose the primary subject
        - Be confident - use context clues from the title and description
        - Return ONLY the name, nothing else

        ## Output Format:
        Return ONLY the person's name as a plain string. No quotes, no explanations, no JSON.

        Examples of valid outputs:
        Shawn Mendes
        Jake Paul
        Oprah Winfrey

        If you cannot confidently identify a single interviewee, return: UNKNOWN
        """

        let response = try await generateCompletion(
            systemPrompt: prompt,
            userContent: "",
            model: "gpt-4o-mini"  // Use mini model for cost efficiency
        )

        let trimmedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedResponse == "UNKNOWN" ? nil : trimmedResponse
    }

    // MARK: - Extract Dialogue Examples
    func extractDialogueExamples(from speakerLabels: [SpeakerUtterance]) async throws -> [SpeakerDialogueExamples] {
        // Group utterances by speaker
        let speakerGroups = Dictionary(grouping: speakerLabels) { $0.speaker }

        var dialogueExamples: [SpeakerDialogueExamples] = []

        for (speaker, utterances) in speakerGroups {
            // Combine all utterances for this speaker
            let speakerText = utterances.map { $0.text }.joined(separator: "\n\n")

            let prompt = """
            You are an expert at analyzing speech patterns, tone, and vocabulary to identify characteristic dialogue.

            Below is a transcript of everything spoken by "\(speaker)" in this conversation.

            Your task: Select up to 10 of the MOST CHARACTERISTIC dialogue examples (1-2 sentences each) that best represent this speaker's unique:
            - Voice and speaking style
            - Vocabulary and word choice
            - Tone and personality
            - Natural speech patterns
            - Distinctive phrases or expressions

            ## Selection Criteria:
            - Choose examples that feel natural and authentic to this speaker
            - Prioritize quotes that showcase their personality and perspective
            - Include variety: different topics, emotions, or contexts
            - Select memorable, impactful, or revealing statements
            - Keep each example to 1-2 sentences (short and punchy)
            - Choose quotes that could serve as writing samples of their prose/voice

            ## Output Format:
            Return ONLY a JSON array of strings, with each string being one dialogue example.
            No additional text, no explanations - just the JSON array.

            Example format:
            ["First dialogue example here.", "Second dialogue example here.", "Third example."]

            Aim for 5-10 examples depending on the richness of the content. Quality over quantity.
            """

            let response = try await generateCompletion(systemPrompt: prompt, userContent: speakerText)

            // Parse JSON response
            if let jsonData = response.data(using: .utf8),
               let examples = try? JSONDecoder().decode([String].self, from: jsonData) {
                dialogueExamples.append(SpeakerDialogueExamples(
                    speaker: speaker,
                    examples: examples
                ))
            }
        }

        return dialogueExamples
    }

    // MARK: - Generate Completion
    private func generateCompletion(systemPrompt: String, userContent: String, model: String? = nil) async throws -> String {
        let endpoint = "\(baseURL)/chat/completions"

        guard let url = URL(string: endpoint) else {
            throw KnowledgeToolError.invalidURL
        }

        struct ChatRequest: Codable {
            let model: String
            let messages: [Message]
            let temperature: Double

            struct Message: Codable {
                let role: String
                let content: String
            }
        }

        let requestBody = ChatRequest(
            model: model ?? self.model,
            messages: [
                ChatRequest.Message(role: "system", content: systemPrompt),
                ChatRequest.Message(role: "user", content: userContent)
            ],
            temperature: 0.7
        )

        let requestData = try JSONEncoder().encode(requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw KnowledgeToolError.networkError(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw KnowledgeToolError.apiError("OpenAI request failed: \(errorMessage)")
        }

        struct ChatResponse: Codable {
            let choices: [Choice]

            struct Choice: Codable {
                let message: Message

                struct Message: Codable {
                    let content: String
                }
            }
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)

        guard let content = chatResponse.choices.first?.message.content else {
            throw KnowledgeToolError.summarizationFailed("No response content received")
        }

        return content
    }

    // MARK: - Create Summarization Prompts
    private func createSummarizationPrompt(for contentType: ContentType) -> String {
        switch contentType {
        case .video:
            return """
            You are an expert knowledge curator specialized in creating detailed, comprehensive summaries of video transcripts for long-term memory and knowledge storage.

            Your task is to create a RICH, DETAILED summary that preserves the intricate details, nuances, and full context of the content. This summary will serve as a standalone knowledge artifact that can be referenced months or years later.

            ## Required Structure:

            ### Overview
            - Provide a 2-3 sentence overview of the video's main topic and purpose
            - Include the context: who is speaking, what format (interview, lecture, discussion, etc.)

            ### Key Themes & Main Ideas
            - Identify and explain all major themes discussed
            - Preserve the depth of each idea - don't just list topics, explain them thoroughly
            - Include the reasoning, arguments, and logic behind each main point

            ### Detailed Content Breakdown
            For each major topic or segment:
            - Capture specific claims, statements, and assertions made
            - Preserve important examples, anecdotes, and stories with full context
            - Include relevant statistics, numbers, percentages, and data points
            - Quote memorable or significant phrases verbatim when impactful
            - Explain methodologies, processes, or frameworks described
            - Note any contrarian or surprising viewpoints expressed

            ### Important Details
            - All proper names (people, companies, products, places, books, studies)
            - Specific dates, timeframes, and chronological information
            - Technical terms and their explanations
            - Causal relationships and connections between ideas
            - Predictions, forecasts, or future-oriented statements
            - Personal experiences or case studies shared

            ### Insights & Takeaways
            - Synthesize the most valuable insights
            - Highlight actionable advice or practical applications
            - Note any unique perspectives or frameworks presented
            - Include lessons learned or wisdom shared

            ### Context & Nuances
            - Capture the tone and sentiment where relevant
            - Note areas of emphasis or passion
            - Include qualifications, caveats, or exceptions mentioned
            - Preserve disagreements or debates if multiple speakers

            ## Critical Guidelines:
            - PRIORITIZE COMPLETENESS over brevity - aim for a comprehensive summary
            - PRESERVE SPECIFICITY - include actual names, numbers, and concrete details
            - MAINTAIN CONTEXT - explain the "why" behind statements, not just the "what"
            - CAPTURE RICHNESS - include illustrative examples and stories that add understanding
            - ORGANIZE CLEARLY - use headers, bullet points, and structure for easy scanning
            - ASSUME NO PRIOR KNOWLEDGE - someone reading this summary should understand the full content without watching the video

            This is for KNOWLEDGE STORAGE and LONG-TERM REFERENCE. Be thorough, detailed, and comprehensive.
            """

        case .article:
            return """
            You are an expert knowledge curator specialized in creating detailed, comprehensive summaries of articles and written content for long-term memory and knowledge storage.

            Your task is to create a RICH, DETAILED summary that preserves the intricate details, arguments, and full context of the article. This summary will serve as a standalone knowledge artifact that can be referenced months or years later.

            ## Required Structure:

            ### Article Overview
            - Provide a 2-3 sentence summary of the article's main topic and purpose
            - Include the author's background/credentials if mentioned
            - Note the publication context (when relevant: publication, date, type of article)

            ### Main Thesis & Central Arguments
            - Clearly state the author's primary thesis or argument
            - Explain the reasoning and logic behind the main claims
            - Identify supporting sub-arguments and how they connect

            ### Detailed Content Analysis
            For each major section or argument:
            - Capture the specific claims and evidence presented
            - Preserve important examples, case studies, and illustrations
            - Include all statistics, data points, research findings, and citations
            - Quote impactful or definitive statements verbatim
            - Explain frameworks, models, or methodologies discussed
            - Note counterarguments addressed and how they're handled

            ### Evidence & Supporting Details
            - All research studies, papers, or sources cited
            - Specific data, percentages, and quantitative information
            - Names of researchers, experts, or authorities quoted
            - Historical examples or precedents mentioned
            - Comparative analyses or contrasts made

            ### Key Insights & Implications
            - Synthesize the most important insights from the article
            - Explain the practical implications or applications
            - Note any predictions or future-oriented conclusions
            - Highlight novel or unique perspectives presented
            - Capture recommended actions or next steps if provided

            ### Important Context
            - Historical or background information provided
            - Assumptions or premises the argument rests on
            - Limitations or caveats acknowledged by the author
            - Connections to broader debates or fields
            - Controversial or provocative points made

            ### Notable Details
            - Proper names (people, organizations, places, products, books)
            - Dates, timelines, and chronological information
            - Technical terms and their definitions
            - Memorable quotes or phrases
            - Surprising or counterintuitive findings

            ## Critical Guidelines:
            - PRIORITIZE COMPLETENESS over brevity - aim for a comprehensive summary
            - PRESERVE SPECIFICITY - include actual names, numbers, citations, and concrete details
            - MAINTAIN LOGICAL FLOW - show how arguments build on each other
            - CAPTURE RICHNESS - include the examples and evidence that make arguments convincing
            - ORGANIZE CLEARLY - use headers, bullet points, and structure for easy reference
            - ASSUME NO PRIOR KNOWLEDGE - someone reading this should understand the full article without reading the original

            This is for KNOWLEDGE STORAGE and LONG-TERM REFERENCE. Be thorough, detailed, and comprehensive.
            """

        case .textSnippet:
            return """
            You are an expert knowledge curator specialized in analyzing and documenting text snippets for long-term memory and knowledge storage.

            Your task is to create a DETAILED analysis that preserves the complete meaning, context, and nuances of the text snippet.

            ## Your Analysis Should Include:

            ### Main Content
            - Clearly identify the core message or purpose of the text
            - Explain the context if it can be inferred
            - Note the type of content (quote, instruction, note, excerpt, etc.)

            ### Key Information
            - Extract all important facts, claims, or statements
            - Preserve specific names, numbers, dates, and references
            - Identify any technical terms or specialized vocabulary
            - Note quotes or attributions if present

            ### Insights & Implications
            - Synthesize the key insights or takeaways
            - Explain why this information might be important
            - Identify any actionable items or next steps
            - Note connections to broader concepts if relevant

            ### Context & Nuances
            - Capture tone, sentiment, or emphasis where present
            - Note any caveats, qualifications, or conditions
            - Identify assumptions or prerequisites mentioned
            - Preserve any warnings or important considerations

            ### Practical Value
            - Explain how this information might be used or applied
            - Identify the target audience if discernible
            - Note any time-sensitive or context-dependent aspects

            ## Critical Guidelines:
            - PRESERVE ALL DETAILS - don't omit specifics even if the text is short
            - MAINTAIN PRECISION - keep exact phrasing for important points
            - ADD CLARITY - explain or contextualize where it adds understanding
            - ORGANIZE CLEARLY - structure the analysis for easy reference
            - ASSUME NO PRIOR CONTEXT - explain as if the reader is seeing this for the first time

            This is for KNOWLEDGE STORAGE and LONG-TERM REFERENCE. Be thorough and preserve all valuable information.
            """
        }
    }
}
