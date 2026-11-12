import SwiftUI

/// One entry of a menu, shown both in the popup menu of a main button (`MainMenuView`) and in the toolbar menus of
/// the views (`MenuEntriesContent`), so that both offer the same functions (Cachebox `Menu`/`MenuItem`).
struct MenuEntry: Identifiable {
    enum Kind {
        case action(() -> Void)
        /// Opens the entries as a submenu (Cachebox: a menu item that shows another `Menu` or `OptionMenu`).
        case submenu([MenuEntry])
        case divider
    }

    var id: String
    var title: String
    var systemImage: String?
    var kind: Kind
    var isDisabled = false
    /// Checkmark of a checkable entry (Cachebox `addCheckableMenuItem`); nil if the entry cannot be checked.
    var isChecked: Bool?
    var role: ButtonRole?
    /// The entry can also be reached by swiping the main button in this direction (Cachebox shows the direction
    /// behind the title, "(wischen nach oben)").
    var gesture: SwipeDirection?
    /// The popup stays open after a tap, so that several options can be switched in a row (Cachebox `OptionMenu`).
    var keepsMenuOpen = false
    /// Runs as soon as the entry is tapped. Other entries run once the popup has closed, because they may present a
    /// sheet or an alert, which UIKit refuses while the popup is still on screen.
    var runsImmediately = false

    init(_ title: String, systemImage: String? = nil, id: String? = nil, isDisabled: Bool = false,
         isChecked: Bool? = nil, role: ButtonRole? = nil, gesture: SwipeDirection? = nil,
         keepsMenuOpen: Bool = false, runsImmediately: Bool = false, action: @escaping () -> Void) {
        self.id = id ?? title
        self.title = title
        self.systemImage = systemImage
        self.kind = .action(action)
        self.isDisabled = isDisabled
        self.isChecked = isChecked
        self.role = role
        self.gesture = gesture
        self.keepsMenuOpen = keepsMenuOpen
        self.runsImmediately = runsImmediately
    }

    init(_ title: String, systemImage: String? = nil, id: String? = nil, isDisabled: Bool = false,
         entries: [MenuEntry]) {
        self.id = id ?? title
        self.title = title
        self.systemImage = systemImage
        self.kind = .submenu(entries)
        self.isDisabled = isDisabled
    }

    /// A line between groups of entries; `id` must be unique within the menu.
    static func divider(_ id: String) -> MenuEntry {
        var entry = MenuEntry(id, id: "divider-" + id, entries: [])
        entry.kind = .divider
        return entry
    }

    var isDivider: Bool {
        if case .divider = kind { true } else { false }
    }
}

/// Direction of a swipe on a main button (Cachebox `CB_ActionButton.GestureDirection`).
enum SwipeDirection {
    case up, down, left, right

    var systemImage: String {
        switch self {
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .left: "arrow.left"
        case .right: "arrow.right"
        }
    }

    /// "wischen nach oben", as Cachebox writes it behind the menu title.
    var spokenText: String {
        switch self {
        case .up: "nach oben wischen"
        case .down: "nach unten wischen"
        case .left: "nach links wischen"
        case .right: "nach rechts wischen"
        }
    }
}

/// The entries as the content of a SwiftUI `Menu` (toolbar menus).
struct MenuEntriesContent: View {
    let entries: [MenuEntry]

    var body: some View {
        ForEach(entries) { entry in
            switch entry.kind {
            case .action(let run):
                if let checked = entry.isChecked {
                    Toggle(isOn: Binding(get: { checked }, set: { _ in run() })) { label(entry) }
                        .disabled(entry.isDisabled)
                } else {
                    Button(role: entry.role, action: run) { label(entry) }
                        .disabled(entry.isDisabled)
                }
            case .submenu(let children):
                Menu {
                    MenuEntriesContent(entries: children)
                } label: {
                    label(entry)
                }
                .disabled(entry.isDisabled)
            case .divider:
                Divider()
            }
        }
    }

    @ViewBuilder
    private func label(_ entry: MenuEntry) -> some View {
        if let symbol = entry.systemImage {
            Label(entry.title, systemImage: symbol)
        } else {
            Text(entry.title)
        }
    }
}
