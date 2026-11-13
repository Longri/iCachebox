import CacheboxCore
import SwiftUI
import UIKit

/// A waypoint to create or change in the `WaypointEditor`.
struct WaypointEditRequest: Identifiable {
    let id = UUID()
    var waypoint: Waypoint
    /// Shown at the top of the editor (Cachebox `tvCacheName`).
    let cacheName: String
    /// Opens the coordinate input right away (Cachebox `showCoordinateDialog`: new waypoints and "Ändern").
    let showsCoordinateDialog: Bool
    /// For a waypoint without coordinates: the own position, else the cache (Cachebox `iniCoordButton`).
    let fallbackCoordinate: Coordinate
}

/// Creates or changes a waypoint of the selected cache (Cachebox `EditWaypoint`): name of the cache, the coordinate
/// as a button that opens the coordinate input (`CoordinateEditor`), type with a "Start" box for stages of a multi,
/// title, description and clue, OK and Abbruch at the bottom. Description and clue grow with their text up to a
/// few lines (Cachebox: up to 1/2.3 of the height).
///
/// The coordinate input lies over the editor like a Cachebox activity over another, instead of a second sheet; it
/// opens at once for a new waypoint. A long press on the coordinate copies or pastes it (Cachebox `CopyPastePopUp`,
/// "Ausschneiden" is left out). Deviation: "Start" is kept only for a stage (Cachebox keeps a ticked box also after
/// the type changed).
struct WaypointEditor: View {
    let request: WaypointEditRequest
    let onSave: (Waypoint) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var waypoint: Waypoint
    @State private var coordinate: Coordinate
    @State private var editsCoordinate: Bool
    @State private var pasteFailure: String?
    @State private var choosesType = false

    /// The types offered, in the order of the Cachebox spinner.
    private static let types: [WaypointType] = [.reference, .stage, .question, .trailhead, .parking, .final]
    private static let controlHeight: CGFloat = 50

    init(request: WaypointEditRequest, onSave: @escaping (Waypoint) -> Void) {
        self.request = request
        self.onSave = onSave
        _waypoint = State(initialValue: request.waypoint)
        let own = request.waypoint.coordinate
        _coordinate = State(initialValue: own.flatMap { $0.isValid ? $0 : nil } ?? request.fallbackCoordinate)
        _editsCoordinate = State(initialValue: request.showsCoordinateDialog)
    }

