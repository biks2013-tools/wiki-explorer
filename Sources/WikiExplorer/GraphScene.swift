import AppKit
import simd
import SwiftUI
import WikiExplorerCore

/// The state of the graph view: what is shown, the running layout, the camera and the pointer.
/// The layout and camera change every frame, so they are not observed; the view redraws from a timeline.
@MainActor
@Observable
final class GraphScene {
    enum Scope: String, CaseIterable, Identifiable {
        case wiki = "Whole wiki"
        case neighbourhood = "Neighbourhood"
        var id: String { rawValue }
    }

    // Settings the controls change.
    var scope: Scope = .wiki { didSet { if oldValue != scope { rebuild() } } }
    var depth = 2 { didSet { if oldValue != depth { rebuild() } } }
    var includeSources = false { didSet { if oldValue != includeSources { rebuild() } } }
    var hiddenKinds: Set<String> = [] { didSet { if oldValue != hiddenKinds { rebuild() } } }
    /// Pages of one kind pull together and are drawn as one liquid pool.
    var pools = true {
        didSet {
            sim.parameters.cluster = pools ? Self.clusterStrength : 0
            sim.reheat(0.5)
            wake()
        }
    }
    var highlight = "" { didSet { highlightMatches = Self.matches(highlight, in: model) ; wake() } }

    // What the overlays show.
    private(set) var hovered: Int?
    private(set) var selected: Int?
    private(set) var model = GraphModel(items: [], edges: [])
    private(set) var kindCounts: [(kind: String, count: Int)] = []
    private(set) var highlightMatches: Set<Int> = []
    /// False once the layout rests and nothing moves: the timeline stops until something changes.
    private(set) var running = true
    /// Only the slow ambient drift is moving: a low frame rate is enough.
    private(set) var calm = false

    // Per-frame state.
    @ObservationIgnored private(set) var sim = ForceSimulation(count: 0, edges: [], groups: [], radii: [])
    @ObservationIgnored private var source: WikiGraph?
    @ObservationIgnored private var focusId: String?
    @ObservationIgnored private(set) var camera = Camera()
    @ObservationIgnored private var targetCamera = Camera()
    /// While the layout unfolds the camera keeps everything in view, until the user moves it.
    @ObservationIgnored private var autoFit = true
    @ObservationIgnored private var lastFrame: Date?
    @ObservationIgnored private var neighbours: [Set<Int>] = []
    @ObservationIgnored private var labelOrder: [Int] = []
    @ObservationIgnored private var phases: [Double] = []
    @ObservationIgnored var viewSize: CGSize = .zero
    @ObservationIgnored var ambientMotion = true
    /// The last change or interaction: the ambient drift and the flowing links rest a while after it.
    @ObservationIgnored private var lastActivity = Date()
    static let restAfter: TimeInterval = 10

    // Pointer.
    @ObservationIgnored private var dragItem: Int?
    @ObservationIgnored private var dragStartCamera: Camera?
    @ObservationIgnored private var dragMoved = false
    @ObservationIgnored private var magnifyStart: Camera?
    /// The page was picked in the graph itself: the camera stays put (so a double-click lands on the same bubble).
    @ObservationIgnored private var pickedHere: String?

    /// Called when the user picks a page (click) or opens one (double-click, ↩).
    @ObservationIgnored var onSelect: (String) -> Void = { _ in }
    @ObservationIgnored var onOpen: (GraphModel.Item) -> Void = { _ in }

    static let clusterStrength = 0.16

    struct Camera: Equatable {
        /// The world point at the middle of the view.
        var center = SIMD2<Double>(0, 0)
        var zoom = 1.0
    }

    // MARK: - Data

    /// Shows a wiki graph (a new wiki, or the same wiki after a change: positions are kept by page id).
    func load(_ graph: WikiGraph, selectedId: String?) {
        let sameWiki = source?.wiki == graph.wiki
        source = graph
        if !sameWiki {
            sim = ForceSimulation(count: 0, edges: [], groups: [], radii: [])
            model = GraphModel(items: [], edges: [])
            hiddenKinds = []
            autoFit = true
        }
        focusId = selectedId
        rebuild()
    }

