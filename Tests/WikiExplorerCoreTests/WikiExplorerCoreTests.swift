import Foundation
import XCTest
import simd
@testable import WikiExplorerCore

final class LinkTargetTests: XCTestCase {
    func testWikiLinks() {
        XCTAssertEqual(LinkTarget(url: URL(string: "llmwiki://open?wiki=club&page=concepts%2Fgroup-rides")!), .page(wiki: "club", id: "concepts/group-rides"))
        XCTAssertEqual(LinkTarget(url: URL(string: "llmwiki://open?wiki=club&raw=raw%2Fweb%2Fx.html")!), .raw(wiki: "club", path: "raw/web/x.html"))
        XCTAssertEqual(LinkTarget(url: URL(string: "https://example.com/a")!), .external(URL(string: "https://example.com/a")!))
        if case .unsupported = LinkTarget(url: URL(string: "llmwiki://open?wiki=club")!) {} else { XCTFail("missing page/raw is unsupported") }
        if case .unsupported = LinkTarget(url: URL(string: "file:///etc/passwd")!) {} else { XCTFail("file URLs are not followed") }
    }

    func testPageIdFromPath() {
        XCTAssertEqual(WikiPath.pageId(fromPath: "wiki/concepts/x.md"), "concepts/x")
        XCTAssertEqual(WikiPath.pageId(fromPath: "wiki/entities/ada.html"), "entities/ada")
        XCTAssertEqual(WikiPath.pageId(fromPath: "overview"), "overview")
    }
}

final class ShellEnvironmentTests: XCTestCase {
    func testParseIgnoresProfileNoise() {
        var data = Data("Welcome to zsh!\n".utf8)
        data.append(Data(ShellEnvironment.startMarker.utf8))
        data.append(Data("PATH=/opt/homebrew/bin:/usr/bin\u{0}GOOGLE_API_KEY=secret=with=equals\u{0}MULTI=line1\nline2\u{0}".utf8))
        data.append(Data(ShellEnvironment.endMarker.utf8))
        data.append(Data("bye\n".utf8))
        let env = ShellEnvironment.parse(data)
        XCTAssertEqual(env?["PATH"], "/opt/homebrew/bin:/usr/bin")
        XCTAssertEqual(env?["GOOGLE_API_KEY"], "secret=with=equals")
        XCTAssertEqual(env?["MULTI"], "line1\nline2")
        XCTAssertNil(ShellEnvironment.parse(Data("no markers".utf8)))
    }

    func testFindExecutable() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tool = dir.appendingPathComponent("llm-wiki")
        try "#!/bin/sh\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        XCTAssertEqual(ShellEnvironment.findExecutable(named: "llm-wiki", in: ["PATH": "/nonexistent:\(dir.path)"]), tool.path)
        XCTAssertNil(ShellEnvironment.findExecutable(named: "llm-wiki", in: ["PATH": "/nonexistent"]))
    }
}

final class CLIRunnerTests: XCTestCase {
    /// A stand-in for llm-wiki: prints progress on stderr, JSON on stdout, and fails with exit 2 on request.
    private func fakeCLI() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fake-llm-wiki-\(UUID().uuidString)")
        let script = """
        #!/bin/sh
        if [ "$1" = "fail" ]; then echo "wiki: x" >&2; echo "error: Missing required configuration setting LLM_WIKI_MODEL." >&2; exit 2; fi
        echo "step one" >&2
        echo "step two" >&2
        printf '[{"name":"club","root":"/tmp/club","description":"Cycling","healthy":true,"format":"html","pages":15,"pending":0,"lastActivity":"2026-10-17 ingest | X","current":true}]'
        """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func testRunDecodesJsonAndStreamsStderr() async throws {
        let cli = LLMWikiCLI(executable: try fakeCLI(), environment: ["PATH": "/usr/bin:/bin"])
        final class Lines: @unchecked Sendable { var items: [String] = []; let lock = NSLock() }
        let lines = Lines()
        let wikis = try await cli.json([WikiSummary].self, ["wikis", "list", "--json"]) { line in lines.lock.lock(); lines.items.append(line); lines.lock.unlock() }
        XCTAssertEqual(wikis.map(\.name), ["club"])
        XCTAssertEqual(wikis.first?.format, "html")
        XCTAssertEqual(lines.items, ["step one", "step two"])
    }

