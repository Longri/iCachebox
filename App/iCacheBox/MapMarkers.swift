import CacheboxCore
import SwiftUI
import UIKit

/// A cache or a waypoint on the map (Cachebox `MapViewCacheList.WayPointRenderInfo`).
struct MapMarker: Equatable, Identifiable {
    enum Content: Equatable {
        case cache(CacheSummary)
        case waypoint(Waypoint)
    }

    /// Cache code, or `cacheCode/code` for a waypoint.
    let id: String
    var content: Content
    var latitude: Double
    var longitude: Double
    /// The selected cache or one of its waypoints: always framed; the selected cache is always big and on top.
    var isSelected = false
    /// A cache of the signed-in user (Cachebox `iAmTheOwner`, star icon).
    var isOwn = false

    static func cache(_ cache: CacheSummary, isSelected: Bool, isOwn: Bool) -> MapMarker {
        let target = cache.target
        return MapMarker(id: cache.code, content: .cache(cache), latitude: target.latitude,
                         longitude: target.longitude, isSelected: isSelected, isOwn: isOwn)
    }

    static func waypoint(_ waypoint: Waypoint, at coordinate: Coordinate) -> MapMarker {
        MapMarker(id: waypoint.id, content: .waypoint(waypoint), latitude: coordinate.latitude,
                  longitude: coordinate.longitude, isSelected: true)
    }

    var cache: CacheSummary? {
        if case .cache(let cache) = content { cache } else { nil }
    }

    var title: String {
        switch content {
        case .cache(let cache): cache.name
        case .waypoint(let waypoint): waypoint.title.isEmpty ? waypoint.type.title : waypoint.title
        }
    }

    var subtitle: String {
        switch content {
        case .cache(let cache): "\(cache.code) · \(cache.ratingText)"
        case .waypoint(let waypoint): "\(waypoint.code) · \(waypoint.type.title)"
        }
    }

    var accessibilityLabel: String {
        switch content {
        case .cache(let cache):
            var parts = [cache.type.title, cache.name, cache.code, cache.ratingText]
            if cache.isFound { parts.append("gefunden") }
            if cache.isFavorite { parts.append("Favorit") }
            if cache.isArchived {
                parts.append("archiviert")
            } else if !cache.isAvailable {
                parts.append("nicht verfügbar")
            }
            if isSelected { parts.append("gewählt") }
            return parts.joined(separator: ", ")
        case .waypoint(let waypoint):
            return [waypoint.type.title, title, waypoint.code].joined(separator: ", ")
        }
    }
}

/// Icon size on the map by zoom level (Cachebox `MapView.render`: `iconSize` 0 below zoom 13, 1 at 13–14, 2 from 15).
enum MarkerSize: Int, Comparable {
    case small, medium, large

    init(zoom: Double) {
        switch Int(zoom.rounded()) {
        case ..<13: self = .small
        case 13...14: self = .medium
        default: self = .large
        }
    }

    /// Frame (`shaddowrect`) and icon edge in points. Cachebox's `renderWayPoints` gets `GL_UISizes.wayPointSizes`
    /// (13/20/32 dp) and `underlaySizes` (13/14/21 dp) in swapped order, so the frame is the larger of the two.
    var frame: CGFloat { [13, 20, 32][rawValue] }
    var icon: CGFloat { [13, 14, 21][rawValue] }

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// Draws and caches the marker images: Cachebox draws an underlay (`shaddowrect`, red-framed `shaddowrect-selected`
/// for the selected cache), the icon, the favourite heart and, for archived or unavailable caches, the `deact`
/// overlay. Frame and overlay are drawn here instead of scaling up the 48 px sprites.
@MainActor
final class MarkerImages {
    private var cache: [String: UIImage] = [:]
    /// Room around the frame for its shadow and the heart.
    private static let padding: CGFloat = 5

    func image(for marker: MapMarker, size zoomSize: MarkerSize) -> UIImage? {
        switch marker.content {
        case .cache(let cache):
            if marker.isSelected {
                return framed(cache.mapIconName(isOwn: marker.isOwn), size: .large, selected: true,
                              favorite: cache.isFavorite, disabled: cache.isArchived || !cache.isAvailable)
            }
            if zoomSize == .small {
                // Cachebox: small sprite without frame; the "no" sprites already show archived/unavailable
                return plain(cache.smallMapIconName(isOwn: marker.isOwn), edge: zoomSize.icon)
            }
            return framed(cache.mapIconName(isOwn: marker.isOwn), size: zoomSize, selected: false,
                          favorite: cache.isFavorite, disabled: cache.isArchived || !cache.isAvailable)
        case .waypoint(let waypoint):
            // Cachebox frames the waypoints of the selected cache at every zoom; at the smallest size the icon would
            // cover the frame completely, so they stay medium there
            return framed(waypoint.type.iconName, size: max(zoomSize, .medium), selected: false, favorite: false,
                          disabled: false)
        }
    }

