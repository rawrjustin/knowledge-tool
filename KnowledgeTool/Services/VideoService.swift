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

        // Check if yt-dlp is available (should be bundled with app)
        guard await isCommandAvailable("yt-dlp") else {
            throw KnowledgeToolError.fileError("yt-dlp executable not found. The app may be corrupted. Please re-download the app.")
        }

        // Get video information first
        let videoInfo = try await getVideoInfo(from: urlString)

        // Download audio
        let audioURL = try await downloadAudio(from: urlString, videoID: videoInfo.id)

        return (audioURL, videoInfo)
    }

    // MARK: - Get Video Info
    private func getVideoInfo(from urlString: String) async throws -> VideoInfo {
        guard let ytDlpPath = await findCommandPath("yt-dlp") else {
            throw KnowledgeToolError.fileError("yt-dlp executable not found. The app may be corrupted. Please re-download the app.")
        }

        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: ytDlpPath)
        process.arguments = [
            "--print", "%(id)s|%(title)s|%(duration)s|%(thumbnail)s|%(description)s",
            urlString
        ]

        // Set PATH environment variable to include bundled binaries directory
        if let bundlePath = Bundle.main.resourcePath {
            let binPath = "\(bundlePath)/bin"
            var environment = ProcessInfo.processInfo.environment
            if let currentPath = environment["PATH"] {
                environment["PATH"] = "\(binPath):\(currentPath)"
            } else {
                environment["PATH"] = binPath
            }
            process.environment = environment
        }

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
        let description = components.count > 4 ? components[4] : nil

        return VideoInfo(id: id, title: title, duration: duration, thumbnailURL: thumbnail, description: description)
    }

    // MARK: - Download Audio
    private func downloadAudio(from urlString: String, videoID: String) async throws -> URL {
        guard let ytDlpPath = await findCommandPath("yt-dlp") else {
            throw KnowledgeToolError.fileError("yt-dlp executable not found. The app may be corrupted. Please re-download the app.")
        }

        guard let ffmpegPath = await findCommandPath("ffmpeg") else {
            throw KnowledgeToolError.fileError("ffmpeg executable not found. The app may be corrupted. Please re-download the app.")
        }

        // Get the directory containing ffmpeg (yt-dlp needs the directory path)
        let ffmpegDir = (ffmpegPath as NSString).deletingLastPathComponent

        let outputPath = tempDirectory.appendingPathComponent("\(videoID).m4a")

        // Remove existing file if it exists
        try? fileManager.removeItem(at: outputPath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytDlpPath)
        process.arguments = [
            "-f", "bestaudio[ext=m4a]/bestaudio/best",
            "--extract-audio",
            "--audio-format", "m4a",
            "--ffmpeg-location", ffmpegDir,
            "-o", outputPath.path,
            urlString
        ]

        // Set PATH environment variable to include bundled binaries directory
        // This allows yt-dlp to find Node.js for JavaScript decryption
        var environment = ProcessInfo.processInfo.environment
        if let currentPath = environment["PATH"] {
            environment["PATH"] = "\(ffmpegDir):\(currentPath)"
        } else {
            environment["PATH"] = ffmpegDir
        }
        process.environment = environment

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
        guard let ffmpegPath = await findCommandPath("ffmpeg") else {
            throw KnowledgeToolError.fileError("ffmpeg executable not found. The app may be corrupted. Please re-download the app.")
        }

        let fileName = videoURL.deletingPathExtension().lastPathComponent
        let outputURL = tempDirectory.appendingPathComponent("\(fileName)_audio.m4a")

        // Remove existing file if it exists
        try? fileManager.removeItem(at: outputURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
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

    // MARK: - Find Command Path
    private func findCommandPath(_ command: String) async -> String? {
        // First, check for bundled executable in app bundle
        if let bundlePath = Bundle.main.resourcePath {
            let bundledExecutable = "\(bundlePath)/bin/\(command)"
            if fileManager.fileExists(atPath: bundledExecutable) {
                return bundledExecutable
            }
        }

        // Common Homebrew and system installation paths
        let commonPaths = [
            "/opt/homebrew/bin/\(command)",      // Apple Silicon Homebrew
            "/usr/local/bin/\(command)",          // Intel Homebrew
            "/usr/bin/\(command)",                // System binaries
            "/bin/\(command)"                     // System binaries
        ]

        // Check common paths
        for path in commonPaths {
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }

        // Fall back to using 'which' command
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {
            return nil
        }

        return nil
    }

    // MARK: - Check if Command is Available
    private func isCommandAvailable(_ command: String) async -> Bool {
        return await findCommandPath(command) != nil
    }

    // MARK: - Cleanup
    func cleanup(audioURL: URL) {
        try? fileManager.removeItem(at: audioURL)
    }

    func cleanupAll() {
        try? fileManager.removeItem(at: tempDirectory)
    }
}
