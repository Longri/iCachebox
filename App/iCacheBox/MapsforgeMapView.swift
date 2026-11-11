import CacheboxCore
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
    /// An exact zoom level (tile zoom, may be fractional), e.g. the position of the last session; wins over
    /// `resetZoom`.
    var zoom: Double?
    let id = UUID()

    init(latitude: Double, longitude: Double, resetZoom: Bool, zoom: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.resetZoom = resetZoom
        self.zoom = zoom
    }

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

/// Center and zoom level of the map, kept across launches (Cachebox `mapInitLatitude`, `mapInitLongitude`,
/// `lastZoomLevel`).
struct MapCamera: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    /// Tile zoom level, may be fractional.
    var zoom: Double

    private static let key = "map.camera"

    static var saved: MapCamera? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(MapCamera.self, from: $0) }
    }

    func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }
}

/// MKMapView whose base map is replaced by Mapsforge tiles rendered on the device, with the caches of the list and
/// the waypoints of the selected cache on top (Cachebox `MapView` with `MapViewCacheList`).
struct MapsforgeMapView: UIViewRepresentable {
    let renderer: TileRenderer
    let stats: RenderStats
    let center: MapCenterRequest
    var markers: [MapMarker] = []
    var showsUserLocation = false
    /// "Auswählen" in the info bubble of a cache.
    var onSelect: (CacheSummary) -> Void = { _ in }
    /// The details button in the info bubble of a cache.
    var onShowDetails: (CacheSummary) -> Void = { _ in }
    /// The map came to rest at a new position (after panning, zooming or a jump).
    var onCameraChange: (MapCamera) -> Void = { _ in }

    func makeUIView(context: Context) -> CacheMapView {
        let mapView = CacheMapView()
        mapView.delegate = context.coordinator
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.pointOfInterestFilter = .excludingAll
        context.coordinator.installTapRecognizer(on: mapView)
        updateUIView(mapView, context: context)
        return mapView
    }

    func updateUIView(_ mapView: CacheMapView, context: Context) {
        let c = context.coordinator
        c.onSelect = onSelect
        c.onShowDetails = onShowDetails
        c.onCameraChange = onCameraChange
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
            if let zoom = center.zoom {
                mapView.setCenter(center.coordinate, zoomLevel: zoom)
            } else if first || center.resetZoom || mapView.region.span.latitudeDelta > 0.2 {
                // keep the zoom level, unless asked or the map shows a whole region (world view before the first move)
                mapView.setRegion(MKCoordinateRegion(center: center.coordinate, latitudinalMeters: 1500,
                                                     longitudinalMeters: 1500), animated: false)
            } else {
                // not animated: during an animated move MapKit dropped some tile requests and left grey squares
                // until the next pan (seen in the simulator); jumping also saves rendering the tiles in between
                mapView.setCenter(center.coordinate, animated: false)
            }
        }
        c.update(markers, on: mapView)
        if mapView.showsUserLocation != showsUserLocation { mapView.showsUserLocation = showsUserLocation }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var overlay: MapsforgeTileOverlay?
        var centerID: UUID?
        var onSelect: (CacheSummary) -> Void = { _ in }
        var onShowDetails: (CacheSummary) -> Void = { _ in }
        var onCameraChange: (MapCamera) -> Void = { _ in }
        /// Annotations on the map by marker id; kept across updates so that a changed selection only touches the
        /// markers that changed instead of replacing thousands of annotations.
        private var annotations: [String: MarkerAnnotation] = [:]
        private var markerSize = MarkerSize.large
        private let images = MarkerImages()
        /// Keeps the SwiftUI content of the open info bubble alive.
        private var bubble: UIHostingController<CacheBubble>?

        // MARK: Markers

        func update(_ markers: [MapMarker], on mapView: MKMapView) {
            var old = annotations
            var next: [String: MarkerAnnotation] = [:]
            next.reserveCapacity(markers.count)
            var added: [MarkerAnnotation] = []
            for marker in markers where next[marker.id] == nil {
                if let annotation = old.removeValue(forKey: marker.id) {
                    if annotation.marker != marker {
                        let wasSelectedCache = annotation.marker.isSelected
                        annotation.update(marker)
                        if let view = mapView.view(for: annotation) {
                            configure(view, for: annotation)
                            // the callout belongs to the old state (e.g. "Auswählen" after the cache was selected)
                            if wasSelectedCache != marker.isSelected, view.isSelected {
                                mapView.deselectAnnotation(annotation, animated: true)
                            }
                        }
                    }
                    next[marker.id] = annotation
                } else {
                    let annotation = MarkerAnnotation(marker)
                    added.append(annotation)
                    next[marker.id] = annotation
                }
            }
            if !old.isEmpty { mapView.removeAnnotations(Array(old.values)) }
            if !added.isEmpty { mapView.addAnnotations(added) }
            annotations = next
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? MarkerAnnotation else { return nil }   // user location: default
            let id = "marker"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.canShowCallout = true
            // Cachebox draws every cache; MapKit would hide overlapping markers otherwise
            view.displayPriority = .required
            configure(view, for: annotation)
            return view
        }

