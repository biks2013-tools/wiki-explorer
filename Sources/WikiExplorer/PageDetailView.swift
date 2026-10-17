import SwiftUI
import WikiExplorerCore

/// The open page: rendered body, metadata, outgoing links, backlinks and source files.
struct PageDetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let page = model.pageView {
            VStack(spacing: 0) {
                header(page)
                Divider()
                HTMLView(html: page.html, baseURL: model.selectedWiki.map { URL(fileURLWithPath: $0.root, isDirectory: true) }) { model.follow($0) }
                    .overlay(alignment: .top) { if model.loadingPage { ProgressView().controlSize(.small).padding(6) } }
                Divider()
                RelationsBar(page: page)
            }
            .navigationTitle(page.title)
        } else if model.loadingPage {
            ProgressView()
        } else {
            ContentUnavailableView("Select a page", systemImage: "doc.richtext", description: Text("Pick a page from the list, search, or ask a question."))
        }
    }

    private func header(_ page: PageView) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(page.type.capitalized)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
            if let updated = page.updated { Text("updated \(updated)").font(.caption).foregroundStyle(.secondary) }
            Text(page.path).font(.caption.monospaced()).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: page.abs)]) } label: { Image(systemName: "folder") }
                .buttonStyle(.borderless).help("Reveal the page file in Finder")
            Button { NSWorkspace.shared.open(URL(fileURLWithPath: page.abs)) } label: { Image(systemName: page.format == "html" ? "safari" : "square.and.pencil") }
                .buttonStyle(.borderless).help(page.format == "html" ? "Open the page in the browser" : "Open the page in its default editor")
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

/// Backlinks, outgoing links and the raw sources of the open page.
struct RelationsBar: View {
    @Environment(AppModel.self) private var model
    let page: PageView

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            column("Linked from", systemImage: "arrow.uturn.left", empty: "No other page links here") {
                ForEach(page.backlinks) { ref in pageButton(ref) }
            } isEmpty: { page.backlinks.isEmpty }
            column("Links to", systemImage: "arrow.right", empty: "No outgoing links") {
                ForEach(page.links) { ref in pageButton(ref) }
            } isEmpty: { page.links.isEmpty }
            column("Sources", systemImage: "doc.text", empty: "No sources recorded") {
                ForEach(page.sourceFiles) { file in
                    Button {
                        model.openRawFile(wiki: page.wiki, path: file.path)
                    } label: {
                        Label(file.path, systemImage: file.exists ? "doc" : "questionmark.square.dashed").lineLimit(1).truncationMode(.middle)
                    }
                    .buttonStyle(.link)
                    .disabled(!file.exists)
                    .help(file.exists ? "Open \(file.path)" : "\(file.path) is not in raw/")
                }
            } isEmpty: { page.sourceFiles.isEmpty }
        }
        .font(.callout)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxHeight: 150, alignment: .top)
    }

    private func pageButton(_ ref: PageRef) -> some View {
        Button(ref.title) {
            Task { await model.openPage(PageLocation(wiki: page.wiki, id: ref.id), recordHistory: true) }
        }
        .buttonStyle(.link)
        .lineLimit(1)
        .help(ref.id)
    }

    private func column<Content: View>(_ title: String, systemImage: String, empty: String, @ViewBuilder content: () -> Content, isEmpty: () -> Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    if isEmpty() { Text(empty).foregroundStyle(.tertiary) } else { content() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
