// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "WikiExplorer",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic: llm-wiki CLI runner, JSON models, llmwiki:// links, login-shell environment. No UI.
        .target(name: "WikiExplorerCore"),
        // The SwiftUI app: wikis, pages, search, ask, ingest, new wiki, settings.
        .executableTarget(name: "WikiExplorer", dependencies: ["WikiExplorerCore"]),
        .testTarget(name: "WikiExplorerCoreTests", dependencies: ["WikiExplorerCore"]),
    ]
)
