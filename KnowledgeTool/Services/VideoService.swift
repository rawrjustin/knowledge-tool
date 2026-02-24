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
        print("[KnowledgeTool] VideoService: downloadAndExtractAudio starting for \(urlString)")
        // Validate URL
        guard let url = URL(string: urlString), url.scheme != nil else {
            print("[KnowledgeTool] VideoService: Invalid URL: \(urlString)")
            throw KnowledgeToolError.invalidURL
        }

        // Check if yt-dlp is available (should be bundled with app)
        guard await isCommandAvailable("yt-dlp") else {
            print("[KnowledgeTool] VideoService: yt-dlp not found")
            throw KnowledgeToolError.fileError("yt-dlp executable not found. The app may be corrupted. Please re-download the app.")
        }
        print("[KnowledgeTool] VideoService: yt-dlp found, fetching video info...")

        // Get video information first
        let videoInfo = try await getVideoInfo(from: urlString)
        print("[KnowledgeTool] VideoService: Got video info: \(videoInfo.title) (id: \(videoInfo.id))")

        // Download audio
        print("[KnowledgeTool] VideoService: Starting audio download...")
        let audioURL = try await downloadAudio(from: urlString, videoID: videoInfo.id)
        print("[KnowledgeTool] VideoService: Audio downloaded to \(audioURL.lastPathComponent)")

        return (audioURL, videoInfo)
    }

    // MARK: - Run Process Without Blocking
    /// Runs a process on a background thread to avoid blocking the Swift concurrency thread pool.
    /// Also reads pipe data concurrently to prevent pipe buffer deadlocks.
    private func runProcess(_ process: Process, stdoutPipe: Pipe, stderrPipe: Pipe) async throws -> (stdout: Data, stderr: Data, status: Int32) {
        try await withCheckedThrowingContinuation { continuation in
            // Read pipe data on separate queues to prevent buffer deadlocks
            var stdoutData = Data()
            var stderrData = Data()
            let dataLock = NSLock()

            let stdoutHandle = stdoutPipe.fileHandleForReading
            let stderrHandle = stderrPipe.fileHandleForReading

            // Read stdout asynchronously
            DispatchQueue.global(qos: .userInitiated).async {
                let data = stdoutHandle.readDataToEndOfFile()
                dataLock.lock()
                stdoutData = data
                dataLock.unlock()
            }

            // Read stderr asynchronously
            DispatchQueue.global(qos: .userInitiated).async {
                let data = stderrHandle.readDataToEndOfFile()
                dataLock.lock()
                stderrData = data
                dataLock.unlock()
            }

            // Wait for process on a background thread (not the cooperative pool)
            process.terminationHandler = { _ in
                // Give pipe readers a moment to finish
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1) {
                    dataLock.lock()
                    let finalStdout = stdoutData
                    let finalStderr = stderrData
                    dataLock.unlock()
                    continuation.resume(returning: (finalStdout, finalStderr, process.terminationStatus))
                }
            }
        }
    }

    // MARK: - Get Video Info
    private func getVideoInfo(from urlString: String) async throws -> VideoInfo {
        guard let ytDlpPath = await findCommandPath("yt-dlp") else {
            throw KnowledgeToolError.fileError("yt-dlp executable not found. The app may be corrupted. Please re-download the app.")
        }

        print("[KnowledgeTool] VideoService: getVideoInfo using yt-dlp at \(ytDlpPath)")
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: ytDlpPath)
        process.arguments = [
            "--print", "%(id)s|%(title)s|%(duration)s|%(thumbnail)s|%(description)s",
            urlString
        ]

        // Set up environment with comprehensive PATH for yt-dlp dependencies
        process.environment = buildEnvironment()

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            print("[KnowledgeTool] VideoService: yt-dlp failed to launch: \(error.localizedDescription)")
            // This usually means the binary was blocked by macOS security
            throw KnowledgeToolError.fileError("Cannot run yt-dlp. macOS may be blocking it. Try running in Terminal: xattr -cr \(Bundle.main.bundlePath)")
        }

        print("[KnowledgeTool] VideoService: yt-dlp getVideoInfo process launched, waiting for completion...")
        let result = try await runProcess(process, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
        print("[KnowledgeTool] VideoService: yt-dlp getVideoInfo exited with status \(result.status)")

        guard result.status == 0 else {
            let errorMessage = String(data: result.stderr, encoding: .utf8) ?? "Unknown error"
            print("[KnowledgeTool] VideoService: yt-dlp getVideoInfo failed: \(errorMessage)")
            throw KnowledgeToolError.apiError("yt-dlp failed: \(errorMessage)")
        }

        guard let output = String(data: result.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            throw KnowledgeToolError.apiError("Failed to get video information - no output from yt-dlp")
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

        print("[KnowledgeTool] VideoService: downloadAudio for \(videoID), output: \(outputPath.path)")
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

        // Set up environment with comprehensive PATH for yt-dlp dependencies
        process.environment = buildEnvironment()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            print("[KnowledgeTool] VideoService: yt-dlp download failed to launch: \(error.localizedDescription)")
            // This usually means the binary was blocked by macOS security
            throw KnowledgeToolError.fileError("Cannot run yt-dlp. macOS may be blocking it. Try running in Terminal: xattr -cr \(Bundle.main.bundlePath)")
        }

        print("[KnowledgeTool] VideoService: yt-dlp download process launched, waiting for completion...")
        let result = try await runProcess(process, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
        print("[KnowledgeTool] VideoService: yt-dlp download exited with status \(result.status)")

        guard result.status == 0 else {
            let errorMessage = String(data: result.stderr, encoding: .utf8) ?? "Unknown error"
            print("[KnowledgeTool] VideoService: yt-dlp download failed: \(errorMessage.prefix(500))")

            // Check for common error patterns
            if errorMessage.contains("not permitted") || errorMessage.contains("Operation not permitted") {
                throw KnowledgeToolError.fileError("macOS blocked yt-dlp. Run in Terminal: xattr -cr \(Bundle.main.bundlePath)")
            }
            throw KnowledgeToolError.fileError("Failed to download audio: \(errorMessage)")
        }

        guard fileManager.fileExists(atPath: outputPath.path) else {
            print("[KnowledgeTool] VideoService: Audio file not found at expected path after successful yt-dlp exit")
            throw KnowledgeToolError.fileError("Audio file was not created")
        }
        print("[KnowledgeTool] VideoService: Audio file created successfully")

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

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let result = try await runProcess(process, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)

        guard result.status == 0 else {
            let errorMessage = String(data: result.stderr, encoding: .utf8) ?? "Unknown error"
            throw KnowledgeToolError.fileError("Failed to extract audio: \(errorMessage)")
        }

        guard fileManager.fileExists(atPath: outputURL.path) else {
            throw KnowledgeToolError.fileError("Audio file was not created")
        }

        return outputURL
    }

    // MARK: - Build Environment
    private func buildEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment

        // Build comprehensive PATH that includes:
        // 1. Bundled binaries (ffmpeg, yt-dlp, node)
        // 2. User-specific paths (pyenv, local bin)
        // 3. Homebrew paths (for deno as JS runtime fallback)
        // 4. System paths
        var paths: [String] = []

        // Add bundled bin directory first (highest priority)
        if let bundlePath = Bundle.main.resourcePath {
            paths.append("\(bundlePath)/bin")
        }

        // Add user-specific paths (pyenv, local bin)
        if let home = environment["HOME"] {
            paths.append("\(home)/.pyenv/shims")
            paths.append("\(home)/.local/bin")
        }

        // Add Homebrew paths for deno and other tools
        paths.append("/opt/homebrew/bin")  // Apple Silicon
        paths.append("/usr/local/bin")      // Intel Mac

        // Add system paths
        paths.append("/usr/bin")
        paths.append("/bin")

        // Include existing PATH if available
        if let currentPath = environment["PATH"] {
            paths.append(currentPath)
        }

        environment["PATH"] = paths.joined(separator: ":")

        return environment
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

        // Common Homebrew, pyenv, and system installation paths
        var commonPaths = [
            "/opt/homebrew/bin/\(command)",      // Apple Silicon Homebrew
            "/usr/local/bin/\(command)",          // Intel Homebrew
            "/usr/bin/\(command)",                // System binaries
            "/bin/\(command)"                     // System binaries
        ]

        // Add user-specific paths (pyenv, local bin)
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            commonPaths.insert("\(home)/.pyenv/shims/\(command)", at: 0)
            commonPaths.insert("\(home)/.local/bin/\(command)", at: 1)
        }

        // Check common paths
        for path in commonPaths {
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }

        // Fall back to using 'which' command
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            let result = try await runProcess(process, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)

            if result.status == 0 {
                if let path = String(data: result.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
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
