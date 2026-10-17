import SwiftUI
import UniformTypeIdentifiers
import WikiExplorerCore

/// Adds files and web pages (URLs) to the selected wiki through `llm-wiki ingest`.
struct IngestSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var files: [URL] = []
    @State private var urlText = ""
    @State private var dryRun = false
    @State private var render = false
    @State private var running = false
    @State private var log: [String] = []
    @State private var result: IngestResponse?
    @State private var dropTargeted = false

    static let accepted = "md, txt, csv, json, html, rst, org, pdf, docx, pptx, xlsx, png, jpg, gif, webp"

    private var urls: [String] {
        urlText.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var invalidURLs: [String] { urls.filter { !($0.hasPrefix("http://") || $0.hasPrefix("https://")) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add sources to \(model.selectedWikiName ?? "")").font(.title3.weight(.semibold))
            if result == nil {
                form
            } else {
                results
            }
            if running || !log.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(log.enumerated()), id: \.offset) { i, line in
                                Text(line).font(.caption.monospaced()).foregroundStyle(.secondary).id(i)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 110)
                    .padding(6)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                    .onChange(of: log.count) { _, n in proxy.scrollTo(n - 1) }
                }
            }
            HStack {
                if running { ProgressView().controlSize(.small); Text("The LLM is compiling the sources — this can take a minute per source.").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button(result == nil ? "Cancel" : "Done") { dismiss() }.keyboardShortcut(.cancelAction).disabled(running)
                if result == nil {
                    Button(dryRun ? "Preview" : "Add to Wiki") { run() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .help("⌘↩")
                        .buttonStyle(.borderedProminent)
                        .disabled(running || (files.isEmpty && urls.isEmpty) || !invalidURLs.isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 600)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Files") {
                VStack(alignment: .leading, spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                            .foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
                        VStack(spacing: 4) {
                            Image(systemName: "tray.and.arrow.down").font(.title2).foregroundStyle(.secondary)
                            Text("Drop files here or").foregroundStyle(.secondary)
                            Button("Choose Files…") { chooseFiles() }
                        }
                        .padding(10)
                    }
                    .frame(height: 100)
                    .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                        for p in providers {
                            _ = p.loadObject(ofClass: URL.self) { url, _ in
                                if let url { Task { @MainActor in if !files.contains(url) { files.append(url) } } }
                            }
                        }
                        return true
                    }
                    ForEach(files, id: \.self) { f in
                        HStack {
                            Image(systemName: "doc")
                            Text(f.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { files.removeAll { $0 == f } } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless)
                        }
                        .font(.callout)
                    }
                    Text("Accepted: \(Self.accepted). PDF, Word, PowerPoint and images are converted by the parser model; Excel locally.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(4)
            }
            GroupBox("Web pages and online documents") {
                VStack(alignment: .leading, spacing: 6) {
                    TextEditor(text: $urlText)
                        .font(.callout.monospaced())
                        .frame(height: 64)
                        .scrollContentBackground(.hidden)
                        .overlay(alignment: .topLeading) {
                            if urlText.isEmpty { Text("https://… — one URL per line").foregroundStyle(.tertiary).padding(.leading, 5).allowsHitTesting(false) }
                        }
                    if !invalidURLs.isEmpty {
                        Text("Not a web address: \(invalidURLs.joined(separator: ", "))").font(.caption).foregroundStyle(.red)
                    } else {
                        Text("Each page is downloaded into raw/web/ and kept as it was; the wiki cites it with its URL. Pages that build their content with JavaScript are printed to PDF in a headless browser (LLM_WIKI_BROWSER).").font(.caption).foregroundStyle(.secondary)
                        Toggle("Save every page as PDF (render it in the browser first)", isOn: $render)
                    }
                }
                .padding(4)
            }
            Toggle("Preview only — show the pages the LLM would write, without changing the wiki", isOn: $dryRun)
        }
    }

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if result?.dryRun == true { Label("Preview — nothing was written.", systemImage: "eye").foregroundStyle(.secondary) }
                ForEach(result?.results ?? [], id: \.self) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title ?? item.source).font(.headline)
                        Text(item.skipped ? "Already in the wiki — unchanged, skipped." : item.original.map { "\(item.source) (converted from \($0))" } ?? item.source)
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(item.takeaways, id: \.self) { t in Text("• \(t)").font(.callout) }
                        ForEach(item.changes, id: \.self) { c in
                            Button {
                                guard let wiki = model.selectedWikiName, result?.dryRun == false else { return }
                                Task { await model.openPage(PageLocation(wiki: wiki, id: WikiPath.pageId(fromPath: c.page)), recordHistory: true) }
                                dismiss()
                            } label: {
                                Text("\(c.op) \(c.page)").font(.caption.monospaced())
                            }
                            .buttonStyle(.link)
                            .disabled(result?.dryRun == true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 320)
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ["md", "markdown", "txt", "csv", "json", "html", "htm", "rst", "org", "pdf", "docx", "pptx", "xlsx", "png", "jpg", "jpeg", "gif", "webp"].compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK {
            for url in panel.urls where !files.contains(url) { files.append(url) }
        }
    }

    private func run() {
        guard let cli = model.cli, let wiki = model.selectedWikiName else { return }
        running = true
        log = []
        let sources = files.map(\.path) + urls
        let preview = dryRun
        let renderPages = render
        Task {
            defer { running = false }
            do {
                result = try await cli.ingest(wiki: wiki, sources: sources, dryRun: preview, render: renderPages) { line in
                    Task { @MainActor in log.append(line) }
                }
                if !preview { await model.refreshAfterChange() }
            } catch {
                model.report(error)
            }
        }
    }
}