    private func plain(_ name: String, edge: CGFloat) -> UIImage? {
        let key = "\(name)|\(edge)"
        if let image = cache[key] { return image }
        guard let icon = UIImage(named: name) else { return nil }
        let image = UIGraphicsImageRenderer(size: CGSize(width: edge, height: edge)).image { _ in
            icon.draw(in: Self.fit(icon.size, into: CGRect(x: 0, y: 0, width: edge, height: edge)))
        }
        cache[key] = image
        return image
    }

    private func framed(_ name: String, size: MarkerSize, selected: Bool, favorite: Bool, disabled: Bool) -> UIImage? {
        let key = "\(name)|\(size.rawValue)|\(selected)|\(favorite)|\(disabled)"
        if let image = cache[key] { return image }
        let side = size.frame + 2 * Self.padding
        let frame = CGRect(x: Self.padding, y: Self.padding, width: size.frame, height: size.frame)
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            let cg = context.cgContext
            let radius = size.frame * 0.18
            let box = UIBezierPath(roundedRect: frame.insetBy(dx: 1, dy: 1), cornerRadius: radius)
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 1, height: 1.5), blur: 2.5, color: UIColor.black.withAlphaComponent(0.45).cgColor)
            UIColor.white.setFill()
            box.fill()
            cg.restoreGState()
            if selected {
                UIColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1).setStroke()
                box.lineWidth = max(2, size.frame / 12)
            } else {
                UIColor(white: 0.3, alpha: 1).setStroke()
                box.lineWidth = 1
            }
            box.stroke()

            if let icon = UIImage(named: name) {
                let edge = size.icon
                icon.draw(in: Self.fit(icon.size, into: CGRect(x: frame.midX - edge / 2, y: frame.midY - edge / 2,
                                                              width: edge, height: edge)))
            }
            if favorite, let heart = UIImage(named: "favorit") {
                let edge = size.icon / 2
                heart.draw(in: CGRect(x: frame.maxX - edge * 0.7, y: frame.minY - edge * 0.3, width: edge, height: edge))
            }
            if disabled {
                // Cachebox `deact`: reddish veil with a red diagonal
                UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.3).setFill()
                box.fill()
                let line = UIBezierPath()
                line.move(to: CGPoint(x: frame.minX + 2, y: frame.maxY - 2))
                line.addLine(to: CGPoint(x: frame.maxX - 2, y: frame.minY + 2))
                line.lineWidth = max(1.5, size.frame / 14)
                line.lineCapStyle = .round
                UIColor(red: 0.9, green: 0, blue: 0, alpha: 1).setStroke()
                line.stroke()
            }
        }
        cache[key] = image
        return image
    }

    /// `size` scaled to fit into `rect`, centered (the Cachebox icons are not all square).
    private static func fit(_ size: CGSize, into rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2,
                      width: fitted.width, height: fitted.height)
    }
}

/// Content of the info bubble that opens when a cache on the map is tapped (Cachebox `InfoBubble` with
/// `CacheInfo.VIEW_MODE_BUBBLE`: icon, name, owner – the date for events –, coordinates, D/T/size). The name is
/// the callout title above it. Tapping "Auswählen" selects the cache like tapping the bubble in Cachebox.
struct CacheBubble: View {
    let cache: CacheSummary
    let isSelected: Bool
    /// Device position for the distance, if known.
    let here: Coordinate?
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                CacheTypeIcon(type: cache.type, isFound: cache.isFound, isFavorite: cache.isFavorite,
                              isArchived: cache.isArchived, isUnavailable: !cache.isAvailable,
                              isSolved: cache.isSolved, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(cache.code) · \(cache.ratingText)")
                    if cache.type.isEvent, let hidden = cache.hidden {
                        Text(hidden.formatted(date: .abbreviated, time: .omitted))
                    }
                    if !cache.owner.isEmpty {
                        Text("von \(cache.owner)")
                    }
                    Text(cache.target.formatted).monospacedDigit()
                    if let here {
                        Text(Format.distance(here.distance(to: cache.target)) + " entfernt")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            if isSelected {
                Label("Gewählter Cache", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.tint)
            } else {
                Button("Auswählen", systemImage: "checkmark.circle", action: onSelect)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .tint(.cachebox)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