    var body: some View {
        ZStack {
            form
            if choosesType {
                typeDialog.zIndex(1)
            }
            if editsCoordinate {
                CoordinateEditor(coordinate: coordinate) { new in
                    coordinate = new
                    withAnimation(.easeOut(duration: 0.2)) { editsCoordinate = false }
                } onCancel: {
                    withAnimation(.easeOut(duration: 0.2)) { editsCoordinate = false }
                }
                .transition(.move(edge: .bottom))
                .zIndex(2)
            }
        }
        .environment(\.colorScheme, .light)   // Cachebox day skin
        .interactiveDismissDisabled()           // typed text is not lost by a swipe; OK or Abbruch close it
        .alert("Einfügen nicht möglich", isPresented: Binding(get: { pasteFailure != nil },
                                                              set: { if !$0 { pasteFailure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("In der Zwischenablage steht keine Koordinate:\n\(pasteFailure ?? "")")
        }
    }

    // MARK: - Form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                label(request.cacheName)
                coordinateButton
                HStack {
                    label("Typ des Wegpunktes")
                    Spacer()
                    if waypoint.type == .stage {
                        label("Start").frame(width: Self.controlHeight * 1.5)
                    }
                }
                .padding(.top, 6)
                HStack(spacing: 6) {
                    typeButton
                    if waypoint.type == .stage {
                        CacheboxCheckBox(isOn: $waypoint.isStart)
                            .frame(width: Self.controlHeight * 1.5)
                            .accessibilityLabel("Startpunkt des Multis")
                    }
                }
                label("Titel").padding(.top, 6)
                CacheboxTextField(text: $waypoint.title, accessibilityLabel: "Titel")
                label("Beschreibung").padding(.top, 6)
                CacheboxTextField(text: $waypoint.comment, multiline: true, accessibilityLabel: "Beschreibung")
                label("Hinweis").padding(.top, 6)
                CacheboxTextField(text: $waypoint.clue, multiline: true, accessibilityLabel: "Hinweis")
            }
            .padding(8)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 6) {
                Button { save() } label: { Text("OK").frame(maxWidth: .infinity, maxHeight: .infinity) }
                Button { dismiss() } label: { Text("Abbruch").frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color(white: 0.08))
            .buttonStyle(CacheboxButtonStyle())
            .frame(height: 56)
            .padding(8)
            .background(Color.cacheboxActivity)
        }
        .background(Color.cacheboxActivity.ignoresSafeArea())
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color(white: 0.15))
            .lineLimit(2)
            .padding(.leading, 4)
    }

    /// Cachebox `CoordinateButton`: drawn pressed (yellow) and green while pressed, the other way round than a
    /// normal button.
    private var coordinateButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { editsCoordinate = true }
        } label: {
            Text(coordinate.formatted)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color(white: 0.08))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: Self.controlHeight)
        }
        .buttonStyle(CoordinateButtonStyle())
        .contextMenu {
            Button("Kopieren", systemImage: "doc.on.doc") { UIPasteboard.general.string = coordinate.formatted }
            Button("Einfügen", systemImage: "doc.on.clipboard") { paste() }
        }
        .accessibilityLabel("Koordinate")
        .accessibilityValue(coordinate.formatted)
        .accessibilityHint("Öffnet die Eingabe der Koordinate")
    }

    /// Cachebox `Spinner`: shows the type, a tap opens the list of types (`typeDialog`).
    private var typeButton: some View {
        Button {
            choosesType = true
        } label: {
            HStack(spacing: 10) {
                CacheboxIcon(name: waypoint.type.iconName, size: 34)
                Text(waypoint.type.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color(white: 0.08))
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color(white: 0.2))
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: Self.controlHeight)
        }
        .buttonStyle(CacheboxButtonStyle())
        .accessibilityLabel("Typ des Wegpunktes")
        .accessibilityValue(waypoint.type.title)
    }

    /// The list of the spinner (Cachebox `SelectionList` with icons) as a dialog over the editor, in the look of
    /// the Cachebox menus: title bar in the frame green, the types as boxes, the chosen one yellow.
    private var typeDialog: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { choosesType = false }
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                Text("Typ des Wegpunktes")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(Color.cacheboxFrame)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 3) {
                    ForEach(Array(Self.types.enumerated()), id: \.element) { index, type in
                        Button {
                            waypoint.type = type
                            choosesType = false
                        } label: {
                            HStack(spacing: 12) {
                                CacheboxIcon(name: type.iconName, size: 32)
                                Text(type.title)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 50)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(TypeRowStyle(index: index, isChosen: waypoint.type == type))
                        .accessibilityAddTraits(waypoint.type == type ? .isSelected : [])
                    }
                }
                .padding(6)
            }
            .background(Color.cacheboxActivity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.cacheboxFrame, lineWidth: 2)
            }
            .shadow(color: .black.opacity(0.3), radius: 10)
            .frame(maxWidth: 340)
            .padding(24)
        }
    }

    // MARK: - Actions

    private func paste() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            pasteFailure = ""
            return
        }
        if let pasted = Coordinate(parsing: text) {
            coordinate = pasted
        } else {
            pasteFailure = text
        }
    }

    /// Cachebox `bOK`: takes coordinate and texts; the waypoint becomes the user's (also an imported one).
    private func save() {
        var result = waypoint
        result.coordinate = coordinate
        result.isStart = result.type == .stage && result.isStart
        result.isUserCreated = true
        onSave(result)
        dismiss()
    }
}

/// A row of the type list on its Cachebox box, yellow when chosen or pressed.
private struct TypeRowStyle: ButtonStyle {
    let index: Int
    let isChosen: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background { CacheboxRowBox(index: index, isSelected: isChosen || configuration.isPressed) }
    }
}

