import Foundation

actor AssemblyAIService {
    private let apiKey: String
    private let baseURL = "https://api.assemblyai.com/v2"
    private let session: URLSession

    init(apiKey: String) {
        self.apiKey = apiKey

        // Create a custom URLSession with longer timeouts for large audio uploads
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 600  // 10 minutes for request (large audio files)
        config.timeoutIntervalForResource = 1800 // 30 minutes for entire resource
        self.session = URLSession(configuration: config)
    }

    // MARK: - Transcribe Audio File
    func transcribeAudio(fileURL: URL) async throws -> Transcript {
        // Step 1: Upload the audio file
        print("[KnowledgeTool] AssemblyAI: Uploading audio file \(fileURL.lastPathComponent)...")
        let uploadURL = try await uploadAudioFile(fileURL)
        print("[KnowledgeTool] AssemblyAI: Upload complete")

        // Step 2: Request transcription
        print("[KnowledgeTool] AssemblyAI: Requesting transcription...")
        let transcriptID = try await requestTranscription(uploadURL)
        print("[KnowledgeTool] AssemblyAI: Transcription requested, id: \(transcriptID)")

        // Step 3: Poll for completion
        print("[KnowledgeTool] AssemblyAI: Polling for transcription completion...")
        let transcriptionResult = try await pollTranscription(transcriptID)
        print("[KnowledgeTool] AssemblyAI: Transcription complete (\(transcriptionResult.text.count) chars)")

        return transcriptionResult
    }

    // MARK: - Upload Audio File
    private func uploadAudioFile(_ fileURL: URL) async throws -> String {
        let uploadEndpoint = "\(baseURL)/upload"

        guard let url = URL(string: uploadEndpoint) else {
            throw KnowledgeToolError.invalidURL
        }

        let audioData = try Data(contentsOf: fileURL)
        print("[KnowledgeTool] AssemblyAI: Audio file size: \(audioData.count / 1024)KB")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "content-type")
        request.httpBody = audioData

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[KnowledgeTool] AssemblyAI: Upload got non-HTTP response")
            throw KnowledgeToolError.networkError(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[KnowledgeTool] AssemblyAI: Upload failed (HTTP \(httpResponse.statusCode)): \(errorMessage.prefix(200))")
            throw KnowledgeToolError.apiError("Upload failed: \(errorMessage)")
        }

        struct UploadResponse: Codable {
            let upload_url: String
        }

        let uploadResponse = try JSONDecoder().decode(UploadResponse.self, from: data)
        return uploadResponse.upload_url
    }

    // MARK: - Request Transcription
    private func requestTranscription(_ audioURL: String) async throws -> String {
        let transcriptEndpoint = "\(baseURL)/transcript"

        guard let url = URL(string: transcriptEndpoint) else {
            throw KnowledgeToolError.invalidURL
        }

        struct TranscriptRequest: Codable {
            let audio_url: String
            let speaker_labels: Bool
        }

        let requestBody = TranscriptRequest(audio_url: audioURL, speaker_labels: true)
        let requestData = try JSONEncoder().encode(requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = requestData

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw KnowledgeToolError.networkError(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[KnowledgeTool] AssemblyAI: Transcription request failed (HTTP \(httpResponse.statusCode)): \(errorMessage.prefix(200))")
            throw KnowledgeToolError.apiError("Transcription request failed: \(errorMessage)")
        }

        struct TranscriptResponse: Codable {
            let id: String
        }

        let transcriptResponse = try JSONDecoder().decode(TranscriptResponse.self, from: data)
        return transcriptResponse.id
    }

    // MARK: - Poll Transcription Status
    private func pollTranscription(_ transcriptID: String) async throws -> Transcript {
        let pollEndpoint = "\(baseURL)/transcript/\(transcriptID)"

        guard let url = URL(string: pollEndpoint) else {
            throw KnowledgeToolError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "authorization")

        // Poll every 3 seconds until completion, with maximum timeout of 30 minutes
        // (600 attempts * 3 seconds = 30 minutes - enough for very long videos)
        let maxAttempts = 600
        var attempts = 0
        var lastLoggedStatus = ""

        while attempts < maxAttempts {
            attempts += 1

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("[KnowledgeTool] AssemblyAI: Poll got non-HTTP response")
                throw KnowledgeToolError.networkError(URLError(.badServerResponse))
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("[KnowledgeTool] AssemblyAI: Poll failed (HTTP \(httpResponse.statusCode)): \(errorMessage.prefix(200))")
                throw KnowledgeToolError.apiError("Polling failed: \(errorMessage)")
            }

            struct PollResponse: Codable {
                let status: String
                let text: String?
                let error: String?
                let utterances: [Utterance]?

                struct Utterance: Codable {
                    let speaker: String
                    let text: String
                    let start: Int
                    let end: Int
                }
            }

            let pollResponse = try JSONDecoder().decode(PollResponse.self, from: data)

            switch pollResponse.status {
            case "completed":
                print("[KnowledgeTool] AssemblyAI: Transcription completed after \(attempts) poll(s)")
                guard let text = pollResponse.text else {
                    print("[KnowledgeTool] AssemblyAI: Completed but no text received")
                    throw KnowledgeToolError.transcriptionFailed("No transcript text received")
                }

                let speakerLabels = pollResponse.utterances?.map { utterance in
                    SpeakerUtterance(
                        speaker: utterance.speaker,
                        text: utterance.text,
                        start: TimeInterval(utterance.start) / 1000.0,
                        end: TimeInterval(utterance.end) / 1000.0
                    )
                }
                print("[KnowledgeTool] AssemblyAI: Got \(text.count) chars, \(speakerLabels?.count ?? 0) utterances")

                return Transcript(
                    text: text,
                    speakerLabels: speakerLabels
                )

            case "error":
                print("[KnowledgeTool] AssemblyAI: Transcription error: \(pollResponse.error ?? "Unknown")")
                throw KnowledgeToolError.transcriptionFailed(pollResponse.error ?? "Unknown error")

            case "queued", "processing":
                if pollResponse.status != lastLoggedStatus {
                    print("[KnowledgeTool] AssemblyAI: Status: \(pollResponse.status) (poll #\(attempts))")
                    lastLoggedStatus = pollResponse.status
                } else if attempts % 10 == 0 {
                    print("[KnowledgeTool] AssemblyAI: Still \(pollResponse.status)... (poll #\(attempts), ~\(attempts * 3)s elapsed)")
                }
                // Wait 3 seconds before next poll
                try await Task.sleep(for: .seconds(3))
                continue

            default:
                print("[KnowledgeTool] AssemblyAI: Unknown status: \(pollResponse.status)")
                throw KnowledgeToolError.transcriptionFailed("Unknown status: \(pollResponse.status)")
            }
        }

        // Timeout reached
        print("[KnowledgeTool] AssemblyAI: Transcription timed out after \(maxAttempts) polls")
        throw KnowledgeToolError.transcriptionFailed("Transcription timed out after 30 minutes. Please try again with a shorter video.")
    }
}
