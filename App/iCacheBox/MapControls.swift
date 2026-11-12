import CacheboxCore
import SwiftUI

/// Sizes of the controls over the map (Cachebox `GL_UISizes`: `info`, `toggle`, `margin`).
enum MapLayout {
    static let margin: CGFloat = 8
    /// GPS/Free button, square (Cachebox `toggle`: 1.1 × button height).
    static let buttonSize: CGFloat = 56
    /// Info panel height, as high as the button (Cachebox `info`).
    static let panelHeight: CGFloat = buttonSize
    /// The round map menu button under the GPS/Free button.
    static let menuSize: CGFloat = 44
    /// Info panel width in landscape and on iPad.
    static let panelMaxWidth: CGFloat = 440
}

/// The center of the visible map, updated while the map moves. Kept apart from `MapModel` so that only the info
/// panel is redrawn while panning.
@MainActor
@Observable
final class MapViewport {
    var center: Coordinate?
}

/// Cachebox `MultiToggleButton` `btnMapState` with the states Free and GPS: a green button with the state name and an
/// LED below it, green for GPS and grey (off) for Free.
struct MapStateButton: View {
    let state: MapState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(state == .gps ? "GPS" : "Free")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(white: 0.08))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxHeight: .infinity)
                // Cachebox `toggle-led-gr`, tinted with the state color
                Capsule()
                    .fill(state == .gps ? Color(red: 0, green: 0.94, blue: 0) : Color(white: 0.46))
                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5))
                    .shadow(color: state == .gps ? Color(red: 0, green: 1, blue: 0).opacity(0.8) : .clear, radius: 2)
                    .frame(height: 5)
                    .padding(.horizontal, 9)
                    .padding(.bottom, 9)
            }
        }
        .buttonStyle(CacheboxButtonStyle())
        .frame(width: MapLayout.buttonSize, height: MapLayout.buttonSize)
        .accessibilityLabel("Kartenmodus")
        .accessibilityValue(state == .gps ? "GPS, die Karte folgt der eigenen Position" : "Frei")
        .accessibilityHint(state == .gps ? "Zentriert die Karte auf die eigene Position"
                                         : "Springt zur eigenen Position und folgt ihr")
    }
}

/// The Cachebox button look (`btnNormal`/`btn-pressed`): olive green with a light top edge and a black frame,
/// yellow while pressed.
struct CacheboxButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        configuration.label
            .background {
                shape.fill(LinearGradient(stops: pressed ? [
                    .init(color: Color(red: 1, green: 0.93, blue: 0.72), location: 0),
                    .init(color: Color(red: 1, green: 0.8, blue: 0.13), location: 0.25),
                    .init(color: Color(red: 1, green: 0.8, blue: 0.18), location: 1),
                ] : [
                    .init(color: Color(red: 0.80, green: 0.83, blue: 0.73), location: 0),
                    .init(color: Color(red: 0.55, green: 0.62, blue: 0.39), location: 0.28),
                    .init(color: Color(red: 0.55, green: 0.62, blue: 0.39), location: 0.9),
                    .init(color: Color(red: 0.52, green: 0.58, blue: 0.37), location: 1),
                ], startPoint: .top, endPoint: .bottom))
            }
            .overlay { shape.strokeBorder(Color.black.opacity(0.95), lineWidth: 1.5) }
            .contentShape(shape)
            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
    }
}

/// Cachebox `MapInfoPanel`: compass with the arrow to the selected cache, distance to it, own speed, and the
/// coordinates of the map center with a symbol for where they come from (satellite = own position in GPS mode,
/// map = map center in Free mode).
struct MapInfoPanel: View {
    let location: LocationModel
    let viewport: MapViewport
    /// Target of the selected cache (Cachebox `GlobalCore.getSelectedCoordinate`).
    let target: Coordinate?
    let state: MapState

    private static let compassSize = MapLayout.panelHeight * 0.8

