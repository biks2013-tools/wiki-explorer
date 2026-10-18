import Foundation

/// `llm-wiki graph --json`: the pages of a wiki, the links between them, and the source files they cite.
public struct WikiGraph: Decodable, Sendable, Equatable {
    public struct Node: Decodable, Sendable, Hashable {
        public let id: String
        public let title: String
        public let type: String
        public let summary: String?
        public let degree: Int
    }

    public struct Link: Decodable, Sendable, Hashable {
        public let from: String
        public let to: String
    }

    public struct Source: Decodable, Sendable, Hashable {
        public let path: String
        public let exists: Bool
        public let pages: [String]
    }

    public struct Missing: Decodable, Sendable, Hashable {
        public let from: String
        public let target: String
    }

    public let wiki: String
    public let format: String
    public let nodes: [Node]
    public let links: [Link]
    public let sources: [Source]
    public let missing: [Missing]
}

/// What the graph view shows: a subset of the wiki graph with undirected edges, ready for the simulation.
public struct GraphModel: Sendable, Equatable {
    public struct Item: Sendable, Hashable, Identifiable {
        /// The page id, or `raw:<path>` for a source file.
        public let id: String
        public let title: String
        /// The page type (`entity`, `concept`, …) or `file` for a source file.
        public let kind: String
        public let summary: String?
        /// Edges of this item in the shown graph.
        public var degree: Int
        public var isSourceFile: Bool { kind == GraphModel.fileKind }
        /// The source file's path under the wiki root (`raw/…`), for file items.
        public var rawPath: String? { isSourceFile ? String(id.dropFirst(GraphModel.filePrefix.count)) : nil }
    }

    public struct Edge: Sendable, Hashable {
        public let a: Int
        public let b: Int
        /// True when both pages link to each other.
        public let mutual: Bool
        /// True for a page → source file edge.
        public let cites: Bool
    }

    public static let fileKind = "file"
    public static let filePrefix = "raw:"

    public var items: [Item]
    public var edges: [Edge]

    public init(items: [Item], edges: [Edge]) {
        self.items = items
        self.edges = edges
    }

    public func index(of id: String) -> Int? { items.firstIndex { $0.id == id } }

    /// Item indices joined to `i` by an edge.
    public func neighbours(of i: Int) -> Set<Int> {
        var out = Set<Int>()
        for e in edges {
            if e.a == i { out.insert(e.b) } else if e.b == i { out.insert(e.a) }
        }
        return out
    }

    /// Builds the shown graph.
    /// - Parameters:
    ///   - includeSources: add the cited source files as items, joined to the pages that cite them.
    ///   - hiddenKinds: page types (or `file`) to leave out.
    ///   - focus / depth: when both are given, only items within `depth` steps of the `focus` page.
    public static func build(from graph: WikiGraph, includeSources: Bool, hiddenKinds: Set<String> = [], focus: String? = nil, depth: Int? = nil) -> GraphModel {
        var items: [Item] = graph.nodes.map { Item(id: $0.id, title: $0.title, kind: $0.type, summary: $0.summary, degree: 0) }
        if includeSources {
            items += graph.sources.map { s in
                Item(id: filePrefix + s.path, title: (s.path as NSString).lastPathComponent, kind: fileKind,
                     summary: s.exists ? s.path : "\(s.path) (not in raw/)", degree: 0)
            }
        }
        var index = [String: Int]()
        for (i, item) in items.enumerated() { index[item.id] = i }

        // Undirected page edges, one per pair, marked mutual when both directions exist.
        var pairs = [Pair: Bool]()
        for l in graph.links {
            guard let a = index[l.from], let b = index[l.to], a != b else { continue }
            let p = Pair(a, b)
            pairs[p] = pairs[p] != nil
        }
        var edges = pairs.map { Edge(a: $0.key.lo, b: $0.key.hi, mutual: $0.value, cites: false) }
        if includeSources {
            for s in graph.sources {
                guard let f = index[filePrefix + s.path] else { continue }
                for page in s.pages { if let p = index[page] { edges.append(Edge(a: p, b: f, mutual: false, cites: true)) } }
            }
        }
        edges.sort { ($0.a, $0.b) < ($1.a, $1.b) }

        // Keep: not hidden, and (when focused) within reach of the focus page.
        var keep = Set(items.indices.filter { !hiddenKinds.contains(items[$0].kind) })
        if let focus, let depth, let start = index[focus] {
            var adjacency = [Int: [Int]]()
            for e in edges where keep.contains(e.a) && keep.contains(e.b) {
                adjacency[e.a, default: []].append(e.b)
                adjacency[e.b, default: []].append(e.a)
            }
            var reached: Set<Int> = [start]
            var frontier = [start]
            for _ in 0..<max(0, depth) {
                var next = [Int]()
                for i in frontier { for j in adjacency[i] ?? [] where reached.insert(j).inserted { next.append(j) } }
                frontier = next
            }
            keep = keep.intersection(reached).union([start])
        }

        let kept = items.indices.filter { keep.contains($0) }
        var remap = [Int: Int]()
        for (new, old) in kept.enumerated() { remap[old] = new }
        var outItems = kept.map { items[$0] }
        let outEdges = edges.compactMap { e -> Edge? in
            guard let a = remap[e.a], let b = remap[e.b] else { return nil }
            return Edge(a: a, b: b, mutual: e.mutual, cites: e.cites)
        }
        for e in outEdges {
            outItems[e.a].degree += 1
            outItems[e.b].degree += 1
        }
        return GraphModel(items: outItems, edges: outEdges)
    }

