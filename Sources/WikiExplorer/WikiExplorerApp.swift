import AppKit
import SwiftUI
import WikiExplorerCore

@main
struct WikiExplorerApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Wiki Explorer") {
            MainView()
                .environment(model)
                .frame(minWidth: 1100, idealWidth: 1480, minHeight: 640, idealHeight: 920)
        }
        .defaultSize(width: 1480, height: 920)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Wiki…") { NotificationCenter.default.post(name: .showNewWiki, object: nil) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Add Sources…") { NotificationCenter.default.post(name: .showIngest, object: nil) }
                    .keyboardShortcut("i", modifiers: .command)
                Button("Check Sources for Changes…") { NotificationCenter.default.post(name: .showSources, object: nil) }
                    .keyboardShortcut("u", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Reload Wikis") { Task { await model.refreshAfterChange() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
        Settings {
            SettingsView().environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as a regular app with a Dock icon and menu bar, also when started with `swift run`.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // First launch only: open roomy (three columns plus the Ask panel); later launches keep the user's size.
        let key = "didSizeInitialWindow"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) }), let screen = window.screen?.visibleFrame else { return }
            let size = NSSize(width: min(1480, screen.width * 0.92), height: min(920, screen.height * 0.92))
            window.setFrame(NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height), display: true, animate: false)
            UserDefaults.standard.set(true, forKey: key)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKeys.executablePath) private var explicitPath = ""
    @State private var configReport = ""

    var body: some View {
        Form {
            Section("llm-wiki command") {
                TextField("Path", text: $explicitPath, prompt: Text(model.executablePath ?? "found on your shell's PATH"))
                Text("Leave empty to use the llm-wiki found on your login shell's PATH. Wiki Explorer runs it with your shell environment, so the settings in ~/.tool-agents/llm-wiki/.env and the API keys exported by your shell apply.")
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
            Section("Resolved configuration (llm-wiki config)") {
                ScrollView {
                    Text(configReport.isEmpty ? "—" : configReport)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 220)
                HStack {
                    Button("Refresh") { Task { await loadConfig() } }
                    Button("Open Config Folder") {
                        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".tool-agents/llm-wiki"))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 620)
        .task { await loadConfig() }
    }

    private func loadConfig() async {
        guard let cli = model.cli else { return }
        configReport = (try? await cli.configReport()) ?? ""
    }
}