    var body: some View {
        HStack(spacing: 6) {
            compass
            VStack(alignment: .leading, spacing: 0) {
                Text(distanceText)
                    .font(.system(size: 20, weight: .bold))
                Text(MapFormat.speed(location.speed))
                    .font(.system(size: 13, weight: .semibold))
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .layoutPriority(1)
            Spacer(minLength: 2)
            VStack(alignment: .trailing, spacing: 2) {
                Text(viewport.center.map { MapFormat.latitude($0.latitude) } ?? "---")
                Text(viewport.center.map { MapFormat.longitude($0.longitude) } ?? "---")
            }
            .font(.system(size: 13, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .layoutPriority(1)
            // Cachebox `CoordSymbol`: 0.62 × panel height
            Image(state == .gps ? "Satellite" : "MapSymbol")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: MapLayout.panelHeight * 0.62, height: MapLayout.panelHeight * 0.62)
                .accessibilityHidden(true)
        }
        .foregroundStyle(Color(white: 0.05))
        .padding(.leading, 4)
        .padding(.trailing, 6)
        .frame(height: MapLayout.panelHeight)
        .frame(maxWidth: MapLayout.panelMaxWidth)
        .background { InfoPanelBackground() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// Compass rose turned with the heading so that north points north; the arrow points to the selected cache
    /// (Cachebox `MapInfoPanel.setBearing`: scale rotated by the heading, arrow by bearing − heading).
    private var compass: some View {
        let heading = location.heading ?? 0
        return ZStack {
            Image("CompassFrame").resizable().interpolation(.high)
            Image("CompassScale").resizable().interpolation(.high)
                .rotationEffect(.degrees(-heading))
            if let here = location.coordinate, let target {
                CacheboxPositionArrow(compass: location.isCompassHeading, size: MapLayout.panelHeight * 0.5)
                    .rotationEffect(.degrees(here.bearing(to: target) - heading))
            }
        }
        .frame(width: Self.compassSize, height: Self.compassSize)
    }

    private var distance: Double? {
        guard let here = location.coordinate, let target else { return nil }
        return here.distance(to: target)
    }

    private var distanceText: String {
        distance.map(MapFormat.distance) ?? "---"
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if let distance { parts.append("Entfernung zum Cache \(MapFormat.distance(distance))") }
        if location.speed != nil { parts.append("Geschwindigkeit \(MapFormat.speed(location.speed))") }
        if let center = viewport.center {
            let source = state == .gps ? "Eigene Position" : "Kartenmitte"
            parts.append("\(source) \(MapFormat.latitude(center.latitude)), \(MapFormat.longitude(center.longitude))")
        }
        return parts.isEmpty ? "Keine Positionsdaten" : parts.joined(separator: ", ")
    }
}

/// Cachebox `InfoPanelBack` (`Sprites.infoBack`): light green, slightly transparent, grey frame. Background of the
/// map info panel and of the distance in the compass view.
struct InfoPanelBackground: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        let frame = Color(red: 149 / 255, green: 163 / 255, blue: 152 / 255)
        shape.fill(Color(red: 216 / 255, green: 239 / 255, blue: 221 / 255).opacity(0.85))
            .overlay { shape.strokeBorder(frame, lineWidth: 1.5) }
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }
}

/// Number formats of the Cachebox map info panel.
enum MapFormat {
    private static func number(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)).grouping(.never))
    }

    /// Cachebox `UnitFormatter.distanceStringMetric`: metres up to 500 m, then km with two decimals below 10 km.
    static func distance(_ metres: Double) -> String {
        if metres <= 500 { return number(metres, digits: 0) + " m" }
        if metres < 10_000 { return number(metres / 1000, digits: 2) + " km" }
        return number(metres / 1000, digits: 0) + " km"
    }

    /// Cachebox `Formatter.SpeedStringMetric`, "1,18 km/h"; "---" without speed.
    static func speed(_ metresPerSecond: Double?) -> String {
        guard let metresPerSecond else { return "---" }
        return number(metresPerSecond * 3.6, digits: 2) + " km/h"
    }

    /// Cachebox `UnitFormatter.FormatLatitudeDM`, "48°  29,337 N".
    static func latitude(_ value: Double) -> String { degreesMinutes(value, "N", "S") }

    /// Cachebox `UnitFormatter.FormatLongitudeDM`, "9°  15,858 E".
    static func longitude(_ value: Double) -> String { degreesMinutes(value, "E", "W") }

    /// Cachebox `Coordinate.formatCoordinate`, "52°  26,910 N / 13°  32,748 E".
    static func coordinate(_ value: Coordinate) -> String {
        latitude(value.latitude) + " / " + longitude(value.longitude)
    }

    private static func degreesMinutes(_ value: Double, _ positive: String, _ negative: String) -> String {
        // round to thousandths of a minute first, so that 59.9996' becomes the next degree and not "60,000"
        let thousandths = (abs(value) * 60_000).rounded()
        let degrees = Int(thousandths / 60_000)
        let minutes = (thousandths - Double(degrees) * 60_000) / 1000
        return "\(degrees)°  \(number(minutes, digits: 3)) \(value < 0 ? negative : positive)"
    }
}
