import SwiftUI
import WikiExplorerCore

/// Ask a question of the selected wiki or of several wikis; answers link to the pages they cite.
struct AskPanel: View {
    @Environment(AppModel.self) private var model
    @State private var question = ""
    @State private var scope: Scope = .selected
    @State private var chosen: Set<String> = []
    @State private var fileAnswer = false
    @State private var shown: AskEntry.ID?

    enum Scope: String, CaseIterable, Identifiable {
        case selected = "This wiki", several = "Several wikis", all = "All wikis"
        var id: String { rawValue }
    }

    private var targetWikis: [String] {
        let healthy = model.wikis.filter(\.healthy).map(\.name)
        switch scope {
        case .selected: return model.selectedWikiName.map { [$0] } ?? []
        case .several: return healthy.filter { chosen.contains($0) }
        case .all: return healthy
        }
    }

    private var entry: AskEntry? { model.askHistory.first { $0.id == shown } ?? model.askHistory.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask").font(.headline)
            TextEditor(text: $question)
                .font(.body)
                .frame(minHeight: 60, maxHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if question.isEmpty { Text("What would you like to know?").foregroundStyle(.tertiary).padding(11).allowsHitTesting(false) }
                }
            Picker("Ask", selection: $scope) { ForEach(Scope.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden()
            if scope == .several {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(model.wikis.filter(\.healthy)) { w in
                            Toggle(w.name, isOn: Binding(get: { chosen.contains(w.name) }, set: { if $0 { chosen.insert(w.name) } else { chosen.remove(w.name) } }))
                                .toggleStyle(.button).controlSize(.small)
                        }
                    }
                }
            }
            HStack {
                Toggle("Save the answer as a page", isOn: $fileAnswer)
                    .disabled(targetWikis.count != 1)
                    .help("Files the answer under syntheses/ in the wiki (one wiki only)")
                Spacer()
                Button {
                    let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        await model.ask(question: q, wikis: targetWikis, file: fileAnswer && targetWikis.count == 1)
                        shown = model.askHistory.first?.id
                    }
                } label: {
                    if model.asking { ProgressView().controlSize(.small) } else { Text("Ask") }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(model.asking || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || targetWikis.isEmpty)
            }
            if model.asking {
                Text(model.askLog.last ?? "Starting…").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Divider()
            if let entry {
                answer(entry)
            } else {
                ContentUnavailableView("No questions yet", systemImage: "questionmark.bubble", description: Text("Answers cite the wiki pages they come from; click a citation to open it."))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func answer(_ entry: AskEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.question).font(.subheadline.weight(.semibold)).lineLimit(3)
                Spacer()
                if model.askHistory.count > 1 {
                    Menu {
                        ForEach(model.askHistory) { e in Button(e.question) { shown = e.id } }
                    } label: { Image(systemName: "clock.arrow.circlepath") }
                        .menuStyle(.borderlessButton).fixedSize().help("Earlier questions")
                }
            }
            Text("from \(entry.wikis.joined(separator: ", "))\(entry.response.filedAs.map { " · saved as \($0)" } ?? "")")
                .font(.caption).foregroundStyle(.secondary)
        }
        HTMLView(html: entry.response.answerHtml, baseURL: nil) { model.follow($0) }
            .frame(minHeight: 200)
        if !entry.response.citations.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Label("Sources", systemImage: "link").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(entry.response.citations) { c in
                    Button {
                        Task { await model.openPage(PageLocation(wiki: c.wiki, id: c.pageId), recordHistory: true) }
                    } label: {
                        HStack(spacing: 6) {
                            Text(c.title)
                            if entry.wikis.count > 1 { Text(c.wiki).font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                    .buttonStyle(.link)
                    .help(c.path)
                }
            }
        }
    }
}
