import SwiftUI

// The five main buttons at the bottom, as in Cachebox (`ViewManager.addPhoneTab`, `GestureButton`, `CB_TabView`):
//
// - Tapping a button whose view is not shown shows its last view (setting `rememberLastAction`, on by default), the
//   first time its default view; a button without a default view (Werkzeuge) opens its menu instead.
// - Tapping the button of the shown view opens its menu: first the context menu of that view, then all functions
//   of the button (Cachebox: `compoundMenu`).
// - Swiping across a button runs the function for that direction (Cachebox `GestureDirection`).
// - Holding a button opens the list of its functions (the long click of earlier Cachebox versions).
//
// The button of the shown view is drawn pressed (yellow); if the view has a context menu, three dots in the corner
// say so (`cmIcon`, red `MENUFILTERED` on the list and navigation buttons while a filter is set). The images are
// the Cachebox day skin (`Assets.xcassets/CacheboxButtons`, rights: see UI-KONZEPT.md).

/// A main button (Cachebox `ViewManager.mainBtn1` … `mainBtn5`).
enum MainButton: Int, CaseIterable, Identifiable {
    case caches, cache, navigation, tools, misc

    var id: Self { self }

    var title: String {
        switch self {
        case .caches: "Cacheliste"
        case .cache: "Cache"
        case .navigation: "Navigation"
        case .tools: "Werkzeuge"
        case .misc: "Sonstiges"
        }
    }

    /// Sprite name in the Cachebox skin (`db`, `cache`, `Nav`, `tool`, `misc`).
    fileprivate var imageName: String {
        switch self {
        case .caches: "db"
        case .cache: "cache"
        case .navigation: "Nav"
        case .tools: "tool"
        case .misc: "misc"
        }
    }

    /// The functions of the button in the order of the Cachebox menu, with default and swipe direction
    /// (`ViewManager.addPhoneTab`). Functions that are not built yet stay in the menu, greyed out.
    var functions: [ButtonFunction] {
        switch self {
        case .caches:
            [.init(.show(.cacheList), isDefault: true, gesture: .up),
             .init(.parking, gesture: .down),
             .init(.trackables, gesture: .right),
             .init(.share, gesture: .left)]
        case .cache:
            [.init(.show(.description), isDefault: true, gesture: .up),
             .init(.show(.waypoints), gesture: .right),
             .init(.hint),
             .init(.show(.spoiler)),
             .init(.show(.logs), gesture: .down),
             .init(.notes, gesture: .left),
             .init(.browser)]
        case .navigation:
            [.init(.show(.map), isDefault: true, gesture: .up),
             .init(.show(.compass), gesture: .right),
             .init(.navigate, gesture: .down),
             .init(.tracks, gesture: .left),
             .init(.mapDownload)]
        case .tools:
            // Cachebox setting `ShowDraftsAsDefaultView` is off by default: the first tap opens the menu
            [.init(.show(.drafts), gesture: .up),
             .init(.solver, gesture: .left),
             .init(.solver2, gesture: .right),
             .init(.photo, gesture: .down),
             .init(.video),
             .init(.voiceNote)]
        case .misc:
            // Cachebox: Credits up, Settings left, Parking right, Day/Night, Help, Torch, About (default), Quit down.
            // "Mehr" stands for About and Credits; Day/Night follows the system and iOS apps do not quit themselves.
            [.init(.show(.more), isDefault: true, gesture: .up),
             .init(.settings, gesture: .left),
             .init(.parking, gesture: .right),
             .init(.help),
             .init(.torch)]
        }
    }

    var defaultAction: MainAction? {
        functions.first(where: \.isDefault)?.action
    }
}

/// A view above the main buttons (Cachebox: the `AbstractShowAction`s that show a view).
enum MainView: Hashable {
    case cacheList
    case description, waypoints, logs, spoiler
    case map, compass
    case drafts
    case more

    var button: MainButton {
        switch self {
        case .cacheList: .caches
        case .description, .waypoints, .logs, .spoiler: .cache
        case .map, .compass: .navigation
        case .drafts: .tools
        case .more: .misc
        }
    }

    var title: String {
        switch self {
        case .cacheList: "Cacheliste"
        case .description: "Beschreibung"
        case .waypoints: "Wegpunkte"
        case .logs: "Logs"
        case .spoiler: "Spoiler"
        case .map: "Karte"
        case .compass: "Kompass"
        case .drafts: "Entwürfe"
        case .more: "Mehr"
        }
    }

