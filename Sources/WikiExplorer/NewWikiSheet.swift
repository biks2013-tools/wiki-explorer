import SwiftUI
import WikiExplorerCore

/// Creates and registers a new wiki with `llm-wiki init`.
struct NewWikiSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    /// No format is preselected: the choice is the user's, as in the CLI.
    @State private var format: String?
    @State private var parent: URL?
    @State private var makeCurrent = false
    @State private var running = false

    private var slug: String { name.trimmingCharacters(in: .whitespaces) }
    private var nameIsValid: Bool { slug.range(of: #"^[a-z0-9][a-z0-9._-]{0,63}$"#, options: .regularExpression) != nil }
    private var taken: Bool { model.wikis.contains { $0.name == slug } }
    private var folder: URL? { parent.map { $0.appendingPathComponent(slug, isDirectory: true) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Wiki").font(.title3.weight(.semibold))
            Form {
                TextField("Name", text: $name, prompt: Text("e.g. research"))
                if !slug.isEmpty, !nameIsValid {
                    Text("Use lowercase letters, digits, dots, dashes or underscores.").font(.caption).foregroundStyle(.red)
                } else if taken {
                    Text("A wiki with this name already exists.").font(.caption).foregroundStyle(.red)
                }
                TextField("Description", text: $description, prompt: Text("What this wiki is about"))
                Picker("Page format", selection: $format) {
                    Text("Choose…").tag(String?.none)
                    Text("Markdown — for Obsidian, editors and agents").tag(String?.some("markdown"))
                    Text("HTML — pages you read in a browser").tag(String?.some("html"))
                }
                LabeledContent("Location") {
                    HStack {
                        Text(folder?.path ?? "Choose a parent folder").foregroundStyle(folder == nil ? .tertiary : .primary).lineLimit(1).truncationMode(.middle)
                        Button("Choose…") { chooseParent() }
                    }
                }
                Toggle("Make it the current wiki", isOn: $makeCurrent)
            }
            .formStyle(.grouped)
            HStack {
                if running { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(running || !nameIsValid || taken || format == nil || folder == nil)
            }
        }
        .padding(20)
        .frame(width: 540)
    }

    private func chooseParent() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose the folder that will contain the new wiki"
        if panel.runModal() == .OK { parent = panel.url }
    }

    private func create() {
        guard let cli = model.cli, let folder, let format else { return }
        running = true
        Task {
            defer { running = false }
            do {
                try await cli.initWiki(directory: folder.path, format: format, name: slug, description: description.trimmingCharacters(in: .whitespaces), makeCurrent: makeCurrent)
                await model.reloadWikis()
                model.selectedWikiName = slug
                dismiss()
            } catch {
                model.report(error)
            }
        }
    }
}
