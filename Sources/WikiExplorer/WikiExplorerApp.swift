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
                    .keyboardShortcut(AppShortcuts.newWiki)
                Button("Add Sources…") { NotificationCenter.default.post(name: .showIngest, object: nil) }
                    .keyboardShortcut(AppShortcuts.addSources)
                Button("Check Sources for Changes…") { NotificationCenter.default.post(name: .showSources, object: nil) }
                    .keyboardShortcut(AppShortcuts.checkSources)
            }
            CommandGroup(after: .textEditing) {
                Button("Search") { model.focusSearch() }
                    .keyboardShortcut(AppShortcuts.search)
            }
            SidebarCommands()
            CommandGroup(after: .toolbar) {
                Button("Reload Wikis") { Task { await model.refreshAfterChange() } }
                    .keyboardShortcut(AppShortcuts.reloadWikis)
                Button(model.showAsk ? "Hide Ask Panel" : "Show Ask Panel") { model.showAsk.toggle() }
                    .keyboardShortcut(AppShortcuts.ask)
                    .disabled(!model.isReady)
                Divider()
                Button(model.detailMode == .graph ? "Show Page" : "Show Graph") { model.toggleGraph() }
                    .keyboardShortcut(AppShortcuts.graph)
                    .disabled(model.selectedWiki?.healthy != true)
                Button("Fit Graph to Window") { NotificationCenter.default.post(name: .graphCommand, object: "fit") }
                    .keyboardShortcut(AppShortcuts.fitGraph)
                    .disabled(model.detailMode != .graph)
                Button("Zoom In") { NotificationCenter.default.post(name: .graphCommand, object: "zoomIn") }
                    .keyboardShortcut(AppShortcuts.zoomIn)
                    .disabled(model.detailMode != .graph)
                Button("Zoom Out") { NotificationCenter.default.post(name: .graphCommand, object: "zoomOut") }
                    .keyboardShortcut(AppShortcuts.zoomOut)
                    .disabled(model.detailMode != .graph)
            }
            CommandMenu("Page") {
                Button("Back") { model.goBack() }
                    .keyboardShortcut(AppShortcuts.back)
                    .disabled(!model.canGoBack)
                Button("Forward") { model.goForward() }
                    .keyboardShortcut(AppShortcuts.forward)
                    .disabled(!model.canGoForward)
                Divider()
                Button("Open in Browser") { model.openCurrentPageInBrowser() }
                    .keyboardShortcut(AppShortcuts.openInBrowser)
                    .disabled(!model.pageOpensInBrowser)
                Button("Show in Finder") { model.showCurrentPageInFinder() }
                    .keyboardShortcut(AppShortcuts.showInFinder)
                    .disabled(model.pageView == nil)
                Button("Show Sources in Finder") { model.showCurrentSourcesInFinder() }
                    .keyboardShortcut(AppShortcuts.openSourceFolder)
                    .disabled(model.pageView?.sourceFiles.contains(where: \.exists) != true)
                Divider()
                Button("Show in Graph") { model.showCurrentPageInGraph() }
                    .keyboardShortcut(AppShortcuts.showInGraph)
                    .disabled(model.pageView == nil)
            }
            CommandGroup(replacing: .help) {
                Button("Take the Tour") { TourController.shared.start(model: model) }
                    .keyboardShortcut(AppShortcuts.tour)
                    .disabled(!model.isReady)
                OpenShortcutsButton()
                Divider()
                Link("Wiki Explorer on GitHub", destination: URL(string: "https://github.com/biks2013-tools/wiki-explorer")!)
                Link("llm-wiki on GitHub", destination: URL(string: "https://github.com/biks2013-tools/llm-wiki")!)
            }
        }
        Window("Keyboard Shortcuts", id: ShortcutsGuideView.windowID) {
            ShortcutsGuideView()
        }
        .windowResizability(.contentMinSize)
        .defaultPosition(.center)
        .defaultSize(width: 780, height: 700)
        Settings {
            SettingsView().environment(model)
        }
    }
}

/// Help › Keyboard Shortcuts (a button view, so it can use the openWindow action).
struct OpenShortcutsButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Keyboard Shortcuts") { openWindow(id: ShortcutsGuideView.windowID) }
            .keyboardShortcut(AppShortcuts.shortcutsGuide)
    }
}

extension ShortcutsGuideView {
    static let windowID = "keyboard-shortcuts"
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