    func testErrorsCarryTheCliMessageAndExitCode() async throws {
        let cli = LLMWikiCLI(executable: try fakeCLI(), environment: ["PATH": "/usr/bin:/bin"])
        do {
            _ = try await cli.run(["fail"])
            XCTFail("expected an error")
        } catch let e as CLIError {
            XCTAssertEqual(e.exitCode, 2)
            XCTAssertEqual(e.message, "Missing required configuration setting LLM_WIKI_MODEL.")
            XCTAssertEqual(e.kind, "Configuration error")
        }
    }
}

final class ModelDecodingTests: XCTestCase {
    func testQueryResponseWithCitations() throws {
        let json = """
        {"wikis":["a","b"],"question":"q","answer":"x [[a:entities/ada]]","answerHtml":"<p>x <a class=\\"wikilink\\" href=\\"llmwiki://open?wiki=a&amp;page=entities%2Fada\\">ada</a></p>",
         "citations":[{"wiki":"a","id":"entities/ada","title":"Ada","path":"wiki/entities/ada.md"}],"pagesUsed":["a:wiki/entities/ada.md"]}
        """
        let r = try JSONDecoder().decode(QueryResponse.self, from: Data(json.utf8))
        XCTAssertEqual(r.citations.first?.pageId, "entities/ada")
        XCTAssertEqual(r.citations.first?.id, "a:entities/ada")
        XCTAssertNil(r.wiki)
        XCTAssertNil(r.filedAs)
    }

    func testPageViewAndIngest() throws {
        let page = """
        {"id":"concepts/x","path":"wiki/concepts/x.html","title":"X","type":"concept","summary":null,"updated":"2026-10-17","sources":["raw/a.md"],
         "wiki":"club","format":"html","abs":"/tmp/club/wiki/concepts/x.html","frontmatter":{"title":"X","tags":["a"],"n":1},"html":"<h1>X</h1>",
         "links":[{"id":"concepts/y","title":"Y"}],"backlinks":[],"sourceFiles":[{"path":"raw/a.md","abs":"/tmp/club/raw/a.md","exists":true}]}
        """
        let v = try JSONDecoder().decode(PageView.self, from: Data(page.utf8))
        XCTAssertEqual(v.links.first?.id, "concepts/y")
        XCTAssertNil(v.summary)
        let ingest = """
        {"wiki":"club","dryRun":false,"results":[{"source":"raw/web/x.html.md","original":"raw/web/x.html","skipped":false,"title":"T","takeaways":["a"],"changes":[{"op":"create","page":"wiki/entities/e.html","reason":null}]}]}
        """
        let r = try JSONDecoder().decode(IngestResponse.self, from: Data(ingest.utf8))
        XCTAssertEqual(r.results.first?.changes.first?.page, "wiki/entities/e.html")
    }
}

/// Runs the real llm-wiki (when installed) in a throwaway HOME: init, pages, show, search — no LLM calls.
final class RealCLIIntegrationTests: XCTestCase {
    func testAgainstInstalledLlmWiki() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = ShellEnvironment.findExecutable(named: "llm-wiki", in: env) else { throw XCTSkip("llm-wiki is not on PATH") }
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("we-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        var testEnv = env
        testEnv["HOME"] = home.path
        let cli = LLMWikiCLI(executable: URL(fileURLWithPath: path), environment: testEnv)
        try await cli.initWiki(directory: home.appendingPathComponent("w").path, format: "html", name: "w", description: "Test wiki", makeCurrent: false)
        let wikis = try await cli.listWikis()
        XCTAssertEqual(wikis.map(\.name), ["w"])
        XCTAssertEqual(wikis.first?.format, "html")
        let pages = try await cli.pages(wiki: "w")
        XCTAssertEqual(pages.format, "html")
        XCTAssertEqual(pages.pages.count, 0)
        do {
            _ = try await cli.show(wiki: "w", page: "nope")
            XCTFail("expected an error")
        } catch let e as CLIError {
            XCTAssertTrue(e.message.contains("Page not found"), e.message)
        }
        let hits = try await cli.search(wiki: "w", allWikis: false, query: "anything")
        XCTAssertEqual(hits.count, 0)
    }
}

