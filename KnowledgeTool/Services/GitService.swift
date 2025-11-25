import Foundation

actor GitService {
    private let fileManager = FileManager.default

    // MARK: - Git Pull

    /// Pull latest changes from remote repository
    func pull(at path: String) async throws -> String {
        guard fileManager.fileExists(atPath: path) else {
            throw GitServiceError.repositoryNotFound(path)
        }

        // Check if it's a git repository
        let gitPath = "\(path)/.git"
        guard fileManager.fileExists(atPath: gitPath) else {
            throw GitServiceError.notAGitRepository(path)
        }

        // Execute git pull
        let result = try await executeGitCommand(["pull"], at: path)

        return result.output
    }

    // MARK: - Git Status

    /// Get repository status
    func status(at path: String) async throws -> GitStatus {
        guard fileManager.fileExists(atPath: path) else {
            throw GitServiceError.repositoryNotFound(path)
        }

        // Get current branch
        let branchResult = try await executeGitCommand(["branch", "--show-current"], at: path)
        let branch = branchResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Get modified files
        let statusResult = try await executeGitCommand(["status", "--porcelain"], at: path)
        let modifiedFiles = statusResult.output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let hasUncommittedChanges = !modifiedFiles.isEmpty

        // Get last commit info
        let logResult = try? await executeGitCommand(
            ["log", "-1", "--pretty=format:%s|%ct"],
            at: path
        )

        var lastCommitMessage: String?
        var lastCommitDate: Date?

        if let logOutput = logResult?.output {
            let components = logOutput.split(separator: "|")
            if components.count >= 2 {
                lastCommitMessage = String(components[0])
                if let timestamp = TimeInterval(components[1]) {
                    lastCommitDate = Date(timeIntervalSince1970: timestamp)
                }
            }
        }

        return GitStatus(
            hasUncommittedChanges: hasUncommittedChanges,
            modifiedFiles: modifiedFiles,
            branch: branch,
            lastCommitMessage: lastCommitMessage,
            lastCommitDate: lastCommitDate
        )
    }

    // MARK: - Utility

    /// Check if path is a git repository
    func isGitRepository(at path: String) async -> Bool {
        let gitPath = "\(path)/.git"
        return fileManager.fileExists(atPath: gitPath)
    }

    /// Get current branch name
    func getCurrentBranch(at path: String) async throws -> String {
        let result = try await executeGitCommand(["branch", "--show-current"], at: path)
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Get remote URL
    func getRemoteURL(at path: String) async throws -> String? {
        let result = try? await executeGitCommand(["config", "--get", "remote.origin.url"], at: path)
        return result?.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Commit History

    /// Get commit history for a specific file
    func getCommitHistory(for filePath: String, at repositoryPath: String, limit: Int = 20) async throws -> [GitCommit] {
        let result = try await executeGitCommand([
            "log",
            "--format=%H%n%an%n%ae%n%at%n%s%n%b%n---COMMIT-END---",
            "-n", "\(limit)",
            "--",
            filePath
        ], at: repositoryPath)

        return parseGitLog(result.output)
    }

    /// Get diff between two commits for a file
    func getDiff(for filePath: String, from: String, to: String, at repositoryPath: String) async throws -> String {
        let result = try await executeGitCommand([
            "diff",
            "\(from)..\(to)",
            "--",
            filePath
        ], at: repositoryPath)

        return result.output
    }

    /// Get file content at a specific commit
    func getFileContent(at filePath: String, commit: String, in repositoryPath: String) async throws -> String {
        let result = try await executeGitCommand([
            "show",
            "\(commit):\(filePath)"
        ], at: repositoryPath)

        return result.output
    }

    // MARK: - Private Helpers

    private func parseGitLog(_ output: String) -> [GitCommit] {
        let commits = output.components(separatedBy: "---COMMIT-END---")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return commits.compactMap { commitString in
            let lines = commitString.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard lines.count >= 4 else { return nil }

            let sha = lines[0]
            let authorName = lines[1]
            let authorEmail = lines[2]

            guard let timestamp = TimeInterval(lines[3]) else { return nil }
            let date = Date(timeIntervalSince1970: timestamp)

            let subject = lines.count > 4 ? lines[4] : ""
            let body = lines.count > 5 ? lines[5...].joined(separator: "\n") : ""

            return GitCommit(
                sha: sha,
                authorName: authorName,
                authorEmail: authorEmail,
                date: date,
                subject: subject,
                body: body
            )
        }
    }

    /// Execute a git command
    private func executeGitCommand(_ arguments: [String], at repositoryPath: String) async throws -> GitCommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: repositoryPath)
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw GitServiceError.commandFailed(
                command: "git \(arguments.joined(separator: " "))",
                exitCode: process.terminationStatus,
                errorOutput: error
            )
        }

        return GitCommandResult(output: output, error: error, exitCode: process.terminationStatus)
    }
}

// MARK: - Supporting Types

struct GitCommandResult {
    let output: String
    let error: String
    let exitCode: Int32
}

struct GitCommit: Identifiable, Codable, Hashable {
    let id: UUID
    let sha: String
    let authorName: String
    let authorEmail: String
    let date: Date
    let subject: String
    let body: String
    var aiSummary: String?  // LLM-generated summary of changes

    init(
        id: UUID = UUID(),
        sha: String,
        authorName: String,
        authorEmail: String,
        date: Date,
        subject: String,
        body: String,
        aiSummary: String? = nil
    ) {
        self.id = id
        self.sha = sha
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.date = date
        self.subject = subject
        self.body = body
        self.aiSummary = aiSummary
    }

    var shortSha: String {
        String(sha.prefix(7))
    }

    var fullMessage: String {
        if body.isEmpty {
            return subject
        }
        return "\(subject)\n\n\(body)"
    }
}

// MARK: - Errors

enum GitServiceError: LocalizedError {
    case repositoryNotFound(String)
    case notAGitRepository(String)
    case commandFailed(command: String, exitCode: Int32, errorOutput: String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .repositoryNotFound(let path):
            return "Repository not found at: \(path)"
        case .notAGitRepository(let path):
            return "Not a git repository: \(path)"
        case .commandFailed(let command, let exitCode, let errorOutput):
            return "Git command failed: \(command)\nExit code: \(exitCode)\nError: \(errorOutput)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}
