import AppKit
import SwiftUI
import WikiExplorerCore

/// The guided tour: a transparent panel over the main window that dims everything except the part a step
/// is about. The highlighted area is fully transparent, so clicks pass through to the window and the user
/// can try it out; the step card and the dimmed area take the clicks. → / ↩ next, ← back, Esc ends.
@MainActor
@Observable
final class TourController {
    static let shared = TourController()
    static let seenKey = "didShowGuidedTour"

    private(set) var index = 0
    private(set) var isRunning = false
    /// The highlighted area in the panel's coordinates (top-left origin), nil for a centred step.
    private(set) var hole: CGRect?
    private(set) var canvas: CGSize = .zero

    var step: TourStep { Tour.steps[index] }
    var steps: [TourStep] { Tour.steps }

    @ObservationIgnored private var anchors: [TourTarget: WeakView] = [:]
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var askWasShown = false
    @ObservationIgnored private var modeWas: DetailMode?

    private struct WeakView { weak var view: NSView? }

    @ObservationIgnored private weak var mainView: NSView?

    func register(_ target: TourTarget, view: NSView) { anchors[target] = WeakView(view: view) }
    /// A view inside the main window (MainView's background): the tour runs over that window.
    func registerMain(_ view: NSView) { mainView = view }

    /// Starts the tour over the app's main window.
    func start(model: AppModel) {
        guard !isRunning, let window = mainView?.window else { return }
        self.model = model
        self.window = window
        askWasShown = model.showAsk
        modeWas = model.detailMode
        window.makeKeyAndOrderFront(nil)

        let panel = TourPanel(contentRect: window.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.becomesKeyOnlyIfNeeded = true
        let host = NSHostingView(rootView: TourOverlay(tour: self))
        host.frame = NSRect(origin: .zero, size: window.frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        window.addChildWindow(panel, ordered: .above)
        panel.setFrame(window.frame, display: true)
        self.panel = panel

        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification, NSWindow.didEndLiveResizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.followWindow() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        })
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRunning else { return event }
            // Typing into a field (search, Ask) keeps working while the tour is open.
            if let responder = event.window?.firstResponder, responder is NSTextView, event.keyCode != 53 { return event }
            switch event.keyCode {
            case 124, 36, 76: self.next(); return nil // → ↩ enter
            case 123: self.back(); return nil // ←
            case 53: self.finish(); return nil // Esc
            default: return event
            }
        }
        index = 0
        isRunning = true
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        show()
    }

    func next() { index < Tour.steps.count - 1 ? go(to: index + 1) : finish() }
    func back() { if index > 0 { go(to: index - 1) } }

    func go(to i: Int) {
        index = i
        show()
    }

    func finish() {
        guard isRunning else { return }
        isRunning = false
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if let panel {
            window?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        panel = nil
        model?.showAsk = askWasShown
        if let modeWas { model?.detailMode = modeWas }
        hole = nil
    }

    private func followWindow() {
        guard let window, let panel else { return }
        if panel.frame != window.frame { panel.setFrame(window.frame, display: true) }
        measure()
    }

    /// Prepares the window for the step (the Ask panel opens for the Ask step), then measures the target once
    /// the layout has settled.
    private func show() {
        if let model {
            if step.target == .askPanel || step.target == .askButton { model.showAsk = true } else { model.showAsk = askWasShown }
            switch step.target {
            case .graphView: model.detailMode = .graph
            case .pageBody, .pageActions, .relations: model.detailMode = .page
            default: break
            }
        }
        followWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.followWindow() }
        // The graph may still be loading.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.followWindow() }
    }

    private func measure() {
        guard let window else { return }
        canvas = window.frame.size
        guard let target = step.target, let rect = windowRect(of: target, in: window), rect.width > 4, rect.height > 4 else {
            hole = nil
            return
        }
        // Window coordinates have a bottom-left origin; the overlay draws top-left.
        let r = CGRect(x: rect.minX, y: window.frame.height - rect.maxY, width: rect.width, height: rect.height).insetBy(dx: -6, dy: -6)
        hole = r.intersection(CGRect(origin: .zero, size: canvas).insetBy(dx: 2, dy: 2))
    }

    private func windowRect(of target: TourTarget, in window: NSWindow) -> CGRect? {
        switch target {
        case .searchField:
            guard let field = NSWindow.searchField(in: window) else { return nil }
            return field.convert(field.bounds, to: nil)
        case .askButton:
            return toolbarItemView(in: window) { $0.label == "Ask" }
        case .addSourcesButton:
            return toolbarItemView(in: window) { $0.label == "Add Sources" }
        case .checkSourcesButton:
            return toolbarItemView(in: window) { $0.label == "Check Sources" }
        default:
            guard let view = anchors[target]?.view, view.window === window, !view.isHiddenOrHasHiddenAncestor else { return nil }
            return view.convert(view.bounds, to: nil)
        }
    }

    private func toolbarItemView(in window: NSWindow, where match: (NSToolbarItem) -> Bool) -> CGRect? {
        guard let item = window.toolbar?.items.first(where: match), let view = item.view, view.window === window else { return nil }
        return view.convert(view.bounds, to: nil)
    }
}

