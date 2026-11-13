import CacheboxCore
import SwiftUI

// The slider at the top of the screen, as in Cachebox (`Slider`, `QuickButtonList`, `QuickButtonItem`):
//
// - The bar (Cachebox `mSlideBox`) shows the selected cache over every view: the colors of its last five logs, type
//   icon, name, size/difficulty/terrain as icons and, with a position, distance and direction. Tapping it opens the
//   details of the cache.
// - Pulling the bar down shows the quick buttons above it (Cachebox snaps the `QuickButtonList` in at half its
//   height); pulling further shows the cache info below them (Cachebox `WaypointViewItem` in
//   `CacheInfo.VIEW_MODE_SLIDER`: owner, hidden date, coordinates, code, last found, attributes). Pushing it up hides
//   them again. Whether the quick buttons are shown is kept (Cachebox `quickButtonLastShow`).
//
// Cachebox lets the cache info cover the whole view and snaps there or back to the top; here it opens as far as its
// content needs, so the view below stays visible.

/// A quick button (Cachebox `Action` in the `QuickButtonList`). The list is the Cachebox default
/// (`quickButtonList = "1,15,14,19,12,23,2,13"`); choosing the buttons (Cachebox settings) is not built yet.
enum QuickButton: CaseIterable, Identifiable {
    case waypoints, hint, spoiler, quickDraft, autoResort, notes, logs, solver

    var id: Self { self }

    /// Sprite of the Cachebox day skin (`Assets.xcassets/CacheboxQuick`, `Action.action.getIcon()`).
    var imageName: String {
        switch self {
        case .waypoints: "waypointListIcon"
        case .hint: "hintIcon"
        case .spoiler: "imagesIcon"
        case .quickDraft: "FieldNote"
        case .autoResort: "autoSortOffIcon"
        case .notes: "userdata"
        case .logs: "listIcon"
        case .solver: "solverIcon"
        }
    }

    var title: String {
        switch self {
        case .waypoints: "Wegpunkte"
        case .hint: "Hinweis"
        case .spoiler: "Spoiler"
        case .quickDraft: "Schnell-Entwurf"
        case .autoResort: "Automatisch sortieren"
        case .notes: "Notizen"
        case .logs: "Logs"
        case .solver: "Solver"
        }
    }

    /// What the button does; `nil` while it is not built (Quick-Draft and auto-resort need drafts and a resorting
    /// list, see the TODOs in `MainActions.swift`).
    var action: MainAction? {
        switch self {
        case .waypoints: .show(.waypoints)
        case .hint: .hint
        case .spoiler: .show(.spoiler)
        case .quickDraft, .autoResort: nil
        case .notes: .notes
        case .logs: .show(.logs)
        case .solver: .solver
        }
    }
}

/// Where the slider bar rests.
enum SliderStop: Int, CaseIterable {
    case closed, quickButtons, info

    private static let key = "slider.quickButtons"

    /// The quick buttons as they were (Cachebox `quickButtonLastShow`); the cache info is always closed at launch.
    static var saved: SliderStop { UserDefaults.standard.bool(forKey: key) ? .quickButtons : .closed }

    func save() { UserDefaults.standard.set(self != .closed, forKey: Self.key) }
}

/// The views above the main buttons with the slider on top.
struct CacheboxSlider<Content: View>: View {
    @ViewBuilder var content: Content

    @Environment(AppState.self) private var state
    @State private var stop = SliderStop.saved
    /// Movement of the finger while the bar is dragged.
    @State private var drag: CGFloat = 0
    @State private var width: CGFloat = 390
    /// Height the cache info needs, and the height of the area below the bar (the cache info leaves some of it).
    @State private var infoHeight: CGFloat = 0
    @State private var areaHeight: CGFloat = 600

    private var quickHeight: CGFloat { QuickButtonRow.height(width: width) }

