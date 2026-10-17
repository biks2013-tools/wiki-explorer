import Foundation

/// Where a link in a rendered page or answer points. llm-wiki writes wiki links as
/// `llmwiki://open?wiki=<name>&page=<id>` and source links as `llmwiki://open?wiki=<name>&raw=<raw/path>`.
public enum LinkTarget: Equatable, Sendable {
    case page(wiki: String, id: String)
    case raw(wiki: String, path: String)
    case external(URL)
    case unsupported(URL)

    public init(url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "llmwiki" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let value = { (name: String) in items.first(where: { $0.name == name })?.value }
            if let wiki = value("wiki"), let id = value("page"), !id.isEmpty {
                self = .page(wiki: wiki, id: id)
            } else if let wiki = value("wiki"), let raw = value("raw"), !raw.isEmpty {
                self = .raw(wiki: wiki, path: raw)
            } else {
                self = .unsupported(url)
            }
        } else if ["http", "https", "mailto"].contains(scheme) {
            self = .external(url)
        } else {
            self = .unsupported(url)
        }
    }
}
