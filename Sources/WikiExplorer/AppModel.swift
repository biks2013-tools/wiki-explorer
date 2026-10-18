import AppKit
import Foundation
import Observation
import WikiExplorerCore

/// A page shown in the detail column, remembered for back/forward navigation.
struct PageLocation: Hashable {
    let wiki: String
    let id: String
}

/// One question asked in this session, with its answer.
struct AskEntry: Identifiable {
    let id = UUID()
    let question: String
    let wikis: [String]
    let response: QueryResponse
}

/// What the detail column shows.
enum DetailMode: String {
    case page, graph
}

enum SetupState: Equatable {
    case starting
    case ready(version: String)
    case failed(String)
}

@MainActor
@Observable
final class AppModel {
    // Setup
    var setup: SetupState = .starting
    private(set) var cli: LLMWikiCLI?
    private(set) var executablePath: String?

    // Wikis and pages
    var wikis: [WikiSummary] = []
    var selectedWikiName: String? {
        didSet {
            guard oldValue != selectedWikiName else { return }
            if !searchAllWikis { searchText = "" }
            graph = nil
            Task { await loadPages() }
        }
    }
    var pages: [PageSummary] = []
    var pagesFormat: String?
    var selectedPageId: String? {
        didSet {
            guard oldValue != selectedPageId, let id = selectedPageId, let wiki = selectedWikiName else { return }
            if current != PageLocation(wiki: wiki, id: id) { Task { await openPage(PageLocation(wiki: wiki, id: id), recordHistory: true) } }
        }
    }
    var pageView: PageView?
    var loadingPage = false

    // Graph
    var detailMode: DetailMode = .page
    var graph: WikiGraph?
    var loadingGraph = false
    private var graphWiki: String?

    // Search
    var searchText = ""
    var searchAllWikis = false
    var searchHits: [SearchHit] = []
    var searching = false

    // Ask
    var askHistory: [AskEntry] = []
    var asking = false
    var askLog: [String] = []
    var showAsk = false

    // Errors
    var errorMessage: String?