    private struct Pair: Hashable {
        let lo: Int
        let hi: Int
        init(_ a: Int, _ b: Int) { lo = min(a, b); hi = max(a, b) }
    }
}

/// A force-directed layout in the manner of d3-force: items repel each other, edges act as springs, items of
/// the same kind drift towards each other, and everything is pulled gently to the middle. Motion cools down
/// (`alpha`) until the layout rests; dragging an item or changing the graph warms it up again.
public final class ForceSimulation {
    public struct Parameters: Sendable, Equatable {
        /// Repulsion between every two items (d3 many-body strength; negative repels).
        public var charge: Double = -70
        public var chargeDistanceMax: Double = 700
        public var linkDistance: Double = 30
        /// Attraction towards the centre of the item's kind (0 = off).
        public var cluster: Double = 0.06
        /// Pull towards the origin, so separate parts stay in view.
        public var gravity: Double = 0.025
        /// Fraction of velocity lost per tick.
        public var velocityDecay: Double = 0.42
        public var alphaMin: Double = 0.002
        public var alphaDecay: Double = 1 - pow(0.002, 1.0 / 320)
        public init() {}
    }

    public var parameters: Parameters
    public private(set) var positions: [SIMD2<Double>]
    public private(set) var velocities: [SIMD2<Double>]
    /// Radius of each item, used to keep items from overlapping.
    public let radii: [Double]
    public let edges: [(Int, Int)]
    /// Group (kind) of each item.
    public let groups: [Int]
    /// Items held in place (being dragged).
    public var fixed: [Int: SIMD2<Double>] = [:]
    public var alpha: Double = 1
    /// The temperature motion settles to: above zero while the user drags an item.
    public var alphaTarget: Double = 0
    private let linkStrength: [Double]
    private let linkBias: [Double]

    /// - Parameter previous: positions to start from by item index (kept when the shown graph changes);
    ///   other items start next to a placed neighbour, or on a sunflower spiral.
    public init(count: Int, edges: [(Int, Int)], groups: [Int], radii: [Double], previous: [Int: SIMD2<Double>] = [:], parameters: Parameters = Parameters()) {
        precondition(groups.count == count && radii.count == count)
        self.parameters = parameters
        self.edges = edges
        self.groups = groups
        self.radii = radii
        var degree = [Int](repeating: 0, count: count)
        for (a, b) in edges { degree[a] += 1; degree[b] += 1 }
        linkStrength = edges.map { 1 / Double(max(1, min(degree[$0.0], degree[$0.1]))) }
        linkBias = edges.map { Double(degree[$0.0]) / Double(max(1, degree[$0.0] + degree[$0.1])) }

        var pos = [SIMD2<Double>?](repeating: nil, count: count)
        for (i, p) in previous where i < count { pos[i] = p }
        if previous.isEmpty {
            let golden = Double.pi * (3 - sqrt(5))
            for i in 0..<count {
                let r = 12 * sqrt(0.5 + Double(i))
                pos[i] = SIMD2(r * cos(Double(i) * golden), r * sin(Double(i) * golden))
            }
        } else {
            // New items appear beside a neighbour that already has a place, so the graph grows out of itself.
            var adjacency = [Int: [Int]]()
            for (a, b) in edges { adjacency[a, default: []].append(b); adjacency[b, default: []].append(a) }
            var progress = true
            while progress {
                progress = false
                for i in 0..<count where pos[i] == nil {
                    if let n = adjacency[i]?.first(where: { pos[$0] != nil }), let p = pos[n] {
                        pos[i] = p + Self.jitter(i, scale: 18)
                        progress = true
                    }
                }
            }
            for i in 0..<count where pos[i] == nil { pos[i] = Self.jitter(i, scale: 120) }
        }
        positions = pos.map { $0! }
        velocities = [SIMD2<Double>](repeating: .zero, count: count)
    }

