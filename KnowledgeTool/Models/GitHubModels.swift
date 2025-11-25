import Foundation

// MARK: - GitHub User

struct GitHubUser: Codable, Hashable {
    let id: Int
    let login: String
    let name: String?
    let email: String?
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case id, login, name, email
        case avatarURL = "avatar_url"
    }
}

// MARK: - GitHub File

struct GitHubFile: Codable {
    let name: String
    let path: String
    let sha: String
    let size: Int
    let url: String
    let htmlURL: String?
    let gitURL: String?
    let downloadURL: String?
    let type: String // "file" or "dir"
    let content: String? // Base64 encoded
    let encoding: String? // "base64"

    enum CodingKeys: String, CodingKey {
        case name, path, sha, size, url, type, content, encoding
        case htmlURL = "html_url"
        case gitURL = "git_url"
        case downloadURL = "download_url"
    }

    var decodedContent: String? {
        guard let content = content,
              let data = Data(base64Encoded: content, options: .ignoreUnknownCharacters) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - GitHub Commit

struct GitHubCommit: Codable, Identifiable {
    let sha: String
    let commit: CommitDetails
    let author: GitHubUser?
    let committer: GitHubUser?
    let htmlURL: String?

    var id: String { sha }

    enum CodingKeys: String, CodingKey {
        case sha, commit, author, committer
        case htmlURL = "html_url"
    }

    struct CommitDetails: Codable {
        let message: String
        let author: CommitAuthor
        let committer: CommitAuthor
    }

    struct CommitAuthor: Codable {
        let name: String
        let email: String
        let date: String

        var dateFormatted: Date? {
            let formatter = ISO8601DateFormatter()
            return formatter.date(from: date)
        }
    }
}

// MARK: - GitHub OAuth Response

struct GitHubOAuthResponse: Codable {
    let accessToken: String
    let tokenType: String
    let scope: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
    }
}

// MARK: - GitHub Content Update Request

struct GitHubContentUpdateRequest: Codable {
    let message: String
    let content: String // Base64 encoded
    let sha: String? // Required for updates, nil for new files
    let branch: String?

    init(message: String, content: String, sha: String? = nil, branch: String? = nil) {
        self.message = message
        self.content = content.data(using: .utf8)?.base64EncodedString() ?? ""
        self.sha = sha
        self.branch = branch
    }
}

// MARK: - GitHub Auth Mode

enum GitHubAuthMode {
    case authenticated(token: String, user: GitHubUser)
    case readOnly(token: String)

    var token: String {
        switch self {
        case .authenticated(let token, _):
            return token
        case .readOnly(let token):
            return token
        }
    }

    var isReadOnly: Bool {
        switch self {
        case .authenticated:
            return false
        case .readOnly:
            return true
        }
    }

    var user: GitHubUser? {
        switch self {
        case .authenticated(_, let user):
            return user
        case .readOnly:
            return nil
        }
    }
}