        private func configure(_ view: MKAnnotationView, for annotation: MarkerAnnotation) {
            let marker = annotation.marker
            view.image = images.image(for: marker, size: markerSize)
            // the selected cache on top, then its waypoints, then the other caches (Cachebox draws the selected last)
            view.zPriority = switch marker.content {
            case .cache: marker.isSelected ? .max : .defaultUnselected
            case .waypoint: MKAnnotationViewZPriority(rawValue: 750)
            }
            view.accessibilityLabel = marker.accessibilityLabel
        }

        /// Marker icons change size at zoom 13 and 15 like in Cachebox.
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            let size = MarkerSize(zoom: mapView.zoomLevel)
            guard size != markerSize else { return }
            markerSize = size
            for annotation in annotations.values {
                if let view = mapView.view(for: annotation) { configure(view, for: annotation) }
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard centerID != nil, let mapView = mapView as? CacheMapView, !mapView.isSettingCamera,
                  mapView.bounds.width > 0 else { return }
            let center = mapView.centerCoordinate
            onCameraChange(MapCamera(latitude: center.latitude, longitude: center.longitude, zoom: mapView.zoomLevel))
        }

        // MARK: Info bubble

        /// The bubble content is built only for the tapped cache, not for every marker on the screen.
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation as? MarkerAnnotation else { return }
            guard let cache = annotation.marker.cache else {
                view.detailCalloutAccessoryView = nil
                view.rightCalloutAccessoryView = nil
                return
            }
            let here = mapView.showsUserLocation ? mapView.userLocation.location.map {
                Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
            } : nil
            let content = CacheBubble(cache: cache, isSelected: annotation.marker.isSelected, here: here) {
                [weak self, weak mapView] in
                mapView?.deselectAnnotation(annotation, animated: true)
                self?.onSelect(cache)
            }
            let host = UIHostingController(rootView: content)
            host.safeAreaRegions = []   // near the screen edge SwiftUI would add the safe area as padding
            host.view.backgroundColor = .clear
            // a fixed size: with only an intrinsic size MapKit sometimes laid the callout out before SwiftUI had
            // measured it (narrow, wrapped lines, partly under the status bar)
            let size = host.sizeThatFits(in: CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude))
            host.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([host.view.widthAnchor.constraint(equalToConstant: ceil(size.width)),
                                         host.view.heightAnchor.constraint(equalToConstant: ceil(size.height))])
            bubble = host
            view.detailCalloutAccessoryView = host.view
            let details = UIButton(type: .detailDisclosure)
            details.accessibilityLabel = "Details"
            view.rightCalloutAccessoryView = details
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            view.detailCalloutAccessoryView = nil
            view.rightCalloutAccessoryView = nil
            bubble = nil
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                     calloutAccessoryControlTapped control: UIControl) {
            guard let cache = (view.annotation as? MarkerAnnotation)?.marker.cache else { return }
            mapView.deselectAnnotation(view.annotation, animated: false)
            onShowDetails(cache)
        }

        // MARK: Tapping next to a marker

        /// MapKit selects a marker only when its image is hit, which is hard with the small icons; Cachebox opens
        /// the bubble of the nearest cache within 40 px of the finger. A single tap that does not hit a marker
        /// selects the nearest one within `tapRadius`. The double-tap recognizer only keeps a double tap (zoom)
        /// from selecting a marker on its first tap.
        func installTapRecognizer(on mapView: MKMapView) {
            let doubleTap = UITapGestureRecognizer(target: nil, action: nil)
            doubleTap.numberOfTapsRequired = 2
            doubleTap.cancelsTouchesInView = false
            doubleTap.delegate = self
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            tap.require(toFail: doubleTap)
            mapView.addGestureRecognizer(doubleTap)
            mapView.addGestureRecognizer(tap)
        }

        private let tapRadius: CGFloat = 30

        @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let mapView = recognizer.view as? MKMapView else { return }
            let point = recognizer.location(in: mapView)
            var nearest: (annotation: MarkerAnnotation, distance: CGFloat)?
            for case let annotation as MarkerAnnotation in mapView.annotations(in: mapView.visibleMapRect) {
                let p = mapView.convert(annotation.coordinate, toPointTo: mapView)
                let distance = hypot(p.x - point.x, p.y - point.y)
                // equal distance (a waypoint at the cache position): the one drawn on top
                if distance <= tapRadius, distance < nearest?.distance ?? .infinity
                    || (distance == nearest?.distance && annotation.marker.isSelected) {
                    nearest = (annotation, distance)
                }
            }
            guard let nearest else { return }
            // after MapKit has handled the same tap (it deselects when the tap hits no marker)
            DispatchQueue.main.async { mapView.selectAnnotation(nearest.annotation, animated: true) }
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // markers and open bubbles handle their own touches
            var view = touch.view
            while let v = view, !(v is MKMapView) {
                if v is MKAnnotationView || v is UIControl || NSStringFromClass(type(of: v)).contains("Callout") {
                    return false
                }
                view = v.superview
            }
            return true
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        // MARK: Tiles

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tiles)
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

