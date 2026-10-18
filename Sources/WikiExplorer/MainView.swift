import SwiftUI
import WikiExplorerCore

struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var showNewWiki = false
    @State private var showIngest = false
    @State private var showSources = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.setup {
            case .starting:
                ProgressView("Looking for llm-wiki…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                SetupFailedView(message: message)
            case .ready:
                NavigationSplitView {
                    WikiSidebar(showNewWiki: $showNewWiki)
                        .tourAnchor(.wikiList)
                        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
                } content: {
                    PageListColumn()
                        .tourAnchor(.pageList)
                        .navigationSplitViewColumnWidth(min: 260, ideal: 320)
                } detail: {
                    Group {
                        switch model.detailMode {
                        case .page: PageDetailView()
                        case .graph: WikiGraphView()
                        }
                    }
                    .frame(minWidth: 460)
                }
                .inspector(isPresented: $model.showAsk) {
                    AskPanel().tourAnchor(.askPanel).inspectorColumnWidth(min: 340, ideal: 440, max: 700)
                }
                .toolbar { toolbar }
                .sheet(isPresented: $showNewWiki) { NewWikiSheet() }
                .sheet(isPresented: $showIngest) { IngestSheet() }
                .sheet(isPresented: $showSources) { SourcesSheet() }
                .task {
                    // First launch: offer the guided tour once the window has its size.
                    guard !UserDefaults.standard.bool(forKey: TourController.seenKey) else { return }
                    try? await Task.sleep(for: .seconds(1.2))
                    TourController.shared.start(model: model)
                }
            }
        }
        .background(TourMainWindowAnchor())
        .alert("Something went wrong", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .task { if model.setup == .starting { await model.bootstrap() } }
        .onReceive(NotificationCenter.default.publisher(for: .showIngest)) { _ in if model.selectedWiki != nil { showIngest = true } }
        .onReceive(NotificationCenter.default.publisher(for: .showNewWiki)) { _ in showNewWiki = true }
        .onReceive(NotificationCenter.default.publisher(for: .showSources)) { _ in if model.selectedWiki?.healthy == true { showSources = true } }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { model.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                .disabled(!model.canGoBack)
                .help("Back (\(AppShortcuts.back.display))")
            Button { model.goForward() } label: { Label("Forward", systemImage: "chevron.right") }
                .disabled(!model.canGoForward)
                .help("Forward (\(AppShortcuts.forward.display))")
        }
        ToolbarItem(placement: .primaryAction) {
            Picker("View", selection: Binding(get: { model.detailMode }, set: { model.detailMode = $0 })) {
                Label("Page", systemImage: "doc.richtext").tag(DetailMode.page)
                Label("Graph", systemImage: "circle.hexagongrid").tag(DetailMode.graph)
            }
            .pickerStyle(.segmented)
            .help("Show the open page, or the wiki as a graph of linked pages (\(AppShortcuts.graph.display))")
            .disabled(model.selectedWiki?.healthy != true)
            .tourAnchor(.graphToggle)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { showSources = true } label: { Label("Check Sources", systemImage: "arrow.triangle.2.circlepath") }
                .help("Check downloaded pages and outside files for changes, and update the wiki (\(AppShortcuts.checkSources.display))")
                .disabled(model.selectedWiki?.healthy != true)
            Button { showIngest = true } label: { Label("Add Sources", systemImage: "square.and.arrow.down.on.square") }
                .help("Ingest files or web pages into the selected wiki (\(AppShortcuts.addSources.display))")
                .disabled(model.selectedWiki?.healthy != true)
            Button { model.showAsk.toggle() } label: { Label("Ask", systemImage: "questionmark.bubble") }
                .help("Ask a question and get an answer with linked sources (\(AppShortcuts.ask.display))")
            Menu {
                Button { TourController.shared.start(model: model) } label: { Label("Take the Tour", systemImage: "figure.walk") }
                    .keyboardShortcut(AppShortcuts.tour)
                Button { openWindow(id: ShortcutsGuideView.windowID) } label: { Label("Keyboard Shortcuts", systemImage: "keyboard") }
                    .keyboardShortcut(AppShortcuts.shortcutsGuide)
                Divider()
                SettingsLink { Label("Settings…", systemImage: "gearshape") }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .help("Guided tour, keyboard shortcuts and settings")
        }
    }
}

struct SetupFailedView: View {
    @Environment(AppModel.self) private var model
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 40)).foregroundStyle(.orange)
            Text("Wiki Explorer cannot run llm-wiki").font(.title2.weight(.semibold))
            Text(message).multilineTextAlignment(.center).textSelection(.enabled).frame(maxWidth: 520)
            HStack {
                SettingsLink { Text("Open Settings…") }
                Button("Try Again") { Task { await model.bootstrap() } }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Notification.Name {
    static let showIngest = Notification.Name("WikiExplorer.showIngest")
    static let showNewWiki = Notification.Name("WikiExplorer.showNewWiki")
    static let showSources = Notification.Name("WikiExplorer.showSources")
}
