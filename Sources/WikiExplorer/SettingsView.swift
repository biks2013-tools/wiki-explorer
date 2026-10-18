import AppKit
import SwiftUI
import WikiExplorerCore

/// Settings (⌘, or the toolbar's ⋯ menu). "llm-wiki" edits the CLI's own settings file,
/// `~/.tool-agents/llm-wiki/.env` — the same file the command line reads, so a change made here applies to
/// `llm-wiki` in a terminal too, and the other way round. "Wiki Explorer" holds the app's own options.
struct SettingsView: View {
    var body: some View {
        TabView {
            LLMWikiSettingsView()
                .tabItem { Label("llm-wiki", systemImage: "slider.horizontal.3") }
            AppSettingsView()
                .tabItem { Label("Wiki Explorer", systemImage: "app.badge") }
        }
        .frame(width: 700, height: 660)
    }
}

/// Editor of `~/.tool-agents/llm-wiki/.env`.
struct LLMWikiSettingsView: View {
    @Environment(AppModel.self) private var model
    private let fileURL = DotenvFile.defaultURL()

    @State private var file = DotenvFile(text: "")
    /// The file's text when it was loaded: saving refuses to overwrite changes made elsewhere meanwhile.
    @State private var loadedText = ""
    @State private var draft: [String: String] = [:]
    @State private var revealed: Set<String> = []
    @State private var showOtherProviders = false
    @State private var status: String?
    @State private var problem: String?
    @State private var conflict = false
    @State private var newKey = ""