    /// Under the status bar: the skin green, black in dark mode, where the status bar is white.
    private static var statusBarColor: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? .black : UIColor(Color.cacheboxBackground)
        })
    }

    /// Shown height of the cache info when open: as much as it needs, but some of the view stays visible.
    private var openInfoHeight: CGFloat {
        guard state.selectedCache != nil else { return 0 }
        return max(0, min(infoHeight, areaHeight - 80))
    }

    private func position(_ stop: SliderStop) -> CGFloat {
        switch stop {
        case .closed: 0
        case .quickButtons: quickHeight
        case .info: quickHeight + openInfoHeight
        }
    }

    /// How far the bar is pulled down from the top.
    private var pulled: CGFloat {
        min(max(0, position(stop) + drag), position(.info))
    }

    var body: some View {
        // the width comes from a geometry reader, which takes the offered size whatever its content: measured on
        // the stack, the quick buttons sized for the last width kept it wide after turning to portrait
        GeometryReader { geometry in
            stack
                .onChange(of: geometry.size.width, initial: true) { _, newWidth in width = newWidth }
        }
        .background { Self.statusBarColor.ignoresSafeArea(edges: .top) }
        .onChange(of: state.selectedCache == nil) {
            if state.selectedCache == nil, stop == .info { stop = .quickButtons }
        }
    }

    private var stack: some View {
        let pulled = pulled
        let quick = min(pulled, quickHeight)
        let info = max(0, pulled - quickHeight)
        return VStack(spacing: 0) {
            // clipping does not limit hit testing: the hidden part must not catch taps meant for other views
            QuickButtonRow(width: width)
                .frame(height: quick, alignment: .bottom)
                .clipShape(VerticalClip())
                .allowsHitTesting(quick >= quickHeight - 1)
                .accessibilityHidden(quick < quickHeight / 2)
                .environment(\.colorScheme, .light)   // Cachebox day skin, like the main buttons
            SliderBar(isOpen: stop != .closed) { toggle in
                withAnimation(.spring(duration: 0.3)) { move(to: toggle) }
            }
            .gesture(dragGesture)
            .offset(y: info)
            .overlay(alignment: .top) {
                // the cache info hangs above the bar and comes down with it over the view
                SliderCacheInfo(width: width)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { infoHeight = $0 }
                    .scrollable(if: infoHeight > openInfoHeight + 1, height: openInfoHeight)
                    .frame(height: info, alignment: .bottom)
                    .clipShape(VerticalClip())
                    .allowsHitTesting(info > 0 && info >= openInfoHeight - 1)
                    .accessibilityHidden(info < 1)
            }
            .environment(\.colorScheme, .light)
            .zIndex(1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { areaHeight = $0 }
        }
    }

    /// Cachebox `Slider.onTouchDragged`/`ActionUp`: the bar follows the finger and then snaps to the nearest stop
    /// in the direction of a swipe.
    private var dragGesture: some Gesture {
        // global: the bar moves under the finger
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { drag = $0.translation.height }
            .onEnded { value in
                let end = position(stop) + value.predictedEndTranslation.height
                let stops = SliderStop.allCases.filter { $0 != .info || openInfoHeight > 0 }
                let next = stops.min { abs(position($0) - end) < abs(position($1) - end) } ?? stop
                withAnimation(.spring(duration: 0.3)) { move(to: next) }
            }
    }

    private func move(to next: SliderStop) {
        stop = next
        drag = 0
        next.save()
    }
}

/// Clips only at the top and bottom, so that backgrounds reach into the side safe areas in landscape.
private struct VerticalClip: Shape {
    func path(in rect: CGRect) -> Path { Path(rect.insetBy(dx: -1000, dy: 0)) }
}

private extension View {
    /// A scroll view of `height` around the cache info when it does not fit, else the info as it is.
    @ViewBuilder
    func scrollable(if needed: Bool, height: CGFloat) -> some View {
        if needed {
            ScrollView { self }
                .scrollIndicators(.visible)
                .frame(height: height)
        } else {
            self
        }
    }
}

// MARK: - Quick buttons

/// Cachebox `QuickButtonList`: a row of square buttons on the `button-list-back` band; they fill the width up to a
/// size and scroll sideways on narrow screens.
private struct QuickButtonRow: View {
    let width: CGFloat
    @Environment(AppState.self) private var state

    private static let spacing: CGFloat = 4
    private static let padding: CGFloat = 4

    /// Button size for the width: all buttons side by side, 40 to 54 pt.
    static func buttonSize(width: CGFloat) -> CGFloat {
        let count = CGFloat(QuickButton.allCases.count)
        let fitting = ((width - 2 * padding - (count - 1) * spacing) / count).rounded(.down)
        return min(54, max(40, fitting))
    }

    static func height(width: CGFloat) -> CGFloat { buttonSize(width: width) + 2 * padding }

    /// The buttons need more than the width (only below about 360 pt, e.g. iPad split view).
    private static func scrolls(width: CGFloat) -> Bool {
        let count = CGFloat(QuickButton.allCases.count)
        return count * buttonSize(width: width) + (count - 1) * spacing + 2 * padding > width
    }