    var systemImage: String {
        switch self {
        case .cacheList: "list.bullet"
        case .description: "doc.text"
        case .waypoints: "mappin.and.ellipse"
        case .logs: "text.bubble"
        case .spoiler: "photo"
        case .map: "map"
        case .compass: "location.north.circle"
        case .drafts: "square.and.pencil"
        case .more: "ellipsis.circle"
        }
    }
}

/// What a main button can do (Cachebox `Action`/`AbstractAction`).
enum MainAction: Hashable {
    case show(MainView)
    case parking, trackables, share
    case hint, notes, browser
    case navigate, tracks, mapDownload
    case solver, solver2, photo, video, voiceNote
    case settings, help, torch

    var title: String {
        switch self {
        case .show(let view): view.title
        case .parking: "Parkplatz"
        case .trackables: "Trackables"
        case .share: "Teilen"
        case .hint: "Hinweis"
        case .notes: "Notizen"
        case .browser: "Im Browser öffnen"
        case .navigate: "Navigieren"
        case .tracks: "Tracks"
        case .mapDownload: "Karten und Themes"
        case .solver: "Solver"
        case .solver2: "Solver 2"
        case .photo: "Foto"
        case .video: "Video"
        case .voiceNote: "Sprachnotiz"
        case .settings: "Einstellungen"
        case .help: "Hilfe"
        case .torch: "Taschenlampe"
        }
    }

    var systemImage: String {
        switch self {
        case .show(let view): view.systemImage
        case .parking: "car"
        case .trackables: "tag"
        case .share: "square.and.arrow.up"
        case .hint: "lightbulb"
        case .notes: "note.text"
        case .browser: "safari"
        case .navigate: "arrow.triangle.turn.up.right.diamond"
        case .tracks: "point.topleft.down.to.point.bottomright.curvepath"
        case .mapDownload: "square.and.arrow.down"
        case .solver: "function"
        case .solver2: "function"
        case .photo: "camera"
        case .video: "video"
        case .voiceNote: "mic"
        case .settings: "gearshape"
        case .help: "questionmark.circle"
        case .torch: "flashlight.on.fill"
        }
    }
}

/// A function of a main button (Cachebox `CB_ActionButton`).
struct ButtonFunction {
    let action: MainAction
    var isDefault = false
    var gesture: SwipeDirection?

    init(_ action: MainAction, isDefault: Bool = false, gesture: SwipeDirection? = nil) {
        self.action = action
        self.isDefault = isDefault
        self.gesture = gesture
    }
}

// MARK: - Bar

/// The row of the five main buttons (Cachebox `CB_TabView.setButtonList`): spread evenly over the width on the
/// `button-list-back` background, each 88 × 76 like the sprites.
struct MainButtonBar: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var width: CGFloat = 390

    /// Space above and below the buttons.
    static let padding: CGFloat = 4

    /// Button size for the bar width: five buttons with at least 4 pt between them, at most 96 pt wide (iPad), and
    /// smaller in landscape on the iPhone, where height is short.
    private var buttonSize: CGSize {
        let maxWidth: CGFloat = verticalSizeClass == .compact ? 64 : 96
        let w = min(maxWidth, max(44, ((width - 6 * 4) / 5).rounded(.down)))
        return CGSize(width: w, height: (w * 76 / 88).rounded())
    }

    var body: some View {
        let size = buttonSize
        HStack(spacing: 0) {
            ForEach(MainButton.allCases) { button in
                Spacer(minLength: 0)
                MainButtonView(button: button, size: size)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Self.padding)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background {
            // the sprite is a light band fading into olive; below the buttons (home indicator) only olive
            VStack(spacing: 0) {
                Image("button-list-back")
                    .resizable()
                    .frame(height: size.height + 2 * Self.padding)
                Color(red: 156 / 255, green: 171 / 255, blue: 114 / 255)
            }
            .ignoresSafeArea(edges: [.bottom, .horizontal])
            .accessibilityHidden(true)
        }
        .environment(\.colorScheme, .light)   // Cachebox day skin, also in dark mode (like the map controls)
    }
}

/// Which list a button's popup shows.
enum MainMenuKind: Identifiable {
    /// Context menu of the shown view plus the functions of the button (Cachebox `compoundMenu`).
    case compound
    /// Only the functions of the button (Cachebox `getLongClickMenu`).
    case functions

    var id: Self { self }
}

/// One main button (Cachebox `GestureButton`).
struct MainButtonView: View {
    let button: MainButton
    let size: CGSize

    @Environment(AppState.self) private var state
    @State private var isTouching = false
    @State private var menu: MainMenuKind?
    @State private var longPress: Task<Void, Never>?
    @State private var didLongPress = false
    @State private var feedback = 0

    /// Movement after which a touch counts as a swipe and no longer as a tap.
    private static let swipeDistance: CGFloat = 14

