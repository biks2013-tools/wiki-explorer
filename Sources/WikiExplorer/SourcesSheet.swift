import SwiftUI
import WikiExplorerCore

/// Checks the selected wiki's outside sources (downloaded URLs, files copied in from elsewhere) for changes
/// by SHA-256, and re-ingests the changed ones (`llm-wiki sources check` / `sources update`).
struct SourcesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var checks: [SourceCheck] = []
    @State private var checking = false
    @State private var updating = false
    @State private var log: [String] = []
    @State private var updated: [SourceUpdate]?

    private var changed: [SourceCheck] { checks.filter { $0.status == "changed" } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Outside sources of \(model.selectedWikiName ?? "")").font(.title3.weight(.semibold))
            Text("Web pages and files added from outside the wiki are compared with the copy the wiki was built from (SHA-256; web pages by their text). Changed sources are kept as a new copy and compiled into the wiki again.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Group {
                if checking && checks.isEmpty {
                    HStack { ProgressView().controlSize(.small); Text("Checking…").foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else if checks.isEmpty {
                    ContentUnavailableView("No outside sources", systemImage: "link", description: Text("Web pages (URLs) and files added from outside the wiki folder are tracked here."))
                        .frame(minHeight: 160)
                } else {
                    List(checks) { c in row(c) }
                        .listStyle(.bordered(alternatesRowBackgrounds: true))
                        .frame(minHeight: 180, maxHeight: 300)
                }
            }
            if let updated {
                VStack(alignment: .leading, spacing: 4) {
                    Text(updated.isEmpty ? "Nothing to update." : "Updated \(updated.count) source(s):").font(.callout.weight(.semibold))
                    ForEach(updated, id: \.self) { u in
                        Text("• \(u.title ?? u.source) — \(u.changes.count) page(s) written").font(.callout)
                    }
                }
            }
            if updating || (!log.isEmpty && updated == nil) {
                Text(log.last ?? "Starting…").font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack {
                Button("Check Again") { Task { await check() } }.disabled(checking || updating)
                if updating { ProgressView().controlSize(.small) }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction).disabled(updating)
                Button(changed.isEmpty ? "Up to Date" : "Update \(changed.count) Changed") { Task { await update() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(changed.isEmpty || checking || updating)
            }
        }
        .padding(20)
        .frame(width: 640)
        .task { await check() }
    }

    private func row(_ c: SourceCheck) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(c.status)).foregroundStyle(color(c.status)).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: c.kind == "url" ? "globe" : "doc").foregroundStyle(.secondary).font(.caption)
                    Text(c.origin).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
                Text("\(c.status)\(c.detail.map { " — \($0)" } ?? "") · \(c.raw)").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private func icon(_ status: String) -> String {
        switch status {
        case "unchanged": return "checkmark.circle"
        case "changed": return "arrow.triangle.2.circlepath.circle.fill"
        case "missing": return "questionmark.circle"
        default: return "exclamationmark.triangle"
        }
    }

    private func color(_ status: String) -> Color {
        switch status {
        case "unchanged": return .green
        case "changed": return .orange
        default: return .red
        }
    }

    private func check() async {
        guard let cli = model.cli, let wiki = model.selectedWikiName else { return }
        checking = true
        defer { checking = false }
        do {
            checks = try await cli.checkSources(wiki: wiki).sources
        } catch {
            model.report(error)
        }
    }

    private func update() async {
        guard let cli = model.cli, let wiki = model.selectedWikiName else { return }
        updating = true
        log = []
        defer { updating = false }
        do {
            let r = try await cli.updateSources(wiki: wiki) { line in Task { @MainActor in log.append(line) } }
            updated = r.updated
            await model.refreshAfterChange()
            await check()
        } catch {
            model.report(error)
        }
    }
}