    private var shellKeys: Set<String> { Set(model.cli?.environment.keys.map { $0 } ?? []) }
    private var changedKeys: [String] {
        let keys = Set(draft.keys).union(file.values.keys)
        return keys.filter { (draft[$0] ?? "") != (file[$0] ?? "") }.sorted()
    }
    private var otherKeys: [String] {
        let known = Set(SettingsCatalog.all.map(\.key))
        return (file.keys + draft.keys.sorted()).reduce(into: [String]()) { out, k in
            if !known.contains(k), !out.contains(k) { out.append(k) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                let inUse = SettingsCatalog.providersInUse(draft.merging(model.cli?.environment.filter { $0.key.hasPrefix("LLM_WIKI_") } ?? [:]) { mine, _ in mine })
                ForEach(SettingsCatalog.groups.filter { $0.provider == nil }) { group in section(group) }
                ForEach(SettingsCatalog.groups.filter { $0.provider.map(inUse.contains) == true }) { group in section(group) }
                Section {
                    DisclosureGroup("Other providers", isExpanded: $showOtherProviders) {
                        ForEach(SettingsCatalog.groups.filter { g in g.provider.map { !inUse.contains($0) } == true }) { group in
                            Text(group.title).font(.headline).padding(.top, 6)
                            ForEach(group.settings) { setting in row(setting) }
                        }
                    }
                }
                Section {
                    ForEach(otherKeys, id: \.self) { key in
                        row(SettingInfo(key, key, SettingsCatalog.isSecret(key) ? .secret : .text, help: "Not a setting Wiki Explorer knows; kept as it is unless you change it."))
                    }
                    HStack {
                        TextField("Add a setting (NAME)", text: $newKey)
                            .onSubmit(addKey)
                        Button("Add", action: addKey).disabled(!isValidKey(newKey))
                    }
                } header: {
                    Text("Other settings in this file")
                }
            }
            .formStyle(.grouped)
            footer
        }
        .task { reload() }
        .alert("The settings file changed", isPresented: $conflict) {
            Button("Reload", role: .destructive) { reload() }
            Button("Overwrite") { save(force: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(fileURL.path) was changed outside Wiki Explorer since it was opened. Reload discards your edits here; Overwrite writes them over the file's current content (other lines are kept).")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "doc.text").foregroundStyle(.secondary)
                Text(fileURL.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                    .font(.callout.monospaced()).textSelection(.enabled)
                Spacer()
                Button("Show in Finder") {
                    if FileManager.default.fileExists(atPath: fileURL.path) { model.showInFinder([fileURL]) } else { model.showInFinder([fileURL.deletingLastPathComponent()]) }
                }
                .controlSize(.small)
            }
            Text("The settings file of the llm-wiki command line. Wiki Explorer runs llm-wiki, so what you save here applies to the app and to llm-wiki in a terminal alike. Order: shell environment < this file < ./.env < command flags. There are no defaults: leave a field empty to remove the setting.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 4)
    }

    private var footer: some View {
        HStack {
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.red).lineLimit(2)
            } else if let status {
                Label(status, systemImage: "checkmark.circle").foregroundStyle(.secondary)
            } else if !changedKeys.isEmpty {
                Text("\(changedKeys.count) unsaved change\(changedKeys.count == 1 ? "" : "s")").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Revert") { reload() }.disabled(changedKeys.isEmpty)
            Button("Save") { save(force: false) }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(changedKeys.isEmpty)
        }
        .font(.callout)
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    @ViewBuilder
    private func section(_ group: SettingGroup) -> some View {
        Section {
            ForEach(group.settings) { setting in row(setting) }
        } header: {
            Text(group.title)
        } footer: {
            if let footer = group.footer { Text(footer).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { draft[key] ?? "" }, set: { draft[key] = $0; status = nil; problem = nil })
    }

    @ViewBuilder
    private func row(_ setting: SettingInfo) -> some View {
        let key = setting.key
        let value = draft[key] ?? ""
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                field(setting)
                if (file[key] ?? "") != value {
                    Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(Color.accentColor).help("Changed, not saved yet")
                }
            }
            HStack(spacing: 6) {
                Text(key).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                if shellKeys.contains(key) {
                    Text(value.isEmpty ? "· set by your shell environment" : "· also set by your shell; this file's value wins")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let warning = warning(setting, value) {
                    Label(warning, systemImage: "exclamationmark.triangle").font(.caption2).foregroundStyle(.orange)
                }
            }
        }
        .help(setting.help)
    }

    @ViewBuilder
    private func field(_ setting: SettingInfo) -> some View {
        let key = setting.key
        switch setting.kind {
        case let .choice(options):
            Picker(setting.label, selection: binding(key)) {
                Text("Not set").tag("")
                ForEach(options, id: \.self) { Text($0).tag($0) }
                let current = draft[key] ?? ""
                if !current.isEmpty, !options.contains(current) { Text("\(current) (unknown)").tag(current) }
            }
        case .secret:
            HStack {
                if revealed.contains(key) {
                    TextField(setting.label, text: binding(key), prompt: Text(placeholder(key)))
                } else {
                    SecureField(setting.label, text: binding(key), prompt: Text(placeholder(key)))
                }
                Button {
                    if revealed.contains(key) { revealed.remove(key) } else { revealed.insert(key) }
                } label: { Image(systemName: revealed.contains(key) ? "eye.slash" : "eye") }
                    .buttonStyle(.borderless)
                    .help(revealed.contains(key) ? "Hide" : "Show")
                    .disabled((draft[key] ?? "").isEmpty)
            }
        case .executable:
            HStack {
                TextField(setting.label, text: binding(key), prompt: Text(placeholder(key)))
                Menu("Choose") {
                    ForEach(Self.detectedBrowsers(), id: \.self) { path in
                        Button(URL(fileURLWithPath: path).lastPathComponent) { binding(key).wrappedValue = path }
                    }
                    Divider()
                    Button("Other…") { if let p = chooseExecutable() { binding(key).wrappedValue = p } }
                }
                .fixedSize()
            }
        case .folder:
            HStack {
                TextField(setting.label, text: binding(key), prompt: Text(placeholder(key)))
                Button("Choose…") { if let p = chooseFolder() { binding(key).wrappedValue = p } }
            }
        case .text:
            TextField(setting.label, text: binding(key), prompt: Text(placeholder(key)))
        }
    }

    private func placeholder(_ key: String) -> String { shellKeys.contains(key) ? "from your shell" : "not set" }

    private func warning(_ setting: SettingInfo, _ value: String) -> String? {
        guard !value.isEmpty else { return nil }
        switch setting.kind {
        case .executable:
            return FileManager.default.isExecutableFile(atPath: value) ? nil : "not an executable file"
        case .folder:
            var dir: ObjCBool = false
            return FileManager.default.fileExists(atPath: value, isDirectory: &dir) && dir.boolValue ? nil : "folder not found"
        default:
            return value != value.trimmingCharacters(in: .whitespacesAndNewlines) ? "starts or ends with a space" : nil
        }
    }

    private func isValidKey(_ key: String) -> Bool {
        key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil && draft[key] == nil && file[key] == nil
    }

    private func addKey() {
        let key = newKey.trimmingCharacters(in: .whitespaces)
        guard isValidKey(key) else { return }
        if SettingsCatalog.info(key) != nil { showOtherProviders = true }
        draft[key] = ""
        newKey = ""
    }

    private func reload() {
        do {
            file = try DotenvFile.load(from: fileURL)
            loadedText = file.text
            draft = file.values
            status = nil
            problem = nil
        } catch {
            problem = "Cannot read the settings file: \(error.localizedDescription)"
        }
    }

    private func save(force: Bool) {
        do {
            var current = try DotenvFile.load(from: fileURL)
            if !force, current.text != loadedText {
                conflict = true
                return
            }
            let changes = changedKeys
            for key in changes { current.set(key, draft[key]) }
            try current.save(to: fileURL)
            file = current
            loadedText = current.text
            draft = current.values
            status = "Saved \(changes.count) change\(changes.count == 1 ? "" : "s") to the llm-wiki settings file."
            problem = nil
        } catch {
            problem = "Cannot save: \(error.localizedDescription)"
        }
    }

    /// Chromium-family browsers installed in the usual places (the CLI's `browserCandidates`).
    static func detectedBrowsers() -> [String] {
        let apps = ["Google Chrome", "Chromium", "Microsoft Edge", "Brave Browser", "Google Chrome Canary"]
        let roots = ["/Applications", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        return roots.flatMap { root in apps.map { "\(root)/\($0).app/Contents/MacOS/\($0)" } }
            .filter { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func chooseExecutable() -> String? {
        let panel = NSOpenPanel()
        panel.message = "Choose a Chromium-family browser (Chrome, Chromium, Edge, Brave)"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        // An .app bundle → its executable, which is what the CLI runs.
        if url.pathExtension == "app" { return Bundle(url: url)?.executableURL?.path }
        return url.path
    }

    private func chooseFolder() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK else { return nil }
        return panel.url?.path
    }
}

/// The app's own options: which llm-wiki it runs, and what that llm-wiki resolves.
struct AppSettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKeys.executablePath) private var explicitPath = ""
    @State private var configReport = ""

    var body: some View {
        Form {
            Section("llm-wiki command") {
                TextField("Path", text: $explicitPath, prompt: Text(model.executablePath ?? "found on your shell's PATH"))
                Text("Leave empty to use the llm-wiki found on your login shell's PATH. Wiki Explorer runs it with your shell environment; llm-wiki then reads its settings file (the llm-wiki tab).")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    switch model.setup {
                    case let .ready(version): Label("llm-wiki \(version) — \(model.executablePath ?? "")", systemImage: "checkmark.circle").foregroundStyle(.green)
                    case let .failed(message): Label(message, systemImage: "xmark.circle").foregroundStyle(.red)
                    case .starting: ProgressView().controlSize(.small)
                    }
                    Spacer()
                    Button("Apply") { Task { await model.bootstrap() } }
                }
                .font(.caption)
            }
            Section("What llm-wiki resolves (llm-wiki config, secrets masked)") {
                ScrollView {
                    Text(configReport.isEmpty ? "—" : configReport)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 260)
                HStack {
                    Button("Refresh") { Task { await loadConfig() } }
                    Button("Open Config Folder") {
                        model.showInFinder([DotenvFile.defaultURL().deletingLastPathComponent()])
                    }
                }
            }
            Section("Help") {
                HStack {
                    Button("Take the Tour") { TourController.shared.start(model: model) }
                    Text("Shows the main parts of the window, one at a time.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task { await loadConfig() }
    }

    private func loadConfig() async {
        guard let cli = model.cli else { return }
        configReport = (try? await cli.configReport()) ?? ""
    }
}
