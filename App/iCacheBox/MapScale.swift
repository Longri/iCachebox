import CoreGraphics
import Foundation

/// How much bigger everything the map renderer draws is shown – ways, areas, symbols and text alike
/// (mapsforge `DisplayModel.userScaleFactor`, which Cachebox leaves at 1; not a setting there).
///
/// A tile keeps its zoom level and so the detail and the labels mapsforge picked for that level, but it is
/// rendered with `factor` times as many pixels and drawn over `factor` times the length on the screen. For that
/// the camera has to sit `zoomOffset` levels further in than the tiles it shows, which is what the zoom buttons
/// step through once a factor is set – exactly what a bigger tile size does in mapsforge, where the tiles of a
/// level simply cover more of the screen.
enum MapScale: Int, CaseIterable, Identifiable, Sendable {
    case normal = 100
    case large = 125
    case larger = 150
    case largest = 200

    var id: Int { rawValue }

    /// Pixels drawn per pixel of a normal tile.
    var factor: CGFloat { CGFloat(rawValue) / 100 }

    /// Zoom levels the camera stands above the level of the tiles it shows (`log2(factor)`, 0 at 100 %).
    var zoomOffset: Double { log2(Double(factor)) }

    var title: String { self == .normal ? "Normal" : "\(rawValue) %" }

    private static let key = "map.scale"

    static var saved: MapScale {
        guard let raw = UserDefaults.standard.object(forKey: key) as? Int else { return .normal }
        return MapScale(rawValue: raw) ?? .normal
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.key)
    }
}