    public var count: Int { positions.count }
    public var isSettled: Bool { alpha < parameters.alphaMin && alphaTarget == 0 }

    /// Warms the layout up so it moves again.
    public func reheat(_ to: Double = 0.3) { alpha = max(alpha, to) }

    /// Advances the layout one step.
    public func tick() {
        let n = count
        guard n > 0 else { return }
        alpha += (alphaTarget - alpha) * parameters.alphaDecay
        let alpha = self.alpha
        let p = parameters

        // Springs along the edges.
        for (k, (a, b)) in edges.enumerated() {
            var d = (positions[b] + velocities[b]) - (positions[a] + velocities[a])
            if d.x == 0 && d.y == 0 { d = Self.jitter(k, scale: 1e-3) }
            let l = (d.x * d.x + d.y * d.y).squareRoot()
            let target = p.linkDistance + radii[a] + radii[b]
            let f = d * ((l - target) / l * alpha * linkStrength[k])
            velocities[b] -= f * linkBias[k]
            velocities[a] += f * (1 - linkBias[k])
        }

        // Repulsion and overlap, every pair.
        let maxD2 = p.chargeDistanceMax * p.chargeDistanceMax
        for i in 0..<n {
            let pi = positions[i]
            for j in (i + 1)..<n {
                var d = positions[j] - pi
                var l2 = d.x * d.x + d.y * d.y
                if l2 == 0 {
                    d = Self.jitter(i * 31 + j, scale: 1e-2)
                    l2 = d.x * d.x + d.y * d.y
                }
                let reach = radii[i] + radii[j] + 2
                if l2 < reach * reach {
                    let l = l2.squareRoot()
                    let push = d * ((reach - l) / l * 0.35)
                    velocities[i] -= push
                    velocities[j] += push
                }
                guard l2 < maxD2 else { continue }
                let w = p.charge * alpha / max(l2, 16)
                velocities[i] += d * w
                velocities[j] -= d * w
            }
        }

        // Kinds drift together; everything drifts to the middle.
        if p.cluster > 0 {
            var sums = [Int: (SIMD2<Double>, Double)]()
            for i in 0..<n { let s = sums[groups[i]] ?? (.zero, 0); sums[groups[i]] = (s.0 + positions[i], s.1 + 1) }
            for i in 0..<n {
                let (sum, c) = sums[groups[i]]!
                velocities[i] += (sum / c - positions[i]) * (p.cluster * alpha)
            }
        }
        for i in 0..<n { velocities[i] -= positions[i] * (p.gravity * alpha) }

        for i in 0..<n {
            if let f = fixed[i] {
                positions[i] = f
                velocities[i] = .zero
            } else {
                velocities[i] *= (1 - p.velocityDecay)
                positions[i] += velocities[i]
            }
        }
    }

    /// The item nearest to `point` whose circle (plus `slop`) contains it.
    public func item(at point: SIMD2<Double>, slop: Double = 0) -> Int? {
        var best: (Int, Double)?
        for i in 0..<count {
            let d = positions[i] - point
            let l2 = d.x * d.x + d.y * d.y
            let r = radii[i] + slop
            if l2 <= r * r, l2 < (best?.1 ?? .infinity) { best = (i, l2) }
        }
        return best?.0
    }

    /// The rectangle holding every item (with their radii), or nil when there are none.
    public func bounds(of subset: [Int]? = nil) -> (min: SIMD2<Double>, max: SIMD2<Double>)? {
        let ids = subset ?? Array(0..<count)
        guard let first = ids.first else { return nil }
        var lo = positions[first] - radii[first]
        var hi = positions[first] + radii[first]
        for i in ids {
            lo = pointwiseMin(lo, positions[i] - radii[i])
            hi = pointwiseMax(hi, positions[i] + radii[i])
        }
        return (lo, hi)
    }

    /// A small deterministic offset (the layout is the same every time for the same graph).
    static func jitter(_ seed: Int, scale: Double) -> SIMD2<Double> {
        var x = UInt64(truncatingIfNeeded: seed) &* 0x9E37_79B9_7F4A_7C15 &+ 0x6A09_E667
        x ^= x >> 31; x &*= 0xBF58_476D_1CE4_E5B9; x ^= x >> 29
        let a = Double(x & 0xFFFF) / 65535 * 2 * .pi
        let r = (0.35 + Double((x >> 16) & 0xFFFF) / 65535 * 0.65) * scale
        return SIMD2(r * cos(a), r * sin(a))
    }
}