    var body: some View {
        // a scroll view only where needed: it holds touches back a moment before the buttons get them
        if Self.scrolls(width: width) {
            ScrollView(.horizontal) { buttons }
                .scrollIndicators(.hidden)
                .row(width: width)
        } else {
            buttons
                .frame(width: width)
                .row(width: width)
        }
    }

    private var buttons: some View {
        let size = Self.buttonSize(width: width)
        return HStack(spacing: Self.spacing) {
            ForEach(QuickButton.allCases) { button in
                let enabled = button.action.map(state.isEnabled) ?? false
                Button {
                    if let action = button.action { state.perform(action) }
                } label: {
                    Image(button.imageName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(size * 0.15)   // Cachebox: the icon at 70 % of the button
                        .opacity(enabled ? 1 : 0.25)
                        .frame(width: size, height: size)
                }
                .buttonStyle(CacheboxButtonStyle(cornerRadius: 8))
                .disabled(!enabled)
                .accessibilityLabel(button.title)
            }
        }
        .padding(Self.padding)
    }
}

private extension View {
    /// Height and background of the quick button row.
    func row(width: CGFloat) -> some View {
        self
            .frame(height: QuickButtonRow.height(width: width))
            .background {
                Image("button-list-back")
                    .resizable()
                    .ignoresSafeArea(edges: .horizontal)
                    .accessibilityHidden(true)
            }
    }
}

// MARK: - Bar

/// Cachebox `mSlideBox`: the colors of the last five logs, type icon and a line with the cache. Cachebox writes
/// "2/2.5S name"; here the name is on its own line and size, difficulty and terrain are the icons of the cache list.
private struct SliderBar: View {
    /// The quick buttons or the cache info are shown.
    let isOpen: Bool
    /// Opens (quick buttons) or closes the slider, for VoiceOver.
    let onToggle: (SliderStop) -> Void
    @Environment(AppState.self) private var state

    static let height: CGFloat = 50