final class ShortcutTests: XCTestCase {
    func testDisplayUsesAppleModifierOrder() {
        XCTAssertEqual(AppShortcuts.newWiki.display, "⇧⌘N")
        XCTAssertEqual(AppShortcuts.openSourceFolder.display, "⌥⇧⌘R")
        XCTAssertEqual(AppShortcuts.sendQuestion.display, "⌘↩")
        XCTAssertEqual(AppShortcut("escape", [], "x", section: .dialogs).display, "Esc")
    }

    func testMenuShortcutsAreUnique() {
        let menu = AppShortcuts.all.filter(\.isMenuCommand)
        let keys = menu.map { "\($0.modifiers.sorted().map(\.symbol).joined())\($0.key)" }
        XCTAssertEqual(Set(keys).count, keys.count, "two menu commands share a shortcut")
        // The system's own shortcuts are not taken by a menu command.
        for reserved in ["⌘q", "⌘w", "⌘m", "⌘,", "⌃⌘s", "⌃⌘f", "⌘h", "⌘c", "⌘v", "⌘x", "⌘a", "⌘z"] {
            XCTAssertFalse(keys.contains(reserved), "\(reserved) is a system shortcut")
        }
    }

    func testFilterAndGrouping() {
        XCTAssertEqual(AppShortcuts.grouped().map(\.section), AppShortcut.Section.allCases)
        let browser = AppShortcuts.grouped(matching: "browser")
        XCTAssertEqual(browser.flatMap(\.shortcuts), [AppShortcuts.openInBrowser])
        XCTAssertEqual(AppShortcuts.grouped(matching: "⇧⌘N").flatMap(\.shortcuts), [AppShortcuts.newWiki])
        XCTAssertTrue(AppShortcuts.grouped(matching: "no such thing").isEmpty)
    }
}

final class TourTests: XCTestCase {
    func testStepsAreCompleteAndDistinct() {
        XCTAssertGreaterThan(Tour.steps.count, 5)
        XCTAssertNil(Tour.steps.first?.target, "the tour opens with a welcome card")
        XCTAssertNil(Tour.steps.last?.target, "and ends with one")
        XCTAssertEqual(Set(Tour.steps.map(\.id)).count, Tour.steps.count)
        for step in Tour.steps {
            XCTAssertFalse(step.title.isEmpty)
            XCTAssertFalse(step.body.isEmpty)
        }
        let targets = Tour.steps.compactMap(\.target)
        XCTAssertEqual(Set(targets).count, targets.count, "each area is visited once")
    }

    func testTourMentionsTheShortcutsItCites() {
        // Shortcuts quoted in the tour text must be real ones.
        let text = Tour.steps.map { $0.body + ($0.tryIt ?? "") }.joined(separator: " ")
        for s in [AppShortcuts.newWiki, AppShortcuts.search, AppShortcuts.openInBrowser, AppShortcuts.showInFinder, AppShortcuts.ask, AppShortcuts.sendQuestion, AppShortcuts.addSources, AppShortcuts.checkSources, AppShortcuts.shortcutsGuide, AppShortcuts.tour, AppShortcuts.graph, AppShortcuts.showInGraph] {
            XCTAssertTrue(text.contains(s.display), "the tour should cite \(s.display) for \(s.title)")
        }
    }
}

final class DotenvFileTests: XCTestCase {
    let sample = """
    # llm-wiki settings
    LLM_WIKI_PROVIDER=gemini
    export LLM_WIKI_MODEL="gemini-3.6-flash"   

    OPENAI_API_KEY='sk-a#b'
    LLM_WIKI_PARSER_MODEL=gpt-5 # inline comment
    not a setting line
    LLM_WIKI_PROVIDER=openai

    """

    func testReadsLikeTheCLI() {
        let f = DotenvFile(text: sample)
        XCTAssertEqual(f["LLM_WIKI_PROVIDER"], "openai", "last occurrence wins")
        XCTAssertEqual(f["LLM_WIKI_MODEL"], "gemini-3.6-flash")
        XCTAssertEqual(f["OPENAI_API_KEY"], "sk-a#b")
        XCTAssertEqual(f["LLM_WIKI_PARSER_MODEL"], "gpt-5")
        XCTAssertEqual(f.keys, ["LLM_WIKI_PROVIDER", "LLM_WIKI_MODEL", "OPENAI_API_KEY", "LLM_WIKI_PARSER_MODEL"])
        XCTAssertEqual(f.text, sample.components(separatedBy: "\n").map { $0 }.dropLast().joined(separator: "\n") + "\n", "unchanged text round-trips")
    }

