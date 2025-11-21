import Foundation
import UniformTypeIdentifiers

actor VideoService {
    private let fileManager = FileManager.default
    private let tempDirectory: URL

    init() {
        self.tempDirectory = fileManager.temporaryDirectory.appendingPathComponent("KnowledgeTool", isDirectory: true)
        try? fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Download and Extract Audio from URL
    func downloadAndExtractAudio(from urlString: String) async throws -> (audioURL: URL, videoInfo: VideoInfo) {
        // Validate URL
        guard let url = URL(string: urlString), url.scheme != nil else {
            throw KnowledgeToolError.invalidURL
        }

        // Check if yt-dlp is available
        guard await isCommandAvailable("yt-dlp") else {
            throw KnowledgeToolError.fileError("yt-dlp is not installed. Please install it using: brew install yt-dlp")
        }

        // Get video information first
        let videoInfo = try await getVideoInfo(from: urlString)

        // Download audio
        let audioURL = try await downloadAudio(from: urlString, videoID: videoInfo.id)

        return (audioURL, videoInfo)
    }

    // MARK: - Get Video Info
    private func getVideoInfo(from urlString: String) async throws -> VideoInfo {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "yt-dlp",
            "--print", "%(id)s|%(title)s|%(duration)s|%(thumbnail)s",
            urlString
        ]
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            throw KnowledgeToolError.apiError("Failed to get video information")
        }

        let components = output.components(separatedBy: "|")
        guard components.count >= 2 else {
            throw KnowledgeToolError.apiError("Invalid video information format")
        }

        let id = components[0]
        let title = components[1]
        let duration = components.count > 2 ? TimeInterval(components[2]) : nil
        let thumbnail = components.count > 3 ? components[3] : nil

        return VideoInfo(id: id, title: title, duration: duration, thumbnailURL: thumbnail)
    }

    // MARK: - Download Audio
    private func downloadAudio(from urlString: String, videoID: String) async throws -> URL {
        let outputPath = tempDirectory.appendingPathComponent("\(videoID).m4a")

        // Remove existing file if it exists
        try? fileManager.removeItem(at: outputPath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "yt-dlp",
            "-f", "bestaudio[ext=m4a]/bestaudio/best",
            "--extract-audio",
            "--audio-format", "m4a",
            "-o", outputPath.path,
            urlString
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw KnowledgeToolError.fileError("Failed to download audio: \(errorMessage)")
        }

        guard fileManager.fileExists(atPath: outputPath.path) else {
            throw KnowledgeToolError.fileError("Audio file was not created")
        }

        return outputPath
    }

    // MARK: - Extract Audio from Local Video File
    func extractAudio(from videoURL: URL) async throws -> URL {
        // Check if ffmpeg is available
        guard await isCommandAvailable("ffmpeg") else {
            throw KnowledgeToolError.fileError("ffmpeg is not installed. Please install it using: brew install ffmpeg")
        }

        let fileName = videoURL.deletingPathExtension().lastPathComponent
        let outputURL = tempDirectory.appendingPathComponent("\(fileName)_audio.m4a")

        // Remove existing file if it exists
        try? fileManager.removeItem(at: outputURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "ffmpeg",
            "-i", videoURL.path,
            "-vn", // No video
            "-acodec", "aac",
            "-y", // Overwrite output file
            outputURL.path
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw KnowledgeToolError.fileError("Failed to extract audio: \(errorMessage)")
        }

        guard fileManager.fileExists(atPath: outputURL.path) else {
            throw KnowledgeToolError.fileError("Audio file was not created")
        }

        return outputURL
    }

    // MARK: - Check if Command is Available
    private func isCommandAvailable(_ command: String) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", command]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Cleanup
    func cleanup(audioURL: URL) {
        try? fileManager.removeItem(at: audioURL)
    }

    func cleanupAll() {
        try? fileManager.removeItem(at: tempDirectory)
    }
}