    /// The page selected elsewhere (the page list, a link) is selected here too, and the camera glides to it.
    func select(id: String?) {
        let fromGraph = id != nil && pickedHere == id
        pickedHere = nil
        focusId = id ?? focusId
        if scope == .neighbourhood {
            rebuild()
        }
        let index = id.flatMap(model.index(of:))
        guard index != selected || scope == .neighbourhood else { return }
        selected = index
        if let index, !autoFit, !fromGraph {
            targetCamera.center = sim.positions[index]
            targetCamera.zoom = max(targetCamera.zoom, 0.55)
        }
        wake()
    }

    func clearSelection() {
        selected = nil
        wake()
    }

    private func rebuild() {
        guard let source else { return }
        let previousIds = model.items.map(\.id)
        let previousPositions = sim.positions
        let next = GraphModel.build(from: source, includeSources: includeSources, hiddenKinds: hiddenKinds,
                                    focus: scope == .neighbourhood ? focusId : nil, depth: scope == .neighbourhood ? depth : nil)
        var keep = [Int: SIMD2<Double>]()
        var oldIndex = [String: Int]()
        for (i, id) in previousIds.enumerated() { oldIndex[id] = i }
        for (i, item) in next.items.enumerated() { if let o = oldIndex[item.id], o < previousPositions.count { keep[i] = previousPositions[o] } }

        let kinds = Self.kindOrder(next.items.map(\.kind))
        var params = ForceSimulation.Parameters()
        params.cluster = pools ? Self.clusterStrength : 0
        let selectedId = selected.flatMap { $0 < model.items.count ? model.items[$0].id : nil } ?? focusId
        model = next
        sim = ForceSimulation(count: next.items.count, edges: next.edges.map { ($0.a, $0.b) },
                              groups: next.items.map { kinds.firstIndex(of: $0.kind) ?? 0 },
                              radii: next.items.map(Self.radius), previous: keep, parameters: params)
        if keep.isEmpty {
            // A fresh layout: let it untangle a little before the first frame.
            for _ in 0..<40 { sim.tick() }
        } else {
            sim.alpha = keep.count == next.items.count ? 0.25 : 0.6
        }
        neighbours = next.items.indices.map { _ in Set<Int>() }
        for e in next.edges {
            neighbours[e.a].insert(e.b)
            neighbours[e.b].insert(e.a)
        }
        labelOrder = next.items.indices.sorted { next.items[$0].degree > next.items[$1].degree }
        phases = next.items.indices.map { i in Double((i &* 2_654_435_761) % 6283) / 1000 }
        kindCounts = Self.kindOrder((source.nodes.map(\.type) + (includeSources ? source.sources.map { _ in GraphModel.fileKind } : [])))
            .map { kind in (kind, kind == GraphModel.fileKind ? source.sources.count : source.nodes.filter { $0.type == kind }.count) }
        selected = selectedId.flatMap(next.index(of:))
        hovered = nil
        highlightMatches = Self.matches(highlight, in: next)
        if keep.count < next.items.count / 2 { autoFit = true }
        wake()
    }

    private static func matches(_ text: String, in model: GraphModel) -> Set<Int> {
        let q = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return Set(model.items.indices.filter { model.items[$0].title.lowercased().contains(q) || model.items[$0].id.lowercased().contains(q) })
    }

    static func kindOrder(_ kinds: [String]) -> [String] {
        let order = WikiPath.typeSections.map(\.type) + [GraphModel.fileKind]
        return Array(Set(kinds)).sorted { (order.firstIndex(of: $0) ?? 99, $0) < (order.firstIndex(of: $1) ?? 99, $1) }
    }

    static func radius(_ item: GraphModel.Item) -> Double {
        item.isSourceFile ? 4 : 5 + 2.1 * Double(item.degree).squareRoot()
    }

    // MARK: - Frames

    /// Makes the timeline run again (after any change).
    func wake() {
        lastActivity = Date()
        if !running { running = true }
    }

