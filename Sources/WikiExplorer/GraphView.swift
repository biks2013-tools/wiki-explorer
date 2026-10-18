import AppKit
import SwiftUI
import WikiExplorerCore

/// The wiki as a liquid graph: pages float as bubbles held together by their links, and pages of one kind
/// melt into a coloured pool. Drag to move around, pinch or ⌘-scroll to zoom, click to light up a page's
/// links, double-click to open it.
struct WikiGraphView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene = GraphScene()
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            if let graph = model.graph {
                canvas
                    .onAppear { connect(graph) }
                    .onChange(of: graph) { _, g in scene.load(g, selectedId: model.selectedPageId) }
                VStack(spacing: 0) {
                    GraphControls(scene: scene)
                    Spacer()
                    HStack(alignment: .bottom) {
                        GraphInfoCard(scene: scene, graph: graph)
                        Spacer()
                        GraphLegend(scene: scene)
                    }
                }
                .padding(12)
                if graph.nodes.isEmpty {
                    ContentUnavailableView("No pages yet", systemImage: "circle.hexagongrid", description: Text("Add sources to the wiki and its pages appear here."))
                }
            } else if model.loadingGraph {
                ProgressView("Drawing the graph…")
            } else {
                ContentUnavailableView("No graph", systemImage: "circle.hexagongrid", description: Text("Select a wiki."))
            }
        }
        .navigationTitle(model.selectedWikiName.map { "\($0) — Graph" } ?? "Graph")
        .task(id: model.selectedWikiName) { await model.loadGraph() }
        .onChange(of: model.selectedPageId) { _, id in scene.select(id: id) }
        .onReceive(NotificationCenter.default.publisher(for: .graphCommand)) { note in
            switch note.object as? String {
            case "fit": scene.fit()
            case "zoomIn": scene.zoom(by: 1.4)
            case "zoomOut": scene.zoom(by: 1 / 1.4)
            case "neighbourhood": scene.scope = .neighbourhood; scene.select(id: model.selectedPageId)
            default: break
            }
        }
    }

    private var canvas: some View {
        let animating = scene.running && activeState != .inactive
        return TimelineView(.animation(minimumInterval: scene.calm ? 1 / 15 : 1 / 60, paused: !animating)) { timeline in
            Canvas(rendersAsynchronously: false) { ctx, size in
                scene.advance(to: timeline.date)
                scene.draw(&ctx, size: size, time: timeline.date.timeIntervalSinceReferenceDate, dark: colorScheme == .dark)
            }
        }
        .background(GraphBackdrop())
        .background(ScrollCatcher { delta, location, zoom in
            if zoom {
                scene.zoom(by: exp(Double(delta.height) * 0.012), around: location)
            } else {
                scene.pan(by: CGSize(width: -delta.width, height: -delta.height))
            }
        })
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in scene.dragChanged(start: v.startLocation, location: v.location, translation: v.translation) }
            .onEnded { v in scene.dragEnded(location: v.location) })
        .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { v in scene.doubleClick(at: v.location) })
        .simultaneousGesture(MagnifyGesture()
            .onChanged { v in scene.magnify(v.magnification) }
            .onEnded { _ in scene.magnifyEnded() })
        .onContinuousHover { phase in
            switch phase {
            case let .active(p): scene.hover(at: p)
            case .ended: scene.hover(at: nil)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.return) { scene.openSelected(); return .handled }
        .onKeyPress(.escape) { scene.clearSelection(); return .handled }
        .tourAnchor(.graphView)
    }

    private func connect(_ graph: WikiGraph) {
        scene.ambientMotion = !reduceMotion
        scene.onSelect = { id in model.selectedPageId = id }
        scene.onOpen = { item in
            if let raw = item.rawPath {
                model.openRawFile(wiki: graph.wiki, path: raw)
            } else {
                Task {
                    await model.openPage(PageLocation(wiki: model.selectedWikiName ?? graph.wiki, id: item.id), recordHistory: true)
                    model.detailMode = .page
                }
            }
        }
        scene.load(graph, selectedId: model.selectedPageId)
        focused = true
    }
}

/// A soft vignette behind the graph.
private struct GraphBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        RadialGradient(colors: colorScheme == .dark ? [Color(white: 0.16), Color(white: 0.09)] : [Color(white: 0.995), Color(red: 0.93, green: 0.94, blue: 0.96)],
                       center: .center, startRadius: 40, endRadius: 900)
    }
}

/// The bar at the top: whole wiki or neighbourhood, source files, pools, highlight, zoom.
private struct GraphControls: View {
    @Environment(AppModel.self) private var model
    @Bindable var scene: GraphScene