    /// The view of this button is shown (Cachebox: `aktActionView.getView().isVisible()`, drawn as focused).
    private var isActive: Bool { state.view.button == button }

    var body: some View {
        Image(imageName)
            .resizable()
            .interpolation(.high)
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .bottomTrailing) {
                if isActive, let mark = contextMark {
                    // Cachebox `GestureButton.render`: width / 5 × height / 2.3, inset height / 20 and height / 30
                    Image(mark)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: size.width / 5, height: size.height / 2.3)
                        .padding(.trailing, size.height / 20)
                        .padding(.bottom, size.height / 30)
                }
            }
            .contentShape(Rectangle())
            .gesture(touch)
            .popover(item: $menu, arrowEdge: .bottom) { kind in
                MainMenuView(button: button, kind: kind)
                    .presentationCompactAdaptation(.popover)
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: feedback)
            .accessibilityElement()
            .accessibilityLabel(button.title)
            .accessibilityValue(isActive ? state.view.title : "")
            .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint(isActive ? "Öffnet das Menü" : "Zeigt \(nextViewTitle)")
            .accessibilityAction { tap() }
            .accessibilityActions {
                Button("Menü") { menu = .functions }
                ForEach(Array(button.functions.enumerated()), id: \.offset) { _, function in
                    if state.isEnabled(function.action) {
                        Button(function.action.title) { state.perform(function.action) }
                    }
                }
            }
    }

    private var imageName: String {
        let pressed = isActive || isTouching
        if button == .caches, state.lists.filter.isActive {
            return pressed ? "db-pressed-filter-active" : "db-filter-active"
        }
        return pressed ? button.imageName + "-pressed" : button.imageName
    }

    /// The dots for a view with a context menu; red while a filter is set (Cachebox `isFiltered` on buttons 1 and 3).
    private var contextMark: String? {
        guard state.hasContextMenu(state.view) else { return nil }
        let filtered = (button == .caches || button == .navigation) && state.lists.filter.isActive
        return filtered ? "MENUFILTERED" : "cmIcon"
    }

    private var nextViewTitle: String {
        if let last = state.lastViews[button] { return last.title }
        if case .show(let view) = button.defaultAction { return view.title }
        return "das Menü"
    }

    private var touch: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isTouching {
                    isTouching = true
                    didLongPress = false
                    longPress?.cancel()
                    longPress = Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        guard !Task.isCancelled else { return }
                        didLongPress = true
                        isTouching = false
                        feedback += 1
                        menu = .functions
                    }
                }
                if hypot(value.translation.width, value.translation.height) > Self.swipeDistance {
                    longPress?.cancel()
                }
            }
            .onEnded { value in
                longPress?.cancel()
                isTouching = false
                guard !didLongPress else { return }
                let dx = value.translation.width, dy = value.translation.height
                if hypot(dx, dy) <= Self.swipeDistance {
                    tap()
                } else if abs(dx) > abs(dy) {
                    swipe(dx > 0 ? .right : .left)
                } else {
                    swipe(dy < 0 ? .up : .down)
                }
            }
    }

    /// Cachebox `GestureButton.onClickListener`.
    private func tap() {
        if isActive {
            menu = .compound
        } else if let last = state.lastViews[button] {
            state.perform(.show(last))
        } else if let action = button.defaultAction {
            state.perform(action)
        } else {
            menu = .functions
        }
    }

    /// Cachebox `GestureButton.onTouchUp` after a drag.
    private func swipe(_ direction: SwipeDirection) {
        guard let function = button.functions.first(where: { $0.gesture == direction }),
              state.isEnabled(function.action) else { return }
        state.perform(function.action)
    }
}

// MARK: - Popup menu

/// The popup of a main button: the context menu of the shown view, a line, then the functions of the button with the
/// swipe direction behind each title (Cachebox `Menu` as `compoundMenu`). The entries are built anew on every
/// change, so checkmarks follow the state while it is open.
struct MainMenuView: View {
    let button: MainButton
    let kind: MainMenuKind

    @Environment(AppState.self) private var state

    var body: some View {
        CacheboxMenu(title: rootTitle, entries: rootEntries)
    }

    private var rootTitle: String {
        if kind == .compound, state.view.button == button, let menu = state.contextMenu(for: state.view) {
            return menu.title
        }
        return button.title
    }

    private var rootEntries: [MenuEntry] {
        let functions = state.functionEntries(for: button)
        guard kind == .compound, state.view.button == button, let menu = state.contextMenu(for: state.view) else {
            return functions
        }
        return menu.entries + [.divider(CacheboxMenu.functionsDivider)] + functions
    }
}