    /// Advances layout and camera to `date`. Returns the seconds since the previous frame.
    func advance(to date: Date) {
        let dt = min(0.05, lastFrame.map { date.timeIntervalSince($0) } ?? 1 / 60)
        lastFrame = date
        if !sim.isSettled {
            sim.tick()
            if sim.alpha > 0.2 { sim.tick() } // unfold quicker while hot
        }
        if autoFit, let fit = fittedCamera() { targetCamera = fit }
        let k = 1 - exp(-dt * 7)
        camera.center += (targetCamera.center - camera.center) * k
        camera.zoom += (targetCamera.zoom - camera.zoom) * k
        let cameraMoving = simd_distance(camera.center, targetCamera.center) * camera.zoom > 0.3 || abs(camera.zoom - targetCamera.zoom) / targetCamera.zoom > 0.002
        if sim.isSettled && autoFit && !cameraMoving { autoFit = false }
        let recent = date.timeIntervalSince(lastActivity) < Self.restAfter && (ambientMotion || selected != nil)
        let needed = !sim.isSettled || cameraMoving || dragItem != nil || hovered != nil || recent
        let isCalm = sim.isSettled && !cameraMoving && dragItem == nil && hovered == nil
        if isCalm != calm { DispatchQueue.main.async { [weak self] in self?.calm = isCalm } }
        if !needed && running {
            // Changing observed state from inside a draw pass: defer it.
            DispatchQueue.main.async { [weak self] in self?.running = false }
        }
    }

    func fittedCamera() -> Camera? {
        guard let b = sim.bounds(), viewSize.width > 40, viewSize.height > 40 else { return nil }
        let span = b.max - b.min
        let zoom = min(Double(viewSize.width - 80) / max(span.x, 1), Double(viewSize.height - 140) / max(span.y, 1))
        return Camera(center: (b.min + b.max) / 2, zoom: min(2.2, max(0.06, zoom)))
    }

    func fit() {
        if let f = fittedCamera() { targetCamera = f }
        wake()
    }

    func zoom(by factor: Double, around point: CGPoint? = nil) {
        let anchor = point.map(world) ?? targetCamera.center
        let newZoom = min(6, max(0.04, targetCamera.zoom * factor))
        // Keep the world point under the pointer where it is.
        targetCamera.center = anchor + (targetCamera.center - anchor) * (targetCamera.zoom / newZoom)
        targetCamera.zoom = newZoom
        autoFit = false
        wake()
    }

    func pan(by delta: CGSize) {
        targetCamera.center -= SIMD2(Double(delta.width), Double(delta.height)) / targetCamera.zoom
        camera.center = targetCamera.center
        autoFit = false
        wake()
    }

    // MARK: - Coordinates

    func screen(_ p: SIMD2<Double>) -> CGPoint {
        CGPoint(x: (p.x - camera.center.x) * camera.zoom + viewSize.width / 2, y: (p.y - camera.center.y) * camera.zoom + viewSize.height / 2)
    }

    func world(_ p: CGPoint) -> SIMD2<Double> {
        SIMD2((Double(p.x) - viewSize.width / 2) / camera.zoom + camera.center.x, (Double(p.y) - viewSize.height / 2) / camera.zoom + camera.center.y)
    }

    func item(at point: CGPoint) -> Int? {
        sim.item(at: world(point), slop: 5 / camera.zoom)
    }

    /// The breathing offset of an item at `time` (a slow, small drift; nothing when motion is off).
    func drift(_ i: Int, _ time: Double) -> SIMD2<Double> {
        guard ambientMotion, i < phases.count else { return .zero }
        let ph = phases[i]
        return SIMD2(sin(time * 0.7 + ph), cos(time * 0.55 + ph * 1.3)) * 1.6
    }

    // MARK: - Pointer

    func hover(at point: CGPoint?) {
        let i = point.flatMap(item(at:))
        if i != hovered { hovered = i; wake() }
    }

    func dragChanged(start: CGPoint, location: CGPoint, translation: CGSize) {
        if dragStartCamera == nil && dragItem == nil {
            dragMoved = false
            if let i = item(at: start) {
                dragItem = i
            } else {
                dragStartCamera = targetCamera
            }
        }
        if hypot(translation.width, translation.height) > 3 { dragMoved = true }
        guard dragMoved else { return }
        if let i = dragItem {
            sim.fixed[i] = world(location)
            sim.alphaTarget = 0.25
            sim.reheat(0.25)
        } else if let c = dragStartCamera {
            targetCamera.center = c.center - SIMD2(Double(translation.width), Double(translation.height)) / camera.zoom
            camera.center = targetCamera.center
            autoFit = false
        }
        wake()
    }

    func dragEnded(location: CGPoint) {
        defer {
            dragItem = nil
            dragStartCamera = nil
            dragMoved = false
        }
        if let i = dragItem {
            sim.fixed[i] = nil
            sim.alphaTarget = 0
        }
        guard !dragMoved else { return }
        // A click.
        let i = item(at: location)
        if let i {
            selected = i
            if !model.items[i].isSourceFile {
                pickedHere = model.items[i].id
                onSelect(model.items[i].id)
            }
        } else {
            selected = nil
        }
        wake()
    }