extension NSWindow {
    /// The toolbar search field of `.searchable` (found in the view tree: SwiftUI does not always use an NSSearchToolbarItem).
    static func searchField(in window: NSWindow) -> NSSearchField? {
        func find(_ view: NSView) -> NSSearchField? {
            if let f = view as? NSSearchField, !f.isHiddenOrHasHiddenAncestor { return f }
            for sub in view.subviews { if let f = find(sub) { return f } }
            return nil
        }
        return window.contentView?.superview.flatMap(find)
    }
}

/// A borderless panel that never takes keyboard focus from the main window.
private final class TourPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// Always exactly over the main window, even where that window extends past the screen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Records the window frame of the view it backs, for the tour to highlight.
private struct TourAnchorView: NSViewRepresentable {
    let target: TourTarget
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        TourController.shared.register(target, view: view)
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { TourController.shared.register(target, view: view) }
}

/// Tells the tour which window is the main one.
struct TourMainWindowAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        TourController.shared.registerMain(view)
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { TourController.shared.registerMain(view) }
}

extension View {
    /// Marks this view as what the tour step with `target` points at.
    func tourAnchor(_ target: TourTarget) -> some View {
        background(TourAnchorView(target: target).allowsHitTesting(false))
    }
}

private struct TourOverlay: View {
    let tour: TourController
    @State private var cardSize = CGSize(width: 380, height: 220)
    private let cardWidth: CGFloat = 380

    var body: some View {
        let canvas = tour.canvas
        ZStack(alignment: .topLeading) {
            // The dimmed area; the hole is cut out with an even-odd fill so it stays fully transparent.
            Path { p in
                p.addRect(CGRect(origin: .zero, size: canvas))
                if let hole = tour.hole { p.addRoundedRect(in: hole, cornerSize: CGSize(width: 10, height: 10)) }
            }
            .fill(Color.black.opacity(0.42), style: FillStyle(eoFill: true))
            .contentShape(Path { p in
                p.addRect(CGRect(origin: .zero, size: canvas))
                if let hole = tour.hole { p.addRoundedRect(in: hole, cornerSize: CGSize(width: 10, height: 10)) }
            }, eoFill: true)
            .onTapGesture {} // swallow clicks on the dimmed area

            if let hole = tour.hole {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: 2.5)
                    .frame(width: hole.width, height: hole.height)
                    .offset(x: hole.minX, y: hole.minY)
                    .allowsHitTesting(false)
            }

            card
                .frame(width: cardWidth)
                .background(GeometryReader { g in Color.clear.onAppear { cardSize = g.size }.onChange(of: g.size) { _, s in cardSize = s } })
                .offset(x: cardOrigin(canvas: canvas).x, y: cardOrigin(canvas: canvas).y)
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.25), value: tour.hole)
        .animation(.easeInOut(duration: 0.25), value: tour.index)
    }

    private var card: some View {
        let step = tour.step
        let last = tour.index == tour.steps.count - 1
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(tour.index + 1) of \(tour.steps.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button { tour.finish() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).help("End the tour (Esc)")
            }
            Text(step.title).font(.title3.weight(.semibold))
            Text(step.body).fixedSize(horizontal: false, vertical: true)
            if let tryIt = step.tryIt {
                Label { Text(tryIt).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "hand.point.up.left") }
                    .font(.callout)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack(spacing: 6) {
                ForEach(0..<tour.steps.count, id: \.self) { i in
                    Circle().fill(i == tour.index ? Color.accentColor : Color.secondary.opacity(0.35)).frame(width: 6, height: 6)
                        .onTapGesture { tour.go(to: i) }
                }
                Spacer()
                if tour.index > 0 { Button("Back") { tour.back() } }
                Button(last ? "Done" : (tour.index == 0 ? "Start" : "Next")) { tour.next() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
    }

    /// Next to the highlighted area on the side with the most room, kept inside the window.
    private func cardOrigin(canvas: CGSize) -> CGPoint {
        let w = cardWidth, h = cardSize.height, gap: CGFloat = 16, margin: CGFloat = 14
        func clamp(_ p: CGPoint) -> CGPoint {
            CGPoint(x: min(max(p.x, margin), canvas.width - w - margin), y: min(max(p.y, margin + 40), canvas.height - h - margin))
        }
        guard let hole = tour.hole else { return clamp(CGPoint(x: (canvas.width - w) / 2, y: (canvas.height - h) / 2)) }
        let right = canvas.width - hole.maxX, left = hole.minX, below = canvas.height - hole.maxY, above = hole.minY
        if right >= w + gap + margin { return clamp(CGPoint(x: hole.maxX + gap, y: hole.minY)) }
        if left >= w + gap + margin { return clamp(CGPoint(x: hole.minX - gap - w, y: hole.minY)) }
        if below >= h + gap + margin { return clamp(CGPoint(x: hole.maxX - w, y: hole.maxY + gap)) }
        if above >= h + gap + margin { return clamp(CGPoint(x: hole.minX, y: hole.minY - gap - h)) }
        // A large area (the page body): inside it, at the bottom right.
        return clamp(CGPoint(x: hole.maxX - w - gap, y: hole.maxY - h - gap))
    }
}