    var body: some View {
        HStack(spacing: 10) {
            Picker("Show", selection: $scene.scope) {
                ForEach(GraphScene.Scope.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("The whole wiki, or only the pages a few links away from the selected page")
            if scene.scope == .neighbourhood {
                Stepper("\(scene.depth) link\(scene.depth == 1 ? "" : "s") away", value: $scene.depth, in: 1...4)
                    .fixedSize()
            }
            Toggle(isOn: $scene.includeSources) { Label("Source files", systemImage: "doc") }
                .toggleStyle(.button)
                .help("Show the original documents, joined to the pages written from them")
            Toggle(isOn: $scene.pools) { Label("Pools", systemImage: "drop") }
                .toggleStyle(.button)
                .help("Let pages of the same kind flow together into coloured pools")
            TextField("Highlight pages", text: $scene.highlight)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120, maxWidth: 200)
            Spacer(minLength: 0)
            ControlGroup {
                Button { scene.zoom(by: 1 / 1.4) } label: { Image(systemName: "minus.magnifyingglass") }
                    .help("Zoom out (\(AppShortcuts.zoomOut.display))")
                Button { scene.fit() } label: { Image(systemName: "arrow.up.left.and.down.right.magnifyingglass") }
                    .help("Fit to window (\(AppShortcuts.fitGraph.display))")
                Button { scene.zoom(by: 1.4) } label: { Image(systemName: "plus.magnifyingglass") }
                    .help("Zoom in (\(AppShortcuts.zoomIn.display))")
            }
            .fixedSize()
        }
        .controlSize(.small)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
    }
}

/// The hovered or selected page: what it is and what it links to, with a button to open it.
private struct GraphInfoCard: View {
    @Environment(AppModel.self) private var model
    let scene: GraphScene
    let graph: WikiGraph

    var body: some View {
        let shown = scene.model
        if let i = scene.hovered ?? scene.selected, i < shown.items.count {
            let item = shown.items[i]
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(GraphPalette.color(item.kind)).frame(width: 9, height: 9)
                    Text(item.isSourceFile ? "Source file" : item.kind.capitalized).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("· \(item.degree) link\(item.degree == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                }
                Text(item.title).font(.headline).lineLimit(2)
                if let summary = item.summary {
                    Text(summary).font(.callout).foregroundStyle(.secondary).lineLimit(4).fixedSize(horizontal: false, vertical: true)
                }
                if scene.hovered == nil || scene.hovered == scene.selected {
                    HStack {
                        Button(item.isSourceFile ? "Open File" : "Open Page") { scene.openSelected() }
                            .keyboardShortcut(.defaultAction)
                            .controlSize(.small)
                        if !item.isSourceFile {
                            Button("Neighbourhood") {
                                scene.scope = .neighbourhood
                                scene.select(id: item.id)
                            }
                            .controlSize(.small)
                        }
                    }
                } else {
                    Text("Click to select · double-click to open").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .frame(width: 300, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
            .allowsHitTesting(scene.hovered == nil || scene.hovered == scene.selected)
        } else {
            Text("\(shown.items.count) of \(graph.nodes.count + (scene.includeSources ? graph.sources.count : 0)) shown · \(shown.edges.count) links\(graph.missing.isEmpty ? "" : " · \(graph.missing.count) broken")\nDrag to move · pinch or ⌘-scroll to zoom · drag a bubble · double-click to open")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .allowsHitTesting(false)
        }
    }
}

/// The kinds of page, with their colours and counts; clicking one hides or shows it.
private struct GraphLegend: View {
    let scene: GraphScene

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(scene.kindCounts, id: \.kind) { entry in
                let hidden = scene.hiddenKinds.contains(entry.kind)
                Button {
                    if hidden { scene.hiddenKinds.remove(entry.kind) } else { scene.hiddenKinds.insert(entry.kind) }
                } label: {
                    HStack(spacing: 7) {
                        Circle().fill(GraphPalette.color(entry.kind).opacity(hidden ? 0.25 : 1)).frame(width: 10, height: 10)
                        Text(GraphPalette.title(entry.kind)).strikethrough(hidden)
                        Spacer(minLength: 8)
                        Text("\(entry.count)").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(hidden ? .secondary : .primary)
                .help(hidden ? "Show \(GraphPalette.title(entry.kind).lowercased())" : "Hide \(GraphPalette.title(entry.kind).lowercased())")
            }
        }
        .font(.callout)
        .padding(10)
        .frame(width: 190)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
    }
}

/// Scroll-wheel and trackpad scrolling over the graph: two-finger scrolling pans; a mouse wheel, or
/// scrolling with ⌘ held, zooms around the pointer. Sits behind the graph, so clicks are unaffected.
private struct ScrollCatcher: NSViewRepresentable {
    let onScroll: (CGSize, CGPoint, Bool) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let v = CatcherView()
        v.onScroll = onScroll
        return v
    }

    func updateNSView(_ view: CatcherView, context: Context) { view.onScroll = onScroll }

    final class CatcherView: NSView {
        var onScroll: (CGSize, CGPoint, Bool) -> Void = { _, _, _ in }
        private var monitor: Any?
        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let p = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(p), self.isTopmostAt(event.locationInWindow) else { return event }
                let zoom = !event.hasPreciseScrollingDeltas || event.modifierFlags.contains(.command)
                let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 3
                self.onScroll(CGSize(width: event.scrollingDeltaX * factor, height: event.scrollingDeltaY * factor), p, zoom)
                return nil
            }
        }

        /// Not when a sheet, popover or another column is under the pointer.
        private func isTopmostAt(_ windowPoint: NSPoint) -> Bool {
            guard let hit = window?.contentView?.superview?.hitTest(windowPoint) else { return false }
            // The SwiftUI hosting view of the graph sits above this view; accept any view not inside another scroll view.
            var v: NSView? = hit
            while let current = v {
                if current is NSScrollView { return false }
                v = current.superview
            }
            return true
        }

        override func removeFromSuperview() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            super.removeFromSuperview()
        }
    }
}

extension Notification.Name {
    /// Graph commands from the menus: `fit`, `zoomIn`, `zoomOut`, `neighbourhood`.
    static let graphCommand = Notification.Name("WikiExplorer.graphCommand")
}