/// `CacheboxButtonStyle` with the faces swapped (Cachebox `CoordinateButton.renderInit`).
private struct CoordinateButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        configuration.label
            .background { CacheboxButtonFace(isPressed: !configuration.isPressed) }
            .contentShape(shape)
            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
    }
}

/// Cachebox `CB_CheckBox`: a white box with a dark frame and a green check.
struct CacheboxCheckBox: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color(white: 0.25), lineWidth: 2)
                }
                .frame(width: 40, height: 40)
                .overlay {
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 26, weight: .heavy))
                            .foregroundStyle(Color.cachebox)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "ein" : "aus")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Cachebox `EditTextField`: a white field with a dark frame, green while it has the focus.
struct CacheboxTextField: View {
    @Binding var text: String
    var multiline = false
    var keyboard: UIKeyboardType = .default
    let accessibilityLabel: String
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if multiline {
                TextField("", text: $text, axis: .vertical).lineLimit(1...8)
            } else {
                TextField("", text: $text).keyboardType(keyboard)
            }
        }
        .focused($focused)
        .foregroundStyle(Color.black)
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(minHeight: 50)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(focused ? Color.cachebox : Color(white: 0.35), lineWidth: focused ? 2 : 1)
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Creating, changing and deleting waypoints

extension AppState {
    /// Cachebox `WayPointsView.addWP`: a new reference point at the selected cache, named with its new code; the
    /// coordinate input opens at once.
    func addWaypoint() {
        guard let cache = selectedCache else { return }
        startNewWaypoint(of: cache, at: cache.coordinate)
    }

    /// Cachebox `MapView.createWaypointAtCenter` (map menu "WP vom Kartenmittelpunkt"): at the centre of the map,
    /// without a map at the own position.
    func addWaypointAtMapCenter() {
        guard let cache = selectedCache, let center = map.visibleCenter ?? location.coordinate else { return }
        startNewWaypoint(of: cache, at: center)
    }

    private func startNewWaypoint(of cache: CacheSummary, at coordinate: Coordinate) {
        guard let waypoint = newWaypoint(of: cache, at: coordinate) else { return }
        waypointEditor = WaypointEditRequest(waypoint: waypoint, cacheName: cache.name, showsCoordinateDialog: true,
                                             fallbackCoordinate: coordinate)
    }

    /// A reference point at `coordinate` with the next free code (Cachebox `createFreeGcCode`), not saved yet.
    private func newWaypoint(of cache: CacheSummary, at coordinate: Coordinate, comment: String = "") -> Waypoint? {
        guard let database = lists.database(), let code = try? database.freeWaypointCode(cacheCode: cache.code) else {
            waypointError = "Für \(cache.code) konnte kein Wegpunkt angelegt werden."
            return nil
        }
        return Waypoint(code: code, cacheCode: cache.code, title: code, comment: comment, type: .reference,
                        coordinate: coordinate, isUserCreated: true)
    }

    /// Cachebox `WayPointsView.addProjection` (menu "Projektion"): projects from the chosen waypoint, else from the
    /// cache, and without coordinates from the own position.
    func startProjection() {
        guard let cache = selectedCache else { return }
        let from: Coordinate
        let name: String
        if let waypoint = selectedWaypoint, let coordinate = waypoint.coordinate, coordinate.isValid {
            from = coordinate
            name = waypoint.title.isEmpty ? waypoint.type.title : waypoint.title
        } else if cache.target.isValid {
            from = cache.target
            name = cache.name
        } else if let here = location.coordinate {
            from = here
            name = "Vom GPS"
        } else {
            waypointError = "Für die Projektion fehlt ein Startpunkt."
            return
        }
        projection = ProjectionRequest(from: from, fromName: name)
    }

    /// Takes the projected point as a new waypoint and makes it the target (Cachebox `addProjection`, which writes
    /// the waypoint straight into the database without the editor).
    func saveProjection(_ coordinate: Coordinate) {
        guard let cache = selectedCache,
              let waypoint = newWaypoint(of: cache, at: coordinate, comment: "Projektion") else { return }
        save(waypoint, asTarget: true)
    }

    /// Cachebox `WayPointsView.addMeasure` (menu "Vom GPS"): measures the own position and keeps the average.
    func startMeasuring() {
        guard selectedCache != nil else { return }
        location.start()
        measuring = MeasureRequest()
    }

