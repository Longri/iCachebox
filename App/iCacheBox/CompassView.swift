import CacheboxCore
import SwiftUI

// Main button 3 › Kompass, like the Cachebox `CompassView` without its small map (`CompassShowMap` off): on top a
// box with the navigation target (symbol and name, coordinates and GC code, the description of a chosen waypoint,
// own position and height, direction to the target, size/difficulty/terrain, last find, attributes), below it the
// compass. The target is the chosen waypoint of the selected cache, else the cache itself (`AppState.target`), and
// symbol, name and coordinates follow it like Cachebox's `setCache` does. The compass rose turns with the heading so
// that N points north; the arrow points to the target, red while the device compass gives the heading, cyan while it
// comes from GPS. Above the compass the distance to the target and the accuracy of the own position. Sun and moon
// stand at the edge of the compass in their direction while they are above the horizon (off by default, as in
// Cachebox).
//
// Not taken over: the small map and the satellite bar chart (iOS does not report satellites).

/// What the compass view shows (Cachebox settings `CompassShow…`, defaults as there), kept across launches.
@MainActor
@Observable
final class CompassOptions {
    /// In the order of the Cachebox menu `CompassViewElementsMenuTitle`.
    enum Element: String, CaseIterable, Identifiable {
        case name, icon, attributes, code, coordinates, waypointDescription, position, sunMoon, targetDirection,
             sizeDifficultyTerrain, lastFound

        var id: Self { self }

        var title: String {
            switch self {
            case .name: "Name"
            case .icon: "Symbol"
            case .attributes: "Attribute"
            case .code: "GC-Code"
            case .coordinates: "Koordinaten"
            // Cachebox `CompassShowWpDesc`: description and clue of the chosen waypoint
            case .waypointDescription: "Wegpunktbeschreibung"
            // Cachebox `CompassShowSatInfos`: own position, height and the satellites, which iOS does not report
            case .position: "Eigene Position und Höhe"
            case .sunMoon: "Sonne und Mond"
            case .targetDirection: "Richtung zum Ziel"
            case .sizeDifficultyTerrain: "Größe, Schwierigkeit, Gelände"
            case .lastFound: "Zuletzt gefunden"
            }
        }

        /// Cachebox: everything on except sun/moon and the direction to the target.
        var defaultValue: Bool { self != .sunMoon && self != .targetDirection }

        fileprivate var key: String { "compass.show." + rawValue }
    }

    private var values: [Element: Bool]

    init() {
        let defaults = UserDefaults.standard
        values = Dictionary(uniqueKeysWithValues: Element.allCases.map { element in
            (element, defaults.object(forKey: element.key) as? Bool ?? element.defaultValue)
        })
    }

    subscript(element: Element) -> Bool {
        get { values[element] ?? element.defaultValue }
        set {
            values[element] = newValue
            UserDefaults.standard.set(newValue, forKey: element.key)
        }
    }

    /// Something for the box above the compass (sun and moon are drawn at the compass).
    var showsInfo: Bool { Element.allCases.contains { $0 != .sunMoon && self[$0] } }
}

/// Sizes of the compass view (Cachebox `GL_UISizes.margin`, the `activity-back` boxes).
private enum CompassLayout {
    static let margin: CGFloat = 8
    /// Inner padding of a box.
    static let boxPadding: CGFloat = 10
    /// Gap around a box (the transparent rim of the `activity-back` sprite).
    static let boxInset: CGFloat = 2

    /// Cachebox `attHeight`: symbol, attribute icons and sun/moon, a ninth of the view width.
    static func iconSize(width: CGFloat) -> CGFloat {
        max(24, width / 9 - margin)
    }
}

/// Cachebox `activity-back`: light green box with a dark rim.
private struct ActivityBox: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        shape.fill(Color.cacheboxActivity)
            .overlay { shape.strokeBorder(Color.black.opacity(0.55), lineWidth: 1.2) }
            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
            .padding(CompassLayout.boxInset)
    }
}