    // History
    private(set) var current: PageLocation?
    /// A page being opened in another wiki: loading that wiki's pages must not open its first page instead.
    private var pending: PageLocation?
    private var back: [PageLocation] = []
    private var forward: [PageLocation] = []
    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }

    var isReady: Bool { if case .ready = setup { return true } else { return false } }

    var selectedWiki: WikiSummary? { wikis.first { $0.name == selectedWikiName } }

    // MARK: - Setup

    /// Finds `llm-wiki` and the environment to run it with, then loads the wikis.
    func bootstrap() async {
        setup = .starting
        do {
            let env = try await Task.detached { try Self.resolveEnvironment() }.value
            let explicit = UserDefaults.standard.string(forKey: SettingsKeys.executablePath)?.trimmingCharacters(in: .whitespaces)
            let path: String
            if let explicit, !explicit.isEmpty {
                guard FileManager.default.isExecutableFile(atPath: explicit) else {
                    throw CLIError(exitCode: -1, message: "The llm-wiki executable set in Settings does not exist or is not executable: \(explicit)", arguments: [])
                }
                path = explicit
            } else if let found = ShellEnvironment.findExecutable(named: "llm-wiki", in: env) {
                path = found
            } else {
                throw CLIError(exitCode: -1, message: "llm-wiki was not found on your shell's PATH. Install it from the wiki-v2 project with `pnpm link:global`, or set its path in Settings.", arguments: [])
            }
            let cli = LLMWikiCLI(executable: URL(fileURLWithPath: path), environment: env)
            let version = try await cli.version()
            self.cli = cli
            self.executablePath = path
            setup = .ready(version: version)
            await reloadWikis()
        } catch {
            setup = .failed(error.localizedDescription)
        }
    }

    /// The login shell's environment; with WIKI_EXPLORER_INHERIT_ENV=1 (launched from a terminal) the process's own.
    nonisolated static func resolveEnvironment() throws -> [String: String] {
        let own = ProcessInfo.processInfo.environment
        if own["WIKI_EXPLORER_INHERIT_ENV"] == "1" { return own }
        return try ShellEnvironment.capture()
    }

    // MARK: - Wikis and pages

    func reloadWikis() async {
        guard let cli else { return }
        do {
            let list = try await cli.listWikis()
            wikis = list
            if selectedWikiName == nil || !list.contains(where: { $0.name == selectedWikiName }) {
                selectedWikiName = (list.first { $0.current == true && $0.healthy } ?? list.first { $0.healthy })?.name
            }
        } catch {
            report(error)
        }
    }

    func loadPages() async {
        pages = []
        pagesFormat = nil
        searchHits = []
        guard let cli, let wiki = selectedWikiName, selectedWiki?.healthy == true else { return }
        do {
            let r = try await cli.pages(wiki: wiki)
            guard wiki == selectedWikiName else { return }
            pages = r.pages
            pagesFormat = r.format
            if let current, current.wiki == wiki, pages.contains(where: { $0.id == current.id }) { return }
            if pending?.wiki == wiki { return }
            if let first = pages.first(where: { $0.type == "overview" }) ?? pages.first(where: { $0.type == "source" }) ?? pages.first {
                await openPage(PageLocation(wiki: wiki, id: first.id), recordHistory: true)
            } else {
                pageView = nil
                current = nil
            }
        } catch {
            report(error)
        }
    }

    func openPage(_ location: PageLocation, recordHistory: Bool) async {
        guard let cli else { return }
        pending = location
        if location.wiki != selectedWikiName {
            selectedWikiName = location.wiki
        }
        loadingPage = true
        defer {
            loadingPage = false
            if pending == location { pending = nil }
        }
        do {
            let view = try await cli.show(wiki: location.wiki, page: location.id)
            if recordHistory, let current, current != location {
                back.append(current)
                forward.removeAll()
            }
            current = location
            pageView = view
            if selectedPageId != location.id { selectedPageId = location.id }
        } catch {
            report(error)
        }
    }

    func goBack() {
        guard let target = back.popLast() else { return }
        if let current { forward.append(current) }
        Task { await openPage(target, recordHistory: false) }
    }

    func goForward() {
        guard let target = forward.popLast() else { return }
        if let current { back.append(current) }
        Task { await openPage(target, recordHistory: false) }
    }

    /// Follows a link clicked in a page or an answer.
    func follow(_ url: URL) {
        switch LinkTarget(url: url) {
        case let .page(wiki, id):
            Task { await openPage(PageLocation(wiki: wiki, id: id), recordHistory: true) }
        case let .raw(wiki, path):
            openRawFile(wiki: wiki, path: path)
        case let .external(u):
            NSWorkspace.shared.open(u)
        case .unsupported:
            break
        }
    }

    func openRawFile(wiki: String, path: String) {
        guard let root = wikis.first(where: { $0.name == wiki })?.root else { return }
        let url = URL(fileURLWithPath: root).appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "\(path) does not exist in \(wiki)."
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Opening outside the app

    /// The file of a page of a wiki (`path` relative to the wiki root, e.g. `wiki/concepts/x.html`).
    func fileURL(wiki: String, path: String) -> URL? {
        guard let root = wikis.first(where: { $0.name == wiki })?.root else { return nil }
        return URL(fileURLWithPath: root).appendingPathComponent(path)
    }

    /// Opens an HTML page file in the default web browser (not whatever app .html files open with).
    func openInBrowser(_ file: URL) {
        guard FileManager.default.fileExists(atPath: file.path) else {
            errorMessage = "\(file.path) does not exist."
            return
        }
        guard let browser = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) else {
            errorMessage = "No default web browser is set on this Mac (System Settings › Desktop & Dock › Default web browser)."
            return
        }
        NSWorkspace.shared.open([file], withApplicationAt: browser, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { Task { @MainActor in self.report(error) } }
        }
    }

    /// Selects files in Finder (one Finder window per folder).
    func showInFinder(_ files: [URL]) {
        let existing = files.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else {
            errorMessage = files.count == 1 ? "\(files[0].path) does not exist." : "None of these files exist."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting(existing)
    }

    /// The open page is an HTML file that a browser can show.
    var pageOpensInBrowser: Bool { pageView?.format == "html" }

    func openCurrentPageInBrowser() {
        guard let page = pageView, page.format == "html" else { return }
        openInBrowser(URL(fileURLWithPath: page.abs))
    }

    func showCurrentPageInFinder() {
        guard let page = pageView else { return }
        showInFinder([URL(fileURLWithPath: page.abs)])
    }

    func showCurrentSourcesInFinder() {
        guard let page = pageView else { return }
        showInFinder(page.sourceFiles.filter(\.exists).map { URL(fileURLWithPath: $0.abs) })
    }

    /// Puts the cursor in the toolbar's search field.
    func focusSearch() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow, let field = NSWindow.searchField(in: window) else { return }
        window.makeFirstResponder(field)
    }

    // MARK: - Graph

    /// Loads the selected wiki's graph (once per wiki unless `force`).
    func loadGraph(force: Bool = false) async {
        guard let cli, let wiki = selectedWikiName, selectedWiki?.healthy == true else {
            graph = nil
            return
        }
        if !force, graph != nil, graphWiki == wiki { return }
        loadingGraph = true
        defer { loadingGraph = false }
        do {
            let g = try await cli.graph(wiki: wiki)
            guard wiki == selectedWikiName else { return }
            graphWiki = wiki
            graph = g
        } catch {
            report(error)
        }
    }

    func toggleGraph() {
        detailMode = detailMode == .graph ? .page : .graph
    }

    /// The graph, gathered round the open page.
    func showCurrentPageInGraph() {
        detailMode = .graph
        DispatchQueue.main.async { NotificationCenter.default.post(name: .graphCommand, object: "neighbourhood") }
    }

    // MARK: - Search

    func runSearch() async {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cli, !q.isEmpty else {
            searchHits = []
            return
        }
        searching = true
        defer { searching = false }
        do {
            let hits = try await cli.search(wiki: selectedWikiName, allWikis: searchAllWikis, query: q)
            if q == searchText.trimmingCharacters(in: .whitespacesAndNewlines) { searchHits = hits }
        } catch {
            report(error)
        }
    }

    // MARK: - Ask

    func ask(question: String, wikis: [String], file: Bool) async {
        guard let cli, !wikis.isEmpty else { return }
        asking = true
        askLog = []
        defer { asking = false }
        do {
            let response = try await cli.query(wikis: wikis, question: question, file: file) { line in
                Task { @MainActor in self.askLog.append(line) }
            }
            askHistory.insert(AskEntry(question: question, wikis: wikis, response: response), at: 0)
            if file { await refreshAfterChange() }
        } catch {
            report(error)
        }
    }

    // MARK: - Changes

    /// After an ingest, a filed answer or a new wiki: reload counts, pages and the open page.
    func refreshAfterChange() async {
        await reloadWikis()
        let keep = current
        await loadPages()
        if let keep, keep.wiki == selectedWikiName { await openPage(keep, recordHistory: false) }
        if graph != nil || detailMode == .graph { await loadGraph(force: true) }
    }

    func report(_ error: Error) {
        if let e = error as? CLIError {
            errorMessage = e.exitCode == 2 ? "\(e.kind): \(e.message)\n\nSettings live in ~/.tool-agents/llm-wiki/.env (see `llm-wiki config`)." : e.message
        } else {
            errorMessage = error.localizedDescription
        }
    }
}

enum SettingsKeys {
    static let executablePath = "llmWikiExecutablePath"
}