    /// Takes the measured position as a new waypoint and makes it the target (Cachebox `addMeasure`).
    func saveMeasured(_ coordinate: Coordinate) {
        guard let cache = selectedCache,
              let waypoint = newWaypoint(of: cache, at: coordinate, comment: "Gemessen") else { return }
        save(waypoint, asTarget: true)
    }

    private func save(_ waypoint: Waypoint, asTarget: Bool) {
        guard saveWaypoint(waypoint), asTarget else { return }
        selectWaypoint(waypoint)
        show(.waypoints)
    }

    /// Cachebox "Anzeigen" (`editWP(false)`) and "Ändern" (`editWP(true)`, with the coordinate input).
    func editWaypoint(_ waypoint: Waypoint, showsCoordinateDialog: Bool) {
        guard let cache = selectedCache else { return }
        waypointEditor = WaypointEditRequest(waypoint: waypoint, cacheName: cache.name,
                                             showsCoordinateDialog: showsCoordinateDialog,
                                             fallbackCoordinate: location.coordinate ?? cache.coordinate)
    }

    @discardableResult
    func saveWaypoint(_ waypoint: Waypoint) -> Bool {
        do {
            guard let database = lists.database() else { throw CocoaError(.fileNoSuchFile) }
            try database.saveUserWaypoint(waypoint)
        } catch {
            waypointError = "Der Wegpunkt konnte nicht gespeichert werden: \(error.localizedDescription)"
            return false
        }
        // the target keeps its new coordinates right away, before the details are read again
        if selectedWaypoint?.code == waypoint.code { selectWaypoint(waypoint) }
        waypointsChanged()
        return true
    }

    /// Cachebox `deleteWP`, only for the user's waypoints; the target falls back to the cache.
    func deleteWaypoint(_ waypoint: Waypoint) {
        try? lists.database()?.deleteWaypoint(code: waypoint.code, cacheCode: waypoint.cacheCode)
        if selectedWaypoint?.code == waypoint.code { selectWaypoint(nil) }
        waypointsChanged()
    }

    /// Reloads what shows waypoints: details, map, and the list (number of waypoints, a final as target).
    private func waypointsChanged() {
        waypointRevision += 1
        Task {
            await lists.loadCaches()
            refreshSelection()
        }
    }

    /// Context menu of the waypoint view (Cachebox `WayPointsView.getContextMenu`), followed by the cache menu.
    /// Cachebox offers "Anzeigen", "Ändern" and "Löschen" for the chosen waypoint; here they are in the long-press
    /// menu of each row as well, so that a waypoint can be changed without choosing it as the target first.
    func waypointEntries(_ cache: CacheSummary) -> [MenuEntry] {
        var entries: [MenuEntry] = []
        if let waypoint = selectedWaypoint {
            entries += [
                MenuEntry("Anzeigen", systemImage: "eye") { [weak self] in
                    self?.editWaypoint(waypoint, showsCoordinateDialog: false)
                },
                MenuEntry("Ändern", systemImage: "pencil") { [weak self] in
                    self?.editWaypoint(waypoint, showsCoordinateDialog: true)
                },
            ]
            if waypoint.isUserCreated {
                entries.append(MenuEntry("Löschen", systemImage: "trash", role: .destructive) { [weak self] in
                    self?.waypointToDelete = waypoint
                })
            }
            entries.append(MenuEntry("Ziel: der Cache", systemImage: "scope", runsImmediately: true) {
                [weak self] in self?.selectWaypoint(nil)
            })
            entries.append(.divider("add"))
        }
        entries += [
            MenuEntry("Wegpunkt hinzufügen", systemImage: "plus.circle") { [weak self] in self?.addWaypoint() },
            MenuEntry("Projektion", systemImage: "arrow.up.right.circle", level: .advanced) { [weak self] in
                self?.startProjection()
            },
            MenuEntry("Vom GPS", systemImage: "location.circle", level: .advanced) { [weak self] in
                self?.startMeasuring()
            },
            .divider("cache"),
        ]
        return entries + cacheEntries(cache)
    }
}