    func testEditsKeepEverythingElse() {
        var f = DotenvFile(text: sample)
        f.set("LLM_WIKI_PROVIDER", "anthropic")
        f.set("LLM_WIKI_MODEL", "claude-sonnet-5-5")
        f.set("OPENAI_API_KEY", nil)
        f.set("LLM_WIKI_BROWSER", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
        f.set("LLM_WIKI_PARSER_MODEL", "")
        XCTAssertEqual(f.text, """
        # llm-wiki settings
        export LLM_WIKI_MODEL=claude-sonnet-5-5

        not a setting line
        LLM_WIKI_PROVIDER=anthropic
        LLM_WIKI_BROWSER="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

        """)
        // What the app writes, the CLI's parser reads back.
        let back = DotenvFile(text: f.text)
        XCTAssertEqual(back["LLM_WIKI_BROWSER"], "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
        XCTAssertNil(back["LLM_WIKI_PARSER_MODEL"], "an empty value removes the key: no empty settings")
        var q = DotenvFile(text: "")
        q.set("X", "say \"hi\" # not a comment")
        XCTAssertEqual(DotenvFile(text: q.text)["X"], "say \"hi\" # not a comment")
    }

    func testSaveCreatesPrivateFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dotenv-\(UUID().uuidString)/llm-wiki")
        let url = dir.appendingPathComponent(".env")
        XCTAssertEqual(try DotenvFile.load(from: url), DotenvFile(text: ""), "missing file reads as empty")
        var f = DotenvFile(text: "")
        f.set("LLM_WIKI_PROVIDER", "gemini")
        try f.save(to: url)
        try f.save(to: url) // replaces an existing file too
        XCTAssertEqual(try DotenvFile.load(from: url)["LLM_WIKI_PROVIDER"], "gemini")
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
        let dirMode = try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int
        XCTAssertEqual(dirMode, 0o700)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), [".env"], "no temporary files left")
    }

    func testCatalogue() {
        XCTAssertEqual(Set(SettingsCatalog.all.map(\.key)).count, SettingsCatalog.all.count)
        XCTAssertTrue(SettingsCatalog.isSecret("OPENAI_API_KEY"))
        XCTAssertTrue(SettingsCatalog.isSecret("MY_SERVICE_TOKEN"))
        XCTAssertFalse(SettingsCatalog.isSecret("LLM_WIKI_MODEL"))
        XCTAssertEqual(SettingsCatalog.providersInUse(["LLM_WIKI_PROVIDER": "mlx", "LLM_WIKI_PARSER_PROVIDER": "gemini"]), ["mlx", "openai", "gemini"])
        XCTAssertEqual(DotenvFile.defaultURL(home: URL(fileURLWithPath: "/Users/x")).path, "/Users/x/.tool-agents/llm-wiki/.env")
    }
}

final class GraphTests: XCTestCase {
    let json = """
    { "wiki": "demo", "format": "html",
      "nodes": [
        { "id": "a", "title": "A", "type": "entity", "summary": null, "degree": 2 },
        { "id": "b", "title": "B", "type": "concept", "summary": "Bee.", "degree": 2 },
        { "id": "c", "title": "C", "type": "concept", "summary": null, "degree": 2 },
        { "id": "d", "title": "D", "type": "source", "summary": null, "degree": 1 },
        { "id": "lonely", "title": "Lonely", "type": "entity", "summary": null, "degree": 0 } ],
      "links": [ { "from": "a", "to": "b" }, { "from": "b", "to": "a" }, { "from": "b", "to": "c" }, { "from": "c", "to": "d" }, { "from": "a", "to": "ghost" } ],
      "sources": [ { "path": "raw/x.pdf", "exists": true, "pages": ["a", "d"] } ],
      "missing": [ { "from": "a", "target": "ghost" } ] }
    """

    func graph() throws -> WikiGraph { try JSONDecoder().decode(WikiGraph.self, from: Data(json.utf8)) }

