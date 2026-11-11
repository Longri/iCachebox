import MapKit
import MapsforgeCore
import MapsforgeRender
import SwiftUI
import UIKit

/// Request to move the map. Each request has its own `id`; the map moves once per request, so the user can pan
/// freely afterwards.
struct MapCenterRequest: Equatable {
    var latitude: Double
    var longitude: Double
    /// Show about 1.5 km around the point; otherwise the zoom level is kept (unless the map is zoomed far out).
    var resetZoom: Bool
    let id = UUID()

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

/// A cache or waypoint drawn with its Cachebox icon (Cachebox `MapView` draws the selected cache and its waypoints).
struct MapMarker: Equatable, Identifiable {
    let id: String
    var latitude: Double
    var longitude: Double
    var iconName: String
    var title: String
    var subtitle: String
    /// The cache itself: bigger, above its waypoints, with a details button in the callout.
    var isCache: Bool
}

/// MKMapView whose base map is replaced by Mapsforge tiles rendered on the device.
struct MapsforgeMapView: UIViewRepresentable {
    let renderer: TileRenderer
    let stats: RenderStats
    let center: MapCenterRequest
    var markers: [MapMarker] = []
    var showsUserLocation = false
    /// Called by the details button in the callout of a cache marker.
    var onShowDetails: () -> Void = {}

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.pointOfInterestFilter = .excludingAll
        updateUIView(mapView, context: context)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let c = context.coordinator
        c.onShowDetails = onShowDetails
        if c.overlay?.renderer !== renderer {
            // new map/theme/style: replace the tile overlay (MapKit has no API to flush its tile cache)
            let overlay = MapsforgeTileOverlay(renderer: renderer, stats: stats)
            mapView.addOverlay(overlay, level: .aboveLabels)
            if let old = c.overlay { mapView.removeOverlay(old) }
            c.overlay = overlay
        }
        if c.centerID != center.id {
            let first = c.centerID == nil
            c.centerID = center.id
            // keep the zoom level, unless asked or the map shows a whole region (world view before the first move)
            if first || center.resetZoom || mapView.region.span.latitudeDelta > 0.2 {
                mapView.setRegion(MKCoordinateRegion(center: center.coordinate, latitudinalMeters: 1500,
                                                     longitudinalMeters: 1500), animated: false)
            } else {
                // not animated: during an animated move MapKit dropped some tile requests and left grey squares
                // until the next pan (seen in the simulator); jumping also saves rendering the tiles in between
                mapView.setCenter(center.coordinate, animated: false)
            }
        }
        let shown = mapView.annotations.compactMap { $0 as? MarkerAnnotation }
        if shown.map(\.marker) != markers {
            mapView.removeAnnotations(shown)
            mapView.addAnnotations(markers.map(MarkerAnnotation.init))
        }
        if mapView.showsUserLocation != showsUserLocation { mapView.showsUserLocation = showsUserLocation }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var overlay: MapsforgeTileOverlay?
        var centerID: UUID?
        var onShowDetails: () -> Void = {}
        private var icons: [String: UIImage] = [:]

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tiles)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? MarkerAnnotation else { return nil }   // user location: default
            let marker = annotation.marker
            let id = "marker"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.image = icon(marker.iconName, size: marker.isCache ? 40 : 30)
            view.canShowCallout = true
            view.displayPriority = .required
            view.zPriority = marker.isCache ? .max : .defaultUnselected
            if marker.isCache {
                let button = UIButton(type: .detailDisclosure)
                button.accessibilityLabel = "Details"
                view.rightCalloutAccessoryView = button
            } else {
                view.rightCalloutAccessoryView = nil
            }
            view.accessibilityLabel = [marker.title, marker.subtitle].joined(separator: ", ")
            return view
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                     calloutAccessoryControlTapped control: UIControl) {
            onShowDetails()
        }

        /// A Cachebox bitmap fitted into a square (the icons are not all square, `bigFinal` is 80 × 96 px).
        private func icon(_ name: String, size: CGFloat) -> UIImage? {
            let key = "\(name)@\(size)"
            if let cached = icons[key] { return cached }
            guard let image = UIImage(named: name) else { return nil }
            let scale = min(size / image.size.width, size / image.size.height)
            let fitted = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let result = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
                image.draw(in: CGRect(x: (size - fitted.width) / 2, y: (size - fitted.height) / 2,
                                      width: fitted.width, height: fitted.height))
            }
            icons[key] = result
            return result
        }
    }
}

/// MapKit annotation for a `MapMarker`.
final class MarkerAnnotation: NSObject, MKAnnotation {
    let marker: MapMarker
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?

    init(_ marker: MapMarker) {
        self.marker = marker
        coordinate = CLLocationCoordinate2D(latitude: marker.latitude, longitude: marker.longitude)
        title = marker.title
        subtitle = marker.subtitle
    }
}

/// Renders tiles on demand with the Swift Mapsforge renderer.
final class MapsforgeTileOverlay: MKTileOverlay, @unchecked Sendable {
    let renderer: TileRenderer
    private let stats: RenderStats
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "mapsforge.render"
        q.maxConcurrentOperationCount = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
        q.qualityOfService = .userInitiated
        return q
    }()

    init(renderer: TileRenderer, stats: RenderStats) {
        self.renderer = renderer
        self.stats = stats
        super.init(urlTemplate: nil)
        canReplaceMapContent = true
        minimumZ = 6
        maximumZ = 21
        tileSize = CGSize(width: 256, height: 256)
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let renderer = self.renderer
        let stats = self.stats
        nonisolated(unsafe) let result = result   // MapKit's completion handler may be called from any thread
        queue.addOperation {
            let start = CFAbsoluteTimeGetCurrent()
            let tile = Tile(tileX: path.x, tileY: path.y, zoomLevel: path.z, tileSize: 256)
            guard let image = renderer.renderTile(tile, scale: path.contentScaleFactor) else {
                result(nil, nil)
                return
            }
            let data = UIImage(cgImage: image).pngData()
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            Task { @MainActor in stats.record(ms: ms, zoom: path.z) }
            result(data, nil)
        }
    }
}
