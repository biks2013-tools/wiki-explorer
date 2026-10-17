import SwiftUI
import WikiExplorerCore

/// Pages of the selected wiki grouped by type, or full-text search results while searching.
struct PageListColumn: View {
    @Environment(AppModel.self) private var model
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        @Bindable var model = model
        Group {
            if model.selectedWiki == nil {
                ContentUnavailableView("Select a wiki", systemImage: "sidebar.left")
            } else if !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                searchResults
            } else {
                pageList
            }
        }
        .navigationTitle(model.selectedWikiName ?? "Wiki Explorer")
        .navigationSubtitle(subtitle)
        .searchable(text: $model.searchText, placement: .toolbar, prompt: model.searchAllWikis ? "Search all wikis" : "Search this wiki")
        .onChange(of: model.searchText) { _, _ in scheduleSearch() }
        .onChange(of: model.searchAllWikis) { _, _ in scheduleSearch() }
        .onChange(of: model.selectedWikiName) { _, _ in scheduleSearch() }
    }

    private var subtitle: String {
        guard let wiki = model.selectedWiki else { return "" }
        return "\(model.pages.count) pages · \(wiki.format == "html" ? "HTML" : "markdown")"
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { await model.runSearch() }
        }
    }

    private var pageList: some View {
        @Bindable var model = model
        return List(selection: $model.selectedPageId) {
            ForEach(WikiPath.typeSections, id: \.type) { section in
                let members = model.pages.filter { $0.type == section.type }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                if !members.isEmpty {
                    Section("\(section.title) (\(members.count))") {
                        ForEach(members) { page in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(page.title).lineLimit(1)
                                if let summary = page.summary {
                                    Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            .padding(.vertical, 2)
                            .tag(page.id)
                        }
                    }
                }
            }
        }
        .overlay {
            if model.pages.isEmpty, model.selectedWiki?.healthy == true {
                ContentUnavailableView {
                    Label("No pages yet", systemImage: "doc.text")
                } description: {
                    Text("Add documents or web pages and the LLM compiles them into pages.")
                } actions: {
                    Button("Add Sources…") { NotificationCenter.default.post(name: .showIngest, object: nil) }
                }
            }
        }
    }

    private var searchResults: some View {
        @Bindable var model = model
        return List {
            Section {
                Toggle("Search all wikis", isOn: $model.searchAllWikis).toggleStyle(.checkbox)
            }
            Section(model.searching ? "Searching…" : "\(model.searchHits.count) results") {
                ForEach(model.searchHits) { hit in
                    Button {
                        if let id = hit.pageId {
                            Task { await model.openPage(PageLocation(wiki: hit.wiki, id: id), recordHistory: true) }
                        } else {
                            model.openRawFile(wiki: hit.wiki, path: hit.file)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(hit.title).font(.body.weight(.medium)).lineLimit(1)
                                if model.searchAllWikis {
                                    Text(hit.wiki).font(.caption2).padding(.horizontal, 5).background(.quaternary, in: Capsule())
                                }
                                if hit.layer == "raw" { Image(systemName: "doc").font(.caption).foregroundStyle(.secondary).help("Raw source file") }
                            }
                            if !hit.heading.isEmpty, hit.heading != hit.title {
                                Text(hit.heading).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Text(hit.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
