import SwiftUI
import WikiExplorerCore

/// The list of registered wikis.
struct WikiSidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var showNewWiki: Bool

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedWikiName) {
            Section("Wikis") {
                ForEach(model.wikis) { wiki in
                    WikiRow(wiki: wiki).tag(wiki.name)
                        .contextMenu {
                            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: wiki.root)]) }
                            if wiki.format == "html" {
                                Button("Open Index in Browser") { NSWorkspace.shared.open(URL(fileURLWithPath: wiki.root).appendingPathComponent("wiki/index.html")) }
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if model.wikis.isEmpty {
                ContentUnavailableView {
                    Label("No wikis yet", systemImage: "books.vertical")
                } description: {
                    Text("Create your first wiki to start collecting knowledge.")
                } actions: {
                    Button("New Wiki…") { showNewWiki = true }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button { showNewWiki = true } label: { Label("New Wiki", systemImage: "plus") }
                    .buttonStyle(.borderless)
                Spacer()
                Button { Task { await model.refreshAfterChange() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Reload the wikis")
            }
            .padding(10)
        }
    }
}

struct WikiRow: View {
    let wiki: WikiSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(wiki.name).font(.body.weight(.medium))
                if wiki.current == true {
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(.secondary).help("Current wiki")
                }
                Spacer(minLength: 4)
                if let format = wiki.format {
                    Text(format == "html" ? "HTML" : "MD")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
            }
            if let description = wiki.description {
                Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if wiki.healthy {
                Text("\(wiki.pages ?? 0) pages\(wiki.pending.map { $0 > 0 ? " · \($0) pending" : "" } ?? "")")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else {
                Label(wiki.problem ?? "Unavailable", systemImage: "exclamationmark.triangle")
                    .font(.caption2).foregroundStyle(.orange).lineLimit(2)
            }
        }
        .padding(.vertical, 3)
        .opacity(wiki.healthy ? 1 : 0.6)
    }
}