    func testBuildMergesDirectionsAndAddsSources() throws {
        let m = GraphModel.build(from: try graph(), includeSources: false)
        XCTAssertEqual(m.items.map(\.id), ["a", "b", "c", "d", "lonely"])
        XCTAssertEqual(m.edges.count, 3, "a↔b is one edge")
        XCTAssertEqual(m.edges.filter(\.mutual).count, 1)
        XCTAssertEqual(m.items.map(\.degree), [1, 2, 2, 1, 0])
        let s = GraphModel.build(from: try graph(), includeSources: true)
        let file = try XCTUnwrap(s.index(of: "raw:raw/x.pdf"))
        XCTAssertEqual(s.items[file].kind, GraphModel.fileKind)
        XCTAssertEqual(s.items[file].rawPath, "raw/x.pdf")
        XCTAssertEqual(s.items[file].title, "x.pdf")
        XCTAssertEqual(s.neighbours(of: file).map { s.items[$0].id }.sorted(), ["a", "d"])
    }

    func testNeighbourhoodAndHiddenKinds() throws {
        let one = GraphModel.build(from: try graph(), includeSources: false, focus: "a", depth: 1)
        XCTAssertEqual(one.items.map(\.id), ["a", "b"])
        let two = GraphModel.build(from: try graph(), includeSources: false, focus: "a", depth: 2)
        XCTAssertEqual(two.items.map(\.id), ["a", "b", "c"])
        let viaFile = GraphModel.build(from: try graph(), includeSources: true, focus: "a", depth: 2)
        XCTAssertTrue(viaFile.items.contains { $0.id == "d" }, "pages citing the same file are two steps apart")
        let noConcepts = GraphModel.build(from: try graph(), includeSources: false, hiddenKinds: ["concept"], focus: "a", depth: 3)
        XCTAssertEqual(noConcepts.items.map(\.id), ["a"], "a hidden kind also cuts the paths through it")
    }

    func testSimulationSettlesWithLinkedItemsCloser() throws {
        let m = GraphModel.build(from: try graph(), includeSources: false)
        let kinds = Array(Set(m.items.map(\.kind))).sorted()
        let sim = ForceSimulation(count: m.items.count, edges: m.edges.map { ($0.a, $0.b) }, groups: m.items.map { kinds.firstIndex(of: $0.kind)! }, radii: m.items.map { _ in 6 })
        var ticks = 0
        while !sim.isSettled && ticks < 2000 { sim.tick(); ticks += 1 }
        XCTAssertTrue(sim.isSettled, "the layout comes to rest")
        func dist(_ a: String, _ b: String) -> Double {
            let d = sim.positions[m.index(of: a)!] - sim.positions[m.index(of: b)!]
            return (d.x * d.x + d.y * d.y).squareRoot()
        }
        // On average, linked items end up closer than unlinked ones.
        let ids = m.items.map(\.id)
        let linked = Set(m.edges.map { "\(ids[$0.a])|\(ids[$0.b])" })
        var near = [Double](), far = [Double]()
        for i in 0..<ids.count { for j in (i + 1)..<ids.count {
            (linked.contains("\(ids[i])|\(ids[j])") ? { near.append(dist(ids[i], ids[j])) } : { far.append(dist(ids[i], ids[j])) })()
        } }
        XCTAssertLessThan(near.reduce(0, +) / Double(near.count), far.reduce(0, +) / Double(far.count))
        for i in 0..<sim.count { for j in (i + 1)..<sim.count { XCTAssertGreaterThan(simd_distance(sim.positions[i], sim.positions[j]), 6, "items do not overlap") } }
        XCTAssertEqual(sim.item(at: sim.positions[2]), 2)
        XCTAssertNil(sim.item(at: SIMD2(1e6, 1e6)))
    }

    func testFixedItemsStayAndPreviousPositionsAreKept() {
        let sim = ForceSimulation(count: 3, edges: [(0, 1), (1, 2)], groups: [0, 0, 0], radii: [5, 5, 5])
        sim.fixed[0] = SIMD2(100, 100)
        for _ in 0..<50 { sim.tick() }
        XCTAssertEqual(sim.positions[0], SIMD2(100, 100))
        let again = ForceSimulation(count: 4, edges: [(0, 1), (1, 2), (2, 3)], groups: [0, 0, 0, 0], radii: [5, 5, 5, 5], previous: [0: sim.positions[0], 1: sim.positions[1], 2: sim.positions[2]])
        XCTAssertEqual(again.positions[1], sim.positions[1])
        XCTAssertLessThan(simd_distance(again.positions[3], again.positions[2]), 20, "a new item starts beside its neighbour")
    }
}
