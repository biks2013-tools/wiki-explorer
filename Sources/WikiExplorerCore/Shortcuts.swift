import Foundation

/// A key combination of the app, listed in the Keyboard Shortcuts window. The menu commands take their
/// shortcuts from `AppShortcuts`, so the window always shows what the menus do.
public struct AppShortcut: Hashable, Sendable, Identifiable {
    public enum Modifier: Int, CaseIterable, Comparable, Sendable {
        // Apple's display order: ⌃ ⌥ ⇧ ⌘
        case control, option, shift, command
        public var symbol: String { ["⌃", "⌥", "⇧", "⌘"][rawValue] }
        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    public enum Section: String, CaseIterable, Sendable {
        case wikis = "Wikis and sources"
        case pages = "Pages and navigation"
        case graph = "Graph"
        case ask = "Ask"
        case windows = "Windows and help"
        case dialogs = "Dialogs and lists"
        case tour = "Guided tour"
    }

    /// One character (`"k"`, `"["`, `"/"`) or a named key: `return`, `escape`, `up`, `down`, `left`, `right`, `space`.
    public let key: String
    public let modifiers: Set<Modifier>
    public let title: String
    public let detail: String?
    public let section: Section
    /// True for shortcuts that a menu command of the app owns (unique app-wide); false for keys that work
    /// only inside one place (a dialog, a list, the tour) or that macOS provides.
    public let isMenuCommand: Bool

    public init(_ key: String, _ modifiers: Set<Modifier>, _ title: String, detail: String? = nil, section: Section, menu: Bool = true) {
        self.key = key; self.modifiers = modifiers; self.title = title; self.detail = detail; self.section = section; self.isMenuCommand = menu
    }

    public var id: String { "\(section.rawValue)|\(title)|\(display)" }

    /// The combination as macOS shows it: `⇧⌘N`, `⌘↩`, `Esc`.
    public var display: String {
        modifiers.sorted().map(\.symbol).joined() + Self.keySymbol(key)
    }

    public static func keySymbol(_ key: String) -> String {
        switch key {
        case "return": return "↩"
        case "escape": return "Esc"
        case "up": return "↑"
        case "down": return "↓"
        case "left": return "←"
        case "right": return "→"
        case "space": return "Space"
        default: return key.uppercased()
        }
    }
}

public enum AppShortcuts {
    public static let newWiki = AppShortcut("n", [.shift, .command], "New wiki", section: .wikis)
    public static let addSources = AppShortcut("i", [.command], "Add sources (files or web pages)", section: .wikis)
    public static let checkSources = AppShortcut("u", [.command], "Check sources for changes", section: .wikis)
    public static let reloadWikis = AppShortcut("r", [.command], "Reload wikis", section: .wikis)

    public static let search = AppShortcut("f", [.command], "Search", detail: "this wiki, or all wikis with the checkbox", section: .pages)
    public static let back = AppShortcut("[", [.command], "Back", section: .pages)
    public static let forward = AppShortcut("]", [.command], "Forward", section: .pages)
    public static let openInBrowser = AppShortcut("o", [.shift, .command], "Open page in browser", detail: "HTML wikis", section: .pages)
    public static let showInFinder = AppShortcut("r", [.option, .command], "Show page in Finder", section: .pages)
    public static let openSourceFolder = AppShortcut("r", [.shift, .option, .command], "Show page's sources in Finder", section: .pages)

    public static let graph = AppShortcut("g", [.command], "Show the graph, or the page again", detail: "the wiki as a map of linked pages", section: .graph)
    public static let showInGraph = AppShortcut("g", [.shift, .command], "Show the open page in the graph", detail: "its neighbourhood", section: .graph)
    public static let fitGraph = AppShortcut("0", [.command], "Fit the graph to the window", section: .graph)
    public static let zoomIn = AppShortcut("=", [.command], "Zoom in", detail: "also pinch, or scroll with ⌘", section: .graph)
    public static let zoomOut = AppShortcut("-", [.command], "Zoom out", section: .graph)

    public static let ask = AppShortcut("k", [.command], "Show or hide the Ask panel", section: .ask)
    public static let sendQuestion = AppShortcut("return", [.command], "Send the question", detail: "in the Ask panel", section: .ask, menu: false)

    public static let tour = AppShortcut("t", [.shift, .command], "Take the guided tour", section: .windows)
    public static let shortcutsGuide = AppShortcut("/", [.command], "Keyboard shortcuts (this window)", section: .windows)

    /// Every shortcut, in the order the guide lists them. The system ones are listed so the guide is complete.
    public static let all: [AppShortcut] = [
        newWiki, addSources, checkSources, reloadWikis,
        search, back, forward, openInBrowser, showInFinder, openSourceFolder,
        AppShortcut("down", [], "Next page or wiki", detail: "in a list", section: .pages, menu: false),
        AppShortcut("up", [], "Previous page or wiki", detail: "in a list", section: .pages, menu: false),
        graph, showInGraph, fitGraph, zoomIn, zoomOut,
        AppShortcut("return", [], "Open the selected page", detail: "in the graph; also double-click", section: .graph, menu: false),
        AppShortcut("escape", [], "Clear the selection", detail: "in the graph", section: .graph, menu: false),
        ask, sendQuestion,
        tour, shortcutsGuide,
        AppShortcut("s", [.control, .command], "Show or hide the wiki list", section: .windows, menu: false),
        AppShortcut(",", [.command], "Settings", section: .windows, menu: false),
        AppShortcut("f", [.control, .command], "Full screen", section: .windows, menu: false),
        AppShortcut("m", [.command], "Minimize", section: .windows, menu: false),
        AppShortcut("w", [.command], "Close window", section: .windows, menu: false),
        AppShortcut("q", [.command], "Quit Wiki Explorer", section: .windows, menu: false),
        AppShortcut("return", [], "Confirm (the blue button)", section: .dialogs, menu: false),
        AppShortcut("escape", [], "Cancel or close", section: .dialogs, menu: false),
        AppShortcut("right", [], "Next step", detail: "also ↩", section: .tour, menu: false),
        AppShortcut("left", [], "Previous step", section: .tour, menu: false),
        AppShortcut("escape", [], "End the tour", section: .tour, menu: false),
    ]

    /// Shortcuts whose title, detail or keys match `filter` (case-insensitive), grouped by section in display order.
    public static func grouped(matching filter: String = "") -> [(section: AppShortcut.Section, shortcuts: [AppShortcut])] {
        let f = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hits = all.filter { s in
            f.isEmpty || s.title.lowercased().contains(f) || (s.detail?.lowercased().contains(f) ?? false) || s.display.lowercased().contains(f)
        }
        return AppShortcut.Section.allCases.compactMap { section in
            let members = hits.filter { $0.section == section }
            return members.isEmpty ? nil : (section, members)
        }
    }
}