    var body: some View {
        HStack(spacing: 8) {
            LastLogs(logs: lastLogs)
            if let cache = state.selectedCache {
                CacheTypeIcon(type: cache.type, isFound: cache.isFound, isFavorite: cache.isFavorite,
                              isArchived: cache.isArchived, isUnavailable: !cache.isAvailable,
                              isSolved: cache.isSolved, size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(cache.name)
                        .font(.subheadline.weight(.bold))
                        .strikethrough(cache.isArchived)
                        .foregroundStyle(cache.isArchived || !cache.isAvailable ? Color(red: 0.6, green: 0, blue: 0)
                                                                               : Color(white: 0.05))
                        .lineLimit(1)
                    SizeDifficultyTerrain(cache: cache, isCompact: true, showsExtras: false)
                        .foregroundStyle(Color(white: 0.05))
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                if let here = state.location.coordinate, let target = state.target {
                    // arrow and distance go to the navigation target: the chosen waypoint, else the cache
                    let bearing = here.bearing(to: target.coordinate) - (state.location.heading ?? 0)
                    VStack(spacing: 1) {
                        Image(systemName: "location.north.fill")
                            .rotationEffect(.degrees(bearing))
                        Text(Format.distance(here.distance(to: target.coordinate)))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color(white: 0.05))
                    .fixedSize()
                }
            } else {
                Text("Kein Cache gewählt")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(white: 0.2))
                Spacer(minLength: 0)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .frame(height: Self.height)
        .background { CacheboxButtonFace(cornerRadius: 8) }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        // into the side safe areas in landscape, but not under the status bar
        .background(Color.cacheboxBackground, ignoresSafeAreaEdges: .horizontal)
        .contentShape(Rectangle())
        .onTapGesture {
            guard state.selectedCache != nil else { return }
            if isOpen { onToggle(.quickButtons) }   // the details must not open under the cache info
            state.showCacheDetails()
        }
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contextMenu {
            if let cache = state.selectedCache {
                Button("Details", systemImage: "doc.text") { state.showCacheDetails() }
                Button("Auf der Karte", systemImage: "map") { state.select(cache, show: .map) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(state.selectedCache == nil ? "" : "Öffnet die Details")
        .accessibilityAddTraits(state.selectedCache == nil ? [] : .isButton)
        .accessibilityAction(named: isOpen ? "Zusatzknöpfe ausblenden" : "Zusatzknöpfe zeigen") {
            onToggle(isOpen ? .closed : .quickButtons)
        }
        .accessibilityAction(named: "Cache-Infos zeigen") { onToggle(.info) }
    }

    /// Cachebox `last5Logs`: the newest five logs.
    private var lastLogs: [LogType] {
        guard let details = state.selectedDetails else { return [] }
        return details.logs.prefix(5).map(\.type)
    }

    private var accessibilityText: String {
        guard let cache = state.selectedCache else { return "Kein Cache gewählt" }
        var text = "Gewählter Cache: \(cache.name), \(cache.code), Größe \(cache.container.title), "
            + "Schwierigkeit \(CacheSummary.rating(cache.difficulty)), Gelände \(CacheSummary.rating(cache.terrain))"
        if let here = state.location.coordinate, let target = state.target {
            text += ", Entfernung \(Format.distance(here.distance(to: target.coordinate)))"
            if target.isWaypoint { text += " zum Wegpunkt \(target.name)" }
        }
        return text
    }
}

/// Cachebox `last5Logs` in the slider: one narrow field per log, green for found and owner maintenance, red for not
/// found, yellow for needs maintenance or archiving, empty for the other logs and where there is none.
private struct LastLogs: View {
    let logs: [LogType]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
                shape.fill(index < logs.count ? Self.color(logs[index]) : .clear)
                    .overlay { shape.strokeBorder(Color.black.opacity(0.3), lineWidth: 0.5) }
                    .frame(width: 7)
            }
        }
        .padding(.vertical, 8)
        .accessibilityHidden(true)
    }

    /// The sprites `green`, `red` and `yellow` of the skin.
    private static func color(_ type: LogType) -> Color {
        switch type {
        case .found, .ownerMaintenance: Color(red: 0, green: 1, blue: 33 / 255)
        case .didNotFind: Color(red: 1, green: 0, blue: 0)
        case .needsMaintenance, .needsArchived: Color(red: 1, green: 216 / 255, blue: 0)
        default: .clear
        }
    }
}

// MARK: - Cache info

/// Cachebox `WaypointViewItem` with `CacheInfo.VIEW_MODE_SLIDER`, drawn selected (yellow): icon, name, owner and
/// hidden date, coordinates, code, last found, size/difficulty/terrain and the attributes, twelve per line.
private struct SliderCacheInfo: View {
    let width: CGFloat
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            if let cache = state.selectedCache {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        CacheTypeIcon(type: cache.type, isFound: cache.isFound, isFavorite: cache.isFavorite,
                                      isArchived: cache.isArchived, isUnavailable: !cache.isAvailable,
                                      isSolved: cache.isSolved, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cache.name)
                                .font(.headline)
                                .strikethrough(cache.isArchived)
                                .foregroundStyle(cache.isArchived || !cache.isAvailable ? Color.red : Color.black)
                                .fixedSize(horizontal: false, vertical: true)
                            Group {
                                if let ownerLine = ownerLine(cache) { Text(ownerLine) }
                                Text(MapFormat.coordinate(cache.target))
                                    .monospacedDigit()
                                    .accessibilityLabel(cache.target.formatted)
                                Text(cache.code)
                                // the chosen waypoint, which the compass and the arrows point to
                                if let target = state.target, target.isWaypoint {
                                    Text("Ziel: \(target.name) (\(target.code))")
                                }
                                if let date = lastFound {
                                    Text("Zuletzt gefunden: "
                                         + date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year(.twoDigits)))
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(Color(white: 0.15))
                        }
                        Spacer(minLength: 0)
                    }
                    SizeDifficultyTerrain(cache: cache)
                    if let attributes = state.selectedDetails?.cache.attributes, !attributes.isEmpty {
                        // Cachebox `AttributesPerLine = 12`
                        CacheAttributeIcons(attributes: attributes, size: max(22, (width - 32) / 12 - 4))
                    }
                }
                .foregroundStyle(Color.black)
                .padding(10)
                .background { CacheboxRowBox(index: 0, isSelected: true) }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cacheboxBackground)
    }

    /// Cachebox `SHOW_OWNER` + `SHOW_HIDDEN_DATE`: "by owner, date".
    private func ownerLine(_ cache: CacheSummary) -> String? {
        let date = cache.hidden?.formatted(date: .numeric, time: .omitted)
        switch (cache.owner.isEmpty ? nil : cache.owner, date) {
        case let (owner?, date?): return "von \(owner), \(date)"
        case let (owner?, nil): return "von \(owner)"
        case let (nil, date?): return date
        case (nil, nil): return nil
        }
    }

    /// Cachebox `CacheInfo.getLastFoundLogDate`: date of the latest "found" log.
    private var lastFound: Date? {
        state.selectedDetails?.logs.filter { $0.type == .found }.compactMap(\.date).max()
    }
}