struct CompassView: View {
    @Environment(AppState.self) private var state
    /// Height of the content of the upper box.
    @State private var infoHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            // Cachebox `createControls`: the compass keeps at least 70 % of the width as height, the box above gets
            // what its content needs and scrolls if there is less room
            let showsInfo = state.compass.showsInfo
            if size.width > size.height * 1.25 {
                // landscape (Cachebox runs in portrait on phones): the box beside the compass, over the full height
                let dialWidth = showsInfo ? min(size.height * 1.05, size.width * 0.55) : size.width
                HStack(spacing: 0) {
                    if showsInfo {
                        infoBox(width: min(size.width - dialWidth, 440))
                            .frame(maxHeight: .infinity, alignment: .top)
                            .background { ActivityBox() }
                    }
                    CompassDial(width: dialWidth)
                        .frame(width: dialWidth)
                        .frame(maxHeight: .infinity)
                        .background { ActivityBox() }
                }
            } else {
                let infoBoxHeight = showsInfo
                    ? max(0, min(infoHeight + 2 * CompassLayout.boxInset, size.height - size.width * 0.7)) : 0
                VStack(spacing: 0) {
                    if showsInfo {
                        infoBox(width: size.width)
                            .frame(height: infoBoxHeight)
                            .background { ActivityBox() }
                    }
                    CompassDial(width: size.width)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background { ActivityBox() }
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .background(Color.cacheboxBackground)
        .foregroundStyle(Color.black)
        .environment(\.colorScheme, .light)   // Cachebox day skin, also in dark mode (like the map controls)
        .onAppear { state.location.start() }
    }

    /// The scrolling content of the upper box; `width` sizes the icons (Cachebox: a ninth of the view width).
    private func infoBox(width: CGFloat) -> some View {
        ScrollView {
            CompassInfo(width: width)
                .padding(CompassLayout.boxPadding)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { infoHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .padding(CompassLayout.boxInset)
    }
}

// MARK: - Box with the cache

/// Cachebox `CompassView.topContentBox`.
private struct CompassInfo: View {
    let width: CGFloat
    @Environment(AppState.self) private var state

    var body: some View {
        let options = state.compass
        let iconSize = CompassLayout.iconSize(width: width)
        if let cache = state.selectedCache, let target = state.target {
            VStack(alignment: .leading, spacing: 7) {
                if options[.icon] || options[.name] {
                    // Cachebox `setCache`: with a chosen waypoint its icon and title stand here instead of the cache
                    HStack(spacing: 10) {
                        if options[.icon] {
                            CacheboxIcon(name: target.iconName, size: iconSize)
                        }
                        if options[.name] {
                            Text(target.name)
                                .font(.headline)
                                .strikethrough(cache.isArchived && !target.isWaypoint)
                                .lineLimit(2)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                if target.isWaypoint, options[.name] {
                    Text("Wegpunkt von \(cache.name)")
                        .font(.footnote)
                        .lineLimit(1)
                }
                if options[.coordinates] || options[.code] {
                    // Cachebox: coordinates with a fixed width, the code behind them
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) { coordinatesAndCode(target, cache, options) }
                        VStack(alignment: .leading, spacing: 4) { coordinatesAndCode(target, cache, options) }
                    }
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                }
                if options[.waypointDescription], target.isWaypoint {
                    // Cachebox `lblDesc`: the description of the chosen waypoint; the clue is in it here, too
                    VStack(alignment: .leading, spacing: 2) {
                        if !target.comment.isEmpty { Text(target.comment) }
                        if !target.clue.isEmpty { Text("Hinweis: \(target.clue)") }
                    }
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if options[.position] {
                    OwnPositionInfo(location: state.location)
                }
                if options[.targetDirection] {
                    TargetDirectionText(location: state.location, target: target.coordinate)
                }
                if options[.sizeDifficultyTerrain] {
                    SizeDifficultyTerrain(cache: cache)
                }
                if options[.lastFound], let date = lastFound {
                    Text("Zuletzt gefunden: \(date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year(.twoDigits)))")
                        .font(.footnote)
                }
                if options[.attributes], let attributes = state.selectedDetails?.cache.attributes, !attributes.isEmpty {
                    CacheAttributeIcons(attributes: attributes, size: iconSize)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 10) {
                Text("Kein Cache gewählt")
                    .font(.headline)
                Button("Zur Cacheliste") { state.show(.cacheList) }
                    .buttonStyle(.bordered)
                    .tint(Color(red: 0.24, green: 0.48, blue: 0.13))
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func coordinatesAndCode(_ target: NavigationTarget, _ cache: CacheSummary,
                                    _ options: CompassOptions) -> some View {
        if options[.coordinates] {
            Text(MapFormat.coordinate(target.coordinate))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityLabel("Ziel \(target.coordinate.formatted)")
        }
        if options[.code] {
            // Cachebox shows the GC code of the cache also for a waypoint; its own code stands in front of it
            Text(target.isWaypoint ? "\(target.code) · \(cache.code)" : cache.code)
                .lineLimit(1)
        }
    }

    /// Cachebox `CacheInfo.getLastFoundLogDate`: date of the latest "found" log.
    private var lastFound: Date? {
        state.selectedDetails?.logs.filter { $0.type == .found }.compactMap(\.date).max()
    }
}

/// Own position and height (Cachebox `lblOwnCoordinate`, `lblAlt`). Its own view, so that only it follows the fixes.
private struct OwnPositionInfo: View {
    let location: LocationModel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(location.coordinate.map(MapFormat.coordinate) ?? "Keine Position")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("Höhe: " + (location.altitude.map { "\(Int($0.rounded())) m" } ?? "---"))
        }
        .font(.subheadline.weight(.semibold))
        .monospacedDigit()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var text = location.coordinate.map { "Eigene Position \($0.formatted)" } ?? "Keine eigene Position"
        if let altitude = location.altitude { text += ", Höhe \(Int(altitude.rounded())) Meter" }
        return text
    }
}

/// Cachebox `lblBearing`: "Richtung zum Ziel : 123°".
private struct TargetDirectionText: View {
    let location: LocationModel
    let target: Coordinate

    var body: some View {
        let bearing = location.coordinate.map { Int($0.bearing(to: target).rounded()) % 360 }
        Text("Richtung zum Ziel: " + (bearing.map { "\($0)°" } ?? "---"))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
    }
}

// MARK: - Compass

/// Cachebox `CompassView.leftBox` without map: distance and accuracy at the top, the compass at the bottom.
private struct CompassDial: View {
    /// Width of the whole view (Cachebox sizes sun and moon by it).
    let width: CGFloat
    @Environment(AppState.self) private var state
    @State private var panelHeight: CGFloat = 50

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let margin = CompassLayout.margin
            let sunMoon = state.compass[.sunMoon]
            let iconSize = sunMoon ? CompassLayout.iconSize(width: width) : 0
            // Cachebox `Layout`: (min(height, width) − 2 margins) × 0.95, smaller by the sun with sun and moon,
            // standing on the bottom of the box. Unlike Cachebox no larger than the room below the distance, which
            // it would otherwise cover when the box is low (landscape, many lines in the box above).
            let room = size.height - panelHeight - 3 * margin - iconSize
            let dialSize = max(0, min((min(size.height, size.width) - 2 * margin) * 0.95 - iconSize, room))
            let center = CGPoint(x: size.width / 2, y: size.height - margin - iconSize / 2 - dialSize / 2)
            ZStack(alignment: .top) {
                DialFace(location: state.location, target: state.target?.coordinate, size: dialSize)
                    .position(center)
                if sunMoon {
                    SunAndMoon(location: state.location, center: center, dialSize: dialSize, iconSize: iconSize)
                }
                DistancePanel(location: state.location, target: state.target?.coordinate)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
                    .padding(.horizontal, margin)
                    .padding(.top, margin)
            }
        }
    }
}

/// Frame, rose and arrow (Cachebox `frame`, `scale`, `arrow`: `compass-frame`, `compass-scale`, `arrow-Compass` or
/// `arrow-GPS` at 0.8 × 0.7 of the frame).
private struct DialFace: View {
    let location: LocationModel
    let target: Coordinate?
    let size: CGFloat

    var body: some View {
        let heading = location.heading ?? 0
        ZStack {
            Image("CompassViewFrame").resizable().interpolation(.high)
            Image("CompassViewScale").resizable().interpolation(.high)
                .rotationEffect(.degrees(-heading))
            if let here = location.coordinate, let target {
                CacheboxPositionArrow(compass: location.isCompassHeading, size: (size * 0.56).rounded())
                    .rotationEffect(.degrees(here.bearing(to: target) - heading))
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kompass")
        .accessibilityValue(accessibilityText)
    }

    private var accessibilityText: String {
        guard let here = location.coordinate, let target else {
            return location.heading.map { "Blickrichtung \(Int($0.rounded())) Grad" } ?? "Keine Richtung"
        }
        let relative = (here.bearing(to: target) - (location.heading ?? 0) + 360).truncatingRemainder(dividingBy: 360)
        let hour = Int((relative / 30).rounded()) % 12
        return "Ziel auf \(hour == 0 ? 12 : hour) Uhr, \(Int(here.bearing(to: target).rounded())) Grad"
    }
}

/// Cachebox `distanceBack` with `lblDistance` (compass font) and `lblAccuracy`.
private struct DistancePanel: View {
    let location: LocationModel
    let target: Coordinate?
    @ScaledMetric(relativeTo: .title) private var fontSize: CGFloat = 28

    var body: some View {
        let distance = location.coordinate.flatMap { here in target.map { here.distance(to: $0) } }
        HStack(alignment: .firstTextBaseline) {
            Text(distance.map(MapFormat.distance) ?? "---")
                .font(.system(size: fontSize, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 8)
            if let accuracy = location.accuracy, location.coordinate != nil {
                Text("+/- " + MapFormat.distance(accuracy))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .monospacedDigit()
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: fontSize * 1.8)
        .background { InfoPanelBackground() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(distance))
    }

    private func accessibilityText(_ distance: Double?) -> String {
        var text = distance.map { "Entfernung \(MapFormat.distance($0))" } ?? "Entfernung unbekannt"
        if let accuracy = location.accuracy, location.coordinate != nil {
            text += ", Genauigkeit plus minus \(MapFormat.distance(accuracy))"
        }
        return text
    }
}

/// Cachebox `setMoonSunPos`: sun and moon at the edge of the compass in their direction (turned with the heading),
/// only while above the horizon.
private struct SunAndMoon: View {
    let location: LocationModel
    let center: CGPoint
    let dialSize: CGFloat
    let iconSize: CGFloat

    var body: some View {
        if let here = location.coordinate {
            let now = Date()
            let heading = location.heading ?? 0
            // Cachebox: radius = frame/2 + sun/2 + sun/8, the icon centre sun/2 further in
            let radius = dialSize / 2 + iconSize / 8
            let sun = SkyPosition.sun(at: now, latitude: here.latitude, longitude: here.longitude)
            let moon = SkyPosition.moon(at: now, latitude: here.latitude, longitude: here.longitude)
            ZStack {
                if moon.elevation >= 0 { mark("mond", moon, heading, radius, "Mond") }
                if sun.elevation >= 0 { mark("sonne", sun, heading, radius, "Sonne") }
            }
        }
    }

    private func mark(_ image: String, _ position: SkyPosition.Position, _ heading: Double, _ radius: CGFloat,
                      _ name: String) -> some View {
        let angle = (position.azimuth - heading) * .pi / 180
        return Image(image)
            .resizable()
            .interpolation(.high)
            .frame(width: iconSize, height: iconSize)
            .position(x: center.x + radius * sin(angle), y: center.y - radius * cos(angle))
            .accessibilityLabel("\(name), \(Int(position.azimuth.rounded())) Grad, "
                                + "\(Int(position.elevation.rounded())) Grad über dem Horizont")
    }
}
