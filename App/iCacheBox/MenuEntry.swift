import SwiftUI

/// One entry of a menu, shown both in the popup menu of a main button (`MainMenuView`) and in the menu buttons of
/// the views (`CacheboxMenuButton`), so that both offer the same functions (Cachebox `Menu`/`MenuItem`).
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

// MARK: - Cachebox menu

/// A menu in the Cachebox style (Cachebox `Menu`, a dialog of `MenuItem`s, day skin): green box with the title on
/// top, the entries as boxes in white and light grey in turn (yellow while pressed), green lines between groups.
/// Submenus open in place with a back button. Shown in a popover by the main buttons (`MainMenuView`) and by the
/// menu buttons of the views (`CacheboxMenuButton`); light also in dark mode, like the main buttons.
struct CacheboxMenu: View {
    let title: String
    let entries: [MenuEntry]

    /// Id of the divider between the context menu of a view and the functions of its button, drawn thicker.
    static let functionsDivider = "functions"

    @Environment(\.dismiss) private var dismiss
    /// Ids of the opened submenus.
    @State private var path: [String] = []
    /// Entry to run once the popup is gone.
    @State private var pending: (() -> Void)?
    @State private var contentHeight: CGFloat = 0

    private static let width: CGFloat = 300
    private static let maxHeight: CGFloat = 640
    /// Space around the boxes and between them.
    private static let inset: CGFloat = 6
    private static let spacing: CGFloat = 3

    var body: some View {
        let (title, entries) = current
        // one column for the checkmarks, so that the symbols line up
        let checkColumn = entries.contains { $0.isChecked != nil }
        VStack(spacing: 0) {
            header(title)
            ScrollView {
                VStack(spacing: Self.spacing) {
                    ForEach(numbered(entries), id: \.entry.id) { item in
                        row(item.entry, index: item.index, checkColumn: checkColumn)
                    }
                }
                .padding(Self.inset)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .modifier(NoScrollEdgeEffect())
            .frame(height: min(max(contentHeight, 44), Self.maxHeight))
        }
        .frame(width: Self.width)
        .background(Color.cacheboxActivity)
        .foregroundStyle(Color.black)
        .environment(\.colorScheme, .light)
        .presentationBackground(Color.cacheboxActivity)
        .background(PopoverColor(color: UIColor(Color.cacheboxActivity)))
        .onDisappear {
            pending?()
            pending = nil
        }
    }

    /// Title and entries of the root menu or of the opened submenu.
    private var current: (String, [MenuEntry]) {
        var title = self.title
        var entries = self.entries
        for id in path {
            guard let entry = entries.first(where: { $0.id == id }), case .submenu(let children) = entry.kind else { break }
            title = entry.title
            entries = children
        }
        return (title, entries)
    }

    /// The entries with the position of each box for its colour (dividers are not counted).
    private func numbered(_ entries: [MenuEntry]) -> [(index: Int, entry: MenuEntry)] {
        var index = 0
        return entries.map { entry in
            defer { if !entry.isDivider { index += 1 } }
            return (index, entry)
        }
    }

    /// Title bar in the green of the dialog frame (Cachebox `dialog-title`).
    private func header(_ title: String) -> some View {
        HStack(spacing: 8) {
            if !path.isEmpty {
                Button {
                    path.removeLast()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zurück")
            }
            Text(title)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, path.isEmpty ? 16 : 8)
        .padding(.trailing, 16)
        .frame(minHeight: 44)
        .background(Color.cacheboxFrame)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func row(_ entry: MenuEntry, index: Int, checkColumn: Bool) -> some View {
        switch entry.kind {
        case .divider:
            CacheboxDivider(isThick: entry.id == "divider-" + Self.functionsDivider)
        case .submenu:
            Button {
                path.append(entry.id)
            } label: {
                rowLabel(entry, checkColumn: checkColumn) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.black.opacity(0.45))
                }
            }
            .buttonStyle(CacheboxRowStyle(index: index))
            .disabled(entry.isDisabled)
        case .action(let run):
            Button {
                if entry.keepsMenuOpen {
                    run()
                } else if entry.runsImmediately {
                    run()
                    dismiss()
                } else {
                    pending = run
                    dismiss()
                }
            } label: {
                rowLabel(entry, checkColumn: checkColumn) {
                    if let gesture = entry.gesture {
                        Image(systemName: gesture.systemImage)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.black.opacity(0.45))
                            .accessibilityLabel(gesture.spokenText)
                    }
                }
            }
            .buttonStyle(CacheboxRowStyle(index: index))
            .disabled(entry.isDisabled)
            .accessibilityAddTraits(entry.isChecked == true ? .isSelected : [])
        }
    }

    private func rowLabel(_ entry: MenuEntry, checkColumn: Bool,
                          @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 12) {
            if checkColumn {
                Image(systemName: "checkmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color.cachebox)
                    .opacity(entry.isChecked == true ? 1 : 0)
                    .frame(width: 18)
                    .accessibilityHidden(true)
            }
            if let symbol = entry.systemImage {
                Image(systemName: symbol)
                    .frame(width: 24)
                    .accessibilityHidden(true)
            }
            Text(entry.title)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            trailing()
        }
        .foregroundStyle(entry.role == .destructive ? Color.red : Color.black)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// Without the faded scroll edge of iOS 26, which made the last box of a long menu look disabled.
private struct NoScrollEdgeEffect: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden()
        } else {
            content
        }
    }
}

/// A menu row on its Cachebox box: yellow while pressed, the content faded when disabled.
private struct CacheboxRowStyle: ButtonStyle {
    let index: Int
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? 1 : 0.4)
            .background { CacheboxRowBox(index: index, isSelected: configuration.isPressed) }
    }
}

/// A button of a view (toolbar, map) that opens the context menu of the view as a `CacheboxMenu` in a popover, the
/// same as the menu of its main button (instead of a system `Menu`, which cannot take the Cachebox colours).
struct CacheboxMenuButton<Label: View>: View {
    /// Built when the menu opens and again on every change while it is open.
    let menu: () -> ViewContextMenu
    @ViewBuilder let label: () -> Label

    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen = true
        } label: {
            label()
        }
        .popover(isPresented: $isOpen) {
            LiveMenu(menu: menu)
                .presentationCompactAdaptation(.popover)
        }
    }

    /// Calls `menu` in its own body, so that the popup follows the state it reads.
    private struct LiveMenu: View {
        let menu: () -> ViewContextMenu

        var body: some View {
            let menu = menu()
            CacheboxMenu(title: menu.title, entries: menu.entries)
        }
    }
}

/// Colours the popover around a view, arrow included: `presentationBackground` leaves the arrow in glass.
private struct PopoverColor: UIViewRepresentable {
    let color: UIColor

    func makeUIView(context: Context) -> ColorView { ColorView(color: color) }
    func updateUIView(_ view: ColorView, context: Context) {}

    final class ColorView: UIView {
        let color: UIColor

        init(color: UIColor) {
            self.color = color
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            // the hosting controller of the popover content, or one of its parents; setting the colour moves the
            // popover's views again (and calls this again), so only once
            var responder: UIResponder? = self
            while let next = responder {
                if let controller = next as? UIViewController, let popover = controller.popoverPresentationController {
                    if popover.backgroundColor != color { popover.backgroundColor = color }
                    return
                }
                responder = next.next
            }
        }
    }
}
