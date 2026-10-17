import Foundation
import XCTest
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