/// MKMapView that can be put on a zoom level before it has a size (the first position is set in `makeUIView`).
final class CacheMapView: MKMapView {
    private var pending: (center: CLLocationCoordinate2D, zoom: Double)?
    private var isApplying = false
    /// A position set with `setCenter(_:zoomLevel:)` waits for the first layout or is being applied; MapKit reports
    /// the intermediate regions as changes, which must not be remembered.
    var isSettingCamera: Bool { pending != nil || isApplying }

    /// Shows `center` at a tile zoom level: at zoom z a 256 pt tile covers 2^28 / 2^z map points
    /// (`MKMapSize.world` is 2^28 wide), so a screen point covers 2^(20 − z) map points. MapKit fits a visible map
    /// rect into the safe area, not the whole view (seen in the simulator: 0.26 zoom levels off), so the zoom is
    /// measured and corrected once; then the center is set like `centerCoordinate` reports it, the middle of the view.
    func setCenter(_ center: CLLocationCoordinate2D, zoomLevel: Double) {
        guard bounds.width > 0, bounds.height > 0 else {
            pending = (center, zoomLevel)
            return
        }
        pending = nil
        isApplying = true
        let mid = MKMapPoint(center)
        let scale = pow(2, 20 - zoomLevel)
        var size = MKMapSize(width: bounds.width * scale, height: bounds.height * scale)
        for _ in 0..<2 {
            setVisibleMapRect(MKMapRect(x: mid.x - size.width / 2, y: mid.y - size.height / 2,
                                        width: size.width, height: size.height), animated: false)
            let error = self.zoomLevel - zoomLevel
            if abs(error) < 0.001 { break }
            size = MKMapSize(width: size.width * pow(2, error), height: size.height * pow(2, error))
        }
        setCenter(center, animated: false)
        isApplying = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let pending, bounds.width > 0, bounds.height > 0 { setCenter(pending.center, zoomLevel: pending.zoom) }
    }
}

extension MKMapView {
    /// Tile zoom level of the view (fractional, 256 pt per tile like the Mapsforge tiles). Measured along a
    /// horizontal line through the center, so it is also right when the map is rotated.
    var zoomLevel: Double {
        guard bounds.width > 0 else { return 0 }
        let a = MKMapPoint(convert(CGPoint(x: bounds.midX - 50, y: bounds.midY), toCoordinateFrom: self))
        let b = MKMapPoint(convert(CGPoint(x: bounds.midX + 50, y: bounds.midY), toCoordinateFrom: self))
        let mapPointsPerPoint = hypot(b.x - a.x, b.y - a.y) / 100
        guard mapPointsPerPoint > 0 else { return 0 }
        return 20 - log2(mapPointsPerPoint)
    }
}

/// MapKit annotation for a `MapMarker`; updated in place when the marker changes (KVO-observable properties).
final class MarkerAnnotation: NSObject, MKAnnotation {
    private(set) var marker: MapMarker
    @objc dynamic var coordinate: CLLocationCoordinate2D
    @objc dynamic var title: String?
    @objc dynamic var subtitle: String?

    init(_ marker: MapMarker) {
        self.marker = marker
        coordinate = CLLocationCoordinate2D(latitude: marker.latitude, longitude: marker.longitude)
        title = marker.title
        subtitle = marker.subtitle
    }

    func update(_ marker: MapMarker) {
        if marker.latitude != self.marker.latitude || marker.longitude != self.marker.longitude {
            coordinate = CLLocationCoordinate2D(latitude: marker.latitude, longitude: marker.longitude)
        }
        if marker.title != title { title = marker.title }
        if marker.subtitle != subtitle { subtitle = marker.subtitle }
        self.marker = marker
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