    /// A double-click opens the page (or source file) under the pointer.
    func doubleClick(at location: CGPoint) {
        guard let i = item(at: location) else { return }
        onOpen(model.items[i])
    }

    func magnify(_ value: Double) {
        if magnifyStart == nil { magnifyStart = targetCamera }
        guard let start = magnifyStart else { return }
        targetCamera.zoom = min(6, max(0.04, start.zoom * value))
        camera.zoom = targetCamera.zoom
        autoFit = false
        wake()
    }

    func magnifyEnded() { magnifyStart = nil }

    func openSelected() {
        if let i = selected { onOpen(model.items[i]) }
    }

    // MARK: - Drawing

    /// The items the pointer or the selection lights up: the item and its neighbours.
    var focus: (item: Int, ring: Set<Int>)? {
        guard let i = hovered ?? selected, i < neighbours.count else { return nil }
        return (i, neighbours[i])
    }

    func draw(_ ctx: inout GraphicsContext, size: CGSize, time: Double, dark: Bool) {
        viewSize = size
        let n = model.items.count
        guard n > 0, sim.count == n else { return }
        let z = camera.zoom
        var pts = [CGPoint](repeating: .zero, count: n)
        for i in 0..<n { pts[i] = screen(sim.positions[i] + drift(i, time)) }
        let visible = CGRect(origin: .zero, size: size).insetBy(dx: -60, dy: -60)
        let focus = self.focus
        let lit: Set<Int> = focus.map { $0.ring.union([$0.item]) } ?? []
        let dimOthers = hovered != nil || !highlightMatches.isEmpty

        // 1. Liquid pools: the items of each kind, blurred together and cut at a threshold, so nearby
        //    bubbles of the same kind melt into one shape.
        if pools {
            let kinds = Self.kindOrder(model.items.map(\.kind))
            for kind in kinds {
                var layer = ctx
                layer.opacity = dimOthers ? 0.55 : 1
                layer.addFilter(.alphaThreshold(min: 0.42, color: GraphPalette.color(kind).opacity(dark ? 0.2 : 0.16)))
                layer.addFilter(.blur(radius: max(4, 15 * min(z, 1.6))))
                layer.drawLayer { l in
                    for i in 0..<n where model.items[i].kind == kind && visible.contains(pts[i]) {
                        let r = (sim.radii[i] + 15) * z
                        l.fill(Path(ellipseIn: CGRect(x: pts[i].x - r, y: pts[i].y - r, width: 2 * r, height: 2 * r)), with: .color(.black))
                    }
                }
            }
        }

        // 2. Threads: links as gently curved lines; the lit ones brighter, with drops flowing along them.
        let base = dark ? Color.white : Color.black
        var plain = Path()
        var litPath = Path()
        var flows: [(CGPoint, CGPoint, CGPoint)] = []
        for e in model.edges {
            let a = pts[e.a], b = pts[e.b]
            guard visible.contains(a) || visible.contains(b) else { continue }
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let bend = 0.12
            let c = CGPoint(x: mid.x - (b.y - a.y) * bend, y: mid.y + (b.x - a.x) * bend)
            let isLit = focus.map { e.a == $0.item || e.b == $0.item } ?? false
            if isLit {
                litPath.move(to: a); litPath.addQuadCurve(to: b, control: c)
                let from = e.a == focus!.item
                flows.append(from ? (a, c, b) : (b, c, a))
            } else {
                plain.move(to: a); plain.addQuadCurve(to: b, control: c)
            }
        }
        ctx.stroke(plain, with: .color(base.opacity(dimOthers ? 0.05 : (dark ? 0.13 : 0.11))), lineWidth: max(0.5, min(1.2, z)))
        if let focus {
            let color = GraphPalette.color(model.items[focus.item].kind)
            ctx.stroke(litPath, with: .color(color.opacity(0.75)), lineWidth: max(1, min(2.4, 1.6 * z)))
            let dot = max(1.6, min(3.2, 2.4 * z))
            for (k, (a, c, b)) in flows.enumerated() {
                for phase in [0.0, 0.5] {
                    let t = (time * 0.45 + phase + Double(k) * 0.137).truncatingRemainder(dividingBy: 1)
                    let p = Self.quad(a, c, b, t)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - dot, y: p.y - dot, width: 2 * dot, height: 2 * dot)), with: .color(color.opacity(0.9 * sin(t * .pi))))
                }
            }
        }

        // 3. Bubbles.
        for i in 0..<n where visible.contains(pts[i]) {
            let item = model.items[i]
            let r = max(2, sim.radii[i] * z)
            let rect = CGRect(x: pts[i].x - r, y: pts[i].y - r, width: 2 * r, height: 2 * r)
            let faded = dimOthers && !lit.contains(i) && !highlightMatches.contains(i)
            let color = GraphPalette.color(item.kind)
            let shape = item.isSourceFile ? Path(roundedRect: rect, cornerRadius: r * 0.35) : Path(ellipseIn: rect)
            ctx.fill(shape, with: .radialGradient(Gradient(colors: [color.opacity(faded ? 0.25 : 0.95), color.opacity(faded ? 0.15 : 0.7)]),
                                                  center: CGPoint(x: rect.midX - r * 0.35, y: rect.midY - r * 0.35), startRadius: 0, endRadius: r * 1.6))
            ctx.stroke(shape, with: .color(base.opacity(faded ? 0.05 : 0.18)), lineWidth: 0.6)
            if highlightMatches.contains(i) {
                ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -3.5, dy: -3.5)), with: .color(.yellow), lineWidth: 2)
            }
            if i == selected {
                let pulse = 4 + 2 * sin(time * 3)
                ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -pulse, dy: -pulse)), with: .color(color), lineWidth: 2)
                ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -1.5, dy: -1.5)), with: .color(dark ? .white : .black), lineWidth: 1.5)
            }
        }

        // 4. Labels: the focus first, then highlighted pages, then the best-connected ones, without overlaps.
        var placed: [CGRect] = []
        var order: [Int] = []
        if let focus { order.append(focus.item); order += focus.ring.sorted { model.items[$0].degree > model.items[$1].degree } }
        if let selected, !order.contains(selected) { order.append(selected) }
        order += highlightMatches.sorted { model.items[$0].degree > model.items[$1].degree }
        let budget = hovered == nil ? Int(min(90, 10 + 26 * z * z)) : 40
        order += labelOrder.prefix(budget)
        var seen = Set<Int>()
        for i in order where seen.insert(i).inserted && visible.contains(pts[i]) {
            if dimOthers && !lit.contains(i) && !highlightMatches.contains(i) && i != selected { continue }
            let strong = i == focus?.item || i == selected
            let text = ctx.resolve(Text(model.items[i].title).font(.system(size: strong ? 12.5 : 11, weight: strong ? .semibold : .regular)).foregroundStyle(Color.primary))
            let size = text.measure(in: CGSize(width: 220, height: 40))
            let r = max(2, sim.radii[i] * z)
            let box = CGRect(x: pts[i].x - size.width / 2 - 5, y: pts[i].y + r + 3, width: size.width + 10, height: size.height + 4)
            if !strong && placed.contains(where: { $0.intersects(box) }) { continue }
            placed.append(box)
            ctx.fill(Path(roundedRect: box, cornerRadius: 5), with: .color((dark ? Color.black : Color.white).opacity(strong ? 0.85 : 0.62)))
            ctx.draw(text, in: box.insetBy(dx: 5, dy: 2))
        }
    }

    private static func quad(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * a.x + 2 * u * t * c.x + t * t * b.x, y: u * u * a.y + 2 * u * t * c.y + t * t * b.y)
    }
}

/// The colour of each kind of page in the graph and its legend.
enum GraphPalette {
    static func color(_ kind: String) -> Color {
        switch kind {
        case "overview": return Color(red: 0.95, green: 0.55, blue: 0.2)
        case "entity": return Color(red: 0.27, green: 0.52, blue: 0.95)
        case "concept": return Color(red: 0.62, green: 0.38, blue: 0.92)
        case "synthesis": return Color(red: 0.93, green: 0.36, blue: 0.6)
        case "source": return Color(red: 0.16, green: 0.69, blue: 0.62)
        case "lint": return Color(red: 0.9, green: 0.3, blue: 0.25)
        case GraphModel.fileKind: return Color(red: 0.62, green: 0.55, blue: 0.45)
        default: return Color(red: 0.55, green: 0.58, blue: 0.62)
        }
    }

    static func title(_ kind: String) -> String {
        if kind == GraphModel.fileKind { return "Source files" }
        return WikiPath.typeSections.first { $0.type == kind }?.title ?? kind.capitalized
    }
}
