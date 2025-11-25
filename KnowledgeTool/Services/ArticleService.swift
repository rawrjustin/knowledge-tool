import Foundation
#if canImport(WebKit)
import WebKit
#endif

actor ArticleService {

    // MARK: - Fetch Article Content
    func fetchArticle(from urlString: String) async throws -> ArticleInfo {
        guard let url = URL(string: urlString), url.scheme != nil else {
            throw KnowledgeToolError.invalidURL
        }

        // Fetch the HTML content
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw KnowledgeToolError.networkError(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode == 200 else {
            throw KnowledgeToolError.networkError(URLError(.badServerResponse))
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw KnowledgeToolError.apiError("Failed to decode HTML content")
        }

        // Extract article content
        let title = extractTitle(from: html)
        let content = extractContent(from: html)
        let publishedDate = extractPublishedDate(from: html)

        guard !content.isEmpty else {
            throw KnowledgeToolError.apiError("Failed to extract article content")
        }

        return ArticleInfo(
            url: urlString,
            title: title,
            content: content,
            publishedDate: publishedDate
        )
    }

    // MARK: - Extract Title
    private func extractTitle(from html: String) -> String? {
        // Try different title patterns
        let patterns = [
            #"<title[^>]*>([^<]+)</title>"#,
            #"<meta\s+property="og:title"\s+content="([^"]+)""#,
            #"<meta\s+name="twitter:title"\s+content="([^"]+)""#,
            #"<h1[^>]*>([^<]+)</h1>"#
        ]

        for pattern in patterns {
            if let match = try? NSRegularExpression(pattern: pattern).firstMatch(
                in: html,
                range: NSRange(html.startIndex..., in: html)
               ),
               match.numberOfRanges > 1 {
                let titleRange = Range(match.range(at: 1), in: html)
                if let titleRange = titleRange {
                    let title = String(html[titleRange])
                    return cleanText(title)
                }
            }
        }

        return nil
    }

    // MARK: - Extract Content
    private func extractContent(from html: String) -> String {
        // Remove script and style tags
        var cleanedHTML = html
        let tagsToRemove = ["script", "style", "nav", "header", "footer", "aside"]

        for tag in tagsToRemove {
            let pattern = "<\(tag)[^>]*>.*?</\(tag)>"
            cleanedHTML = cleanedHTML.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        // Try to find main content area
        let contentPatterns = [
            #"<article[^>]*>(.*?)</article>"#,
            #"<main[^>]*>(.*?)</main>"#,
            #"<div[^>]*class="[^"]*content[^"]*"[^>]*>(.*?)</div>"#,
            #"<div[^>]*id="[^"]*content[^"]*"[^>]*>(.*?)</div>"#
        ]

        var content = ""

        for pattern in contentPatterns {
            if let match = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators).firstMatch(
                in: cleanedHTML,
                range: NSRange(cleanedHTML.startIndex..., in: cleanedHTML)
               ),
               match.numberOfRanges > 1 {
                let contentRange = Range(match.range(at: 1), in: cleanedHTML)
                if let contentRange = contentRange {
                    content = String(cleanedHTML[contentRange])
                    break
                }
            }
        }

        // If no content area found, use the body
        if content.isEmpty {
            let bodyPattern = #"<body[^>]*>(.*?)</body>"#
            if let match = try? NSRegularExpression(pattern: bodyPattern, options: [.dotMatchesLineSeparators, .caseInsensitive]).firstMatch(
                in: cleanedHTML,
                range: NSRange(cleanedHTML.startIndex..., in: cleanedHTML)
               ),
               match.numberOfRanges > 1,
               let bodyRange = Range(match.range(at: 1), in: cleanedHTML) {
                content = String(cleanedHTML[bodyRange])
            } else {
                content = cleanedHTML
            }
        }

        // Remove all HTML tags
        content = content.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )

        // Clean up whitespace
        content = cleanText(content)

        return content
    }

    // MARK: - Extract Published Date
    private func extractPublishedDate(from html: String) -> Date? {
        let patterns = [
            #"<meta\s+property="article:published_time"\s+content="([^"]+)""#,
            #"<time[^>]+datetime="([^"]+)""#,
            #"<meta\s+name="date"\s+content="([^"]+)""#
        ]

        for pattern in patterns {
            if let match = try? NSRegularExpression(pattern: pattern).firstMatch(
                in: html,
                range: NSRange(html.startIndex..., in: html)
               ),
               match.numberOfRanges > 1 {
                let dateRange = Range(match.range(at: 1), in: html)
                if let dateRange = dateRange {
                    let dateString = String(html[dateRange])
                    if let date = parseDate(dateString) {
                        return date
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Parse Date
    private func parseDate(_ dateString: String) -> Date? {
        let formatters = [
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd",
            "MMM dd, yyyy"
        ]

        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: dateString) {
                return date
            }
        }

        return nil
    }

    // MARK: - Clean Text
    private func cleanText(_ text: String) -> String {
        var cleaned = text

        // Decode HTML entities
        cleaned = cleaned.replacingOccurrences(of: "&nbsp;", with: " ")
        cleaned = cleaned.replacingOccurrences(of: "&amp;", with: "&")
        cleaned = cleaned.replacingOccurrences(of: "&lt;", with: "<")
        cleaned = cleaned.replacingOccurrences(of: "&gt;", with: ">")
        cleaned = cleaned.replacingOccurrences(of: "&quot;", with: "\"")
        cleaned = cleaned.replacingOccurrences(of: "&#39;", with: "'")

        // Remove extra whitespace
        cleaned = cleaned.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
