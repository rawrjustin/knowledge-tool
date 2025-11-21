import Foundation

actor AssemblyAIService {
    private let apiKey: String
    private let baseURL = "https://api.assemblyai.com/v2"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Transcribe Audio File
    func transcribeAudio(fileURL: URL) async throws -> Transcript {
        // Step 1: Upload the audio file
        let uploadURL = try await uploadAudioFile(fileURL)

        // Step 2: Request transcription
        let transcriptID = try await requestTranscription(uploadURL)

        // Step 3: Poll for completion
        let transcriptionResult = try await pollTranscription(transcriptID)

        return transcriptionResult
    }

    // MARK: - Upload Audio File
    private func uploadAudioFile(_ fileURL: URL) async throws -> String {
        let uploadEndpoint = "\(baseURL)/upload"

        guard let url = URL(string: uploadEndpoint) else {
            throw KnowledgeToolError.invalidURL
        }

        let audioData = try Data(contentsOf: fileURL)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "content-type")
        request.httpBody = audioData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw KnowledgeToolError.networkError(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
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

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw KnowledgeToolError.networkError(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
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

        // Poll every 3 seconds until completion
        while true {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw KnowledgeToolError.networkError(URLError(.badServerResponse))
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
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
                guard let text = pollResponse.text else {
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

                return Transcript(
                    text: text,
                    speakerLabels: speakerLabels
                )

            case "error":
                throw KnowledgeToolError.transcriptionFailed(pollResponse.error ?? "Unknown error")

            case "queued", "processing":
                // Wait 3 seconds before next poll
                try await Task.sleep(for: .seconds(3))
                continue

            default:
                throw KnowledgeToolError.transcriptionFailed("Unknown status: \(pollResponse.status)")
            }
        }
    }
}
