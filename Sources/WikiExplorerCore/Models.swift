import Foundation

// JSON shapes of the `llm-wiki ... --json` commands the app uses. See `llm-wiki guide output`.

/// One entry of `llm-wiki wikis list --json`.
public struct WikiSummary: Decodable, Identifiable, Hashable, Sendable {
    public let name: String
    public let root: String
    public let description: String?
    public let healthy: Bool
    public let problem: String?
    public let format: String?
    public let pages: Int?
    public let pending: Int?
    public let lastActivity: String?
    public let current: Bool?
    public var id: String { name }

    public init(name: String, root: String, description: String? = nil, healthy: Bool = true, problem: String? = nil, format: String? = nil, pages: Int? = nil, pending: Int? = nil, lastActivity: String? = nil, current: Bool? = nil) {
        self.name = name; self.root = root; self.description = description; self.healthy = healthy; self.problem = problem
        self.format = format; self.pages = pages; self.pending = pending; self.lastActivity = lastActivity; self.current = current
    }
}

/// One page of `llm-wiki pages --json`.
public struct PageSummary: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let path: String
    public let title: String
    public let type: String
    public let summary: String?
    public let updated: String?
    public let sources: [String]
}

/// `llm-wiki pages --json`.
public struct PagesResponse: Decodable, Sendable {
    public let wiki: String
    public let format: String
    public let root: String
    public let pages: [PageSummary]
}

public struct PageRef: Decodable, Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
}

public struct SourceFile: Decodable, Hashable, Sendable, Identifiable {
    public let path: String
    public let abs: String
    public let exists: Bool
    public var id: String { path }
}

/// `llm-wiki show <page> --json`: a page rendered for display, with links and backlinks.
public struct PageView: Decodable, Sendable, Equatable {
    public let wiki: String
    public let format: String
    public let id: String
    public let path: String
    public let abs: String
    public let title: String
    public let type: String
    public let summary: String?
    public let updated: String?
    public let sources: [String]
    /// Sanitised HTML of the body; wiki links are `llmwiki://open?...` URLs.
    public let html: String
    public let links: [PageRef]
    public let backlinks: [PageRef]
    public let sourceFiles: [SourceFile]
}

/// A page cited by a query answer.
public struct Citation: Decodable, Hashable, Sendable, Identifiable {
    public let wiki: String
    public let pageId: String
    public let title: String
    public let path: String
    public var id: String { "\(wiki):\(pageId)" }

    enum CodingKeys: String, CodingKey { case wiki, pageId = "id", title, path }
}

/// `llm-wiki query --json` for one wiki (`wiki`) or several (`wikis`).
public struct QueryResponse: Decodable, Sendable {
    public let wiki: String?
    public let wikis: [String]?
    public let question: String
    /// The answer as markdown with `[[...]]` citations.
    public let answer: String
    /// The answer as sanitised HTML; citations are `llmwiki://` links.
    public let answerHtml: String
    public let citations: [Citation]
    public let pagesUsed: [String]
    public let filedAs: String?
}

public struct IngestChange: Decodable, Hashable, Sendable {
    public let op: String
    public let page: String
    public let reason: String?
}

public struct IngestItem: Decodable, Hashable, Sendable {
    public let source: String
    public let original: String?
    public let skipped: Bool
    public let title: String?
    public let takeaways: [String]
    public let changes: [IngestChange]
}

/// `llm-wiki ingest --json`.
public struct IngestResponse: Decodable, Sendable {
    public let wiki: String?
    public let dryRun: Bool
    public let results: [IngestItem]
}

/// One hit of `llm-wiki search --json`.
public struct SearchHit: Decodable, Hashable, Sendable, Identifiable {
    public let wiki: String
    public let file: String
    public let layer: String
    public let title: String
    public let heading: String
    public let score: Double
    public let snippet: String
    public var id: String { "\(wiki):\(file):\(heading):\(score)" }

    /// The page id when the hit is a wiki page (`wiki/concepts/x.md` → `concepts/x`), else nil.
    public var pageId: String? { layer == "wiki" ? WikiPath.pageId(fromPath: file) : nil }
}

public enum WikiPath {
    /// `wiki/concepts/x.md` / `wiki/concepts/x.html` → `concepts/x`.
    public static func pageId(fromPath path: String) -> String {
        var s = path
        if s.hasPrefix("wiki/") { s.removeFirst(5) }
        for ext in [".md", ".html", ".htm"] where s.lowercased().hasSuffix(ext) {
            s.removeLast(ext.count)
            break
        }
        return s
    }

    /// Page types in the order the app lists them, with their section titles.
    public static let typeSections: [(type: String, title: String)] = [
        ("overview", "Overview"), ("entity", "Entities"), ("concept", "Concepts"), ("synthesis", "Syntheses & answers"),
        ("source", "Sources"), ("lint", "Lint reports"), ("other", "Other pages"),
    ]
}

/// One outside source of `llm-wiki sources check --json`: a downloaded URL or a file copied in from outside the wiki.
public struct SourceCheck: Decodable, Hashable, Sendable, Identifiable {
    public let kind: String
    public let origin: String
    public let raw: String
    /// unchanged | changed | missing | error
    public let status: String
    public let detail: String?
    public let since: String
    public var id: String { "\(kind):\(origin)" }
}

public struct SourcesCheckResponse: Decodable, Sendable {
    public let wiki: String?
    public let sources: [SourceCheck]
}

public struct SourceUpdate: Decodable, Hashable, Sendable {
    public let origin: String
    public let source: String
    public let original: String?
    public let skipped: Bool
    public let title: String?
    public let changes: [IngestChange]
}

public struct SourcesUpdateResponse: Decodable, Sendable {
    public let wiki: String?
    public let dryRun: Bool
    public let checked: [SourceCheck]
    public let updated: [SourceUpdate]
}
