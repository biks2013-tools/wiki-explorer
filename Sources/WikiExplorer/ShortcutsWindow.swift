import SwiftUI
import WikiExplorerCore

extension AppShortcut {
    /// The SwiftUI shortcut of a menu command.
    var keyboardShortcut: KeyboardShortcut {
        let key: KeyEquivalent
        switch self.key {
        case "return": key = .return
        case "escape": key = .escape
        case "up": key = .upArrow
        case "down": key = .downArrow
        case "left": key = .leftArrow
        case "right": key = .rightArrow
        case "space": key = .space
        default: key = KeyEquivalent(Character(self.key))
        }
        var m: EventModifiers = []
        if modifiers.contains(.command) { m.insert(.command) }
        if modifiers.contains(.shift) { m.insert(.shift) }
        if modifiers.contains(.option) { m.insert(.option) }
        if modifiers.contains(.control) { m.insert(.control) }
        return KeyboardShortcut(key, modifiers: m)
    }
}

extension View {
    func keyboardShortcut(_ shortcut: AppShortcut) -> some View { keyboardShortcut(shortcut.keyboardShortcut) }
}

/// Help › Keyboard Shortcuts: every key of the app, grouped, with a filter.
struct ShortcutsGuideView: View {
    @State private var filter = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "keyboard").font(.title2).foregroundStyle(.secondary)
                Text("Keyboard Shortcuts").font(.title2.weight(.semibold))
                Spacer()
                TextField("Filter", text: $filter).textFieldStyle(.roundedBorder).frame(width: 200)
            }
            .padding(16)
            Divider()
            ScrollView {
                let groups = AppShortcuts.grouped(matching: filter)
                if groups.isEmpty {
                    ContentUnavailableView.search(text: filter).padding(.top, 40)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 28, alignment: .top), GridItem(.flexible(), spacing: 28, alignment: .top)], alignment: .leading, spacing: 22) {
                    ForEach(groups, id: \.section) { group in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(group.section.rawValue).font(.headline)
                            ForEach(group.shortcuts) { s in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(s.title)
                                        if let d = s.detail { Text(d).font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer(minLength: 8)
                                    KeyCaps(shortcut: s)
                                }
                                Divider().opacity(0.5)
                            }
                        }
                    }
                }
                .padding(20)
            }
            Divider()
            Text("Menu commands also show their keys next to them in the menu bar.")
                .font(.caption).foregroundStyle(.secondary).padding(10)
        }
        .frame(minWidth: 720, idealWidth: 760, minHeight: 520, idealHeight: 640)
    }
}

/// A key combination drawn as key caps: ⇧ ⌘ N.
struct KeyCaps: View {
    let shortcut: AppShortcut

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                Text(cap)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .frame(minWidth: 22, minHeight: 22)
                    .padding(.horizontal, cap.count > 1 ? 6 : 0)
                    .background(RoundedRectangle(cornerRadius: 5).fill(.background.secondary))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shortcut.display)
    }

    private var caps: [String] { shortcut.modifiers.sorted().map(\.symbol) + [AppShortcut.keySymbol(shortcut.key)] }
}
