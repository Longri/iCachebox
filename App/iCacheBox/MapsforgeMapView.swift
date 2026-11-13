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
    let center: MapCenterRequest
    var markers: [MapMarker] = []
    /// Source of the own position, drawn as an arrow in the direction the user looks. Observed by the coordinator
    /// itself, so that a new heading does not rebuild the whole map view with its thousands of markers.
    var location: LocationModel?
    /// Target of the selected cache; an arrow at the map edge points to it while it is off the screen.
    var target: Coordinate?
    /// GPS mode: the map keeps the own position in the middle.
    var followsPosition = false
    /// The map turns with the heading of the own position (Cachebox "Nach Kompass ausrichten").
    var alignsToHeading = false
    /// Parts of the view covered by the info panel, the buttons and the bars; the edge arrows, the compass, the
    /// scale and the zoom buttons stay inside the rest.
    var chromeInsets = UIEdgeInsets.zero
    /// "Auswählen" in the info bubble of a cache.
    var onSelect: (CacheSummary) -> Void = { _ in }
    /// The details button in the info bubble of a cache.
    var onShowDetails: (CacheSummary) -> Void = { _ in }
    /// "Als Ziel" in the info bubble of a waypoint (Cachebox `setSelectedWaypoint`).
    var onSelectWaypoint: (Waypoint) -> Void = { _ in }
    /// The map came to rest at a new position (after panning, zooming or a jump).
    var onCameraChange: (MapCamera) -> Void = { _ in }
    /// The map center moved (also while panning); for the coordinates in the info panel.
    var onCenterChange: (Coordinate) -> Void = { _ in }
    /// The user started to move the map with one finger (Cachebox switches GPS to Free then).
    var onUserPan: () -> Void = {}
    /// The own position changed (GPS mode: the map may need another map file).
    var onPositionChange: (Coordinate) -> Void = { _ in }
    /// The arrow at the map edge pointing to the own position was tapped.
    var onPositionArrow: () -> Void = {}
    /// The arrow at the map edge pointing to the selected cache was tapped.
    var onTargetArrow: () -> Void = {}

    func makeUIView(context: Context) -> CacheMapView {
        let mapView = CacheMapView()
        mapView.delegate = context.coordinator
        // compass and scale are placed by `CacheMapView` so they do not end up under the info panel
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.pointOfInterestFilter = .excludingAll
        // where MapKit has not drawn the overlay yet it shows a grid, black in dark mode; the Mapsforge themes are
        // light, so a light grid flashes far less (also gives compass, scale and info bubble the light look)
        mapView.overrideUserInterfaceStyle = .light
        context.coordinator.installTapRecognizer(on: mapView)
        context.coordinator.installPanRecognizer(on: mapView)
        mapView.onCameraApplied = { [weak coordinator = context.coordinator, weak mapView] in
            if let coordinator, let mapView { coordinator.cameraApplied(on: mapView) }
        }
        let arrows = mapView.edgeArrows
        arrows.positionArrow.addTarget(context.coordinator, action: #selector(Coordinator.positionArrowTapped),
                                       for: .touchUpInside)
        arrows.targetArrow.addTarget(context.coordinator, action: #selector(Coordinator.targetArrowTapped),
                                     for: .touchUpInside)
        updateUIView(mapView, context: context)
        return mapView
    }

    func updateUIView(_ mapView: CacheMapView, context: Context) {
        let c = context.coordinator
        c.onSelect = onSelect
        c.onShowDetails = onShowDetails
        c.onSelectWaypoint = onSelectWaypoint
        c.onCameraChange = onCameraChange
        c.onCenterChange = onCenterChange
        c.onUserPan = onUserPan
        c.onPositionChange = onPositionChange
        c.onPositionArrow = onPositionArrow
        c.onTargetArrow = onTargetArrow
        // before the moves below: a jump caused by them must not be taken back by the GPS mode just left
        c.setFollowing(followsPosition)
        c.setAligning(alignsToHeading, on: mapView)
        if mapView.chromeInsets != chromeInsets { mapView.chromeInsets = chromeInsets }
        if c.overlay?.renderer !== renderer {
            // new map/theme/style: replace the tile overlay (MapKit has no API to flush its tile cache)
            let overlay = MapsforgeTileOverlay(renderer: renderer)
            if let old = c.overlay, let oldTiles = mapView.renderer(for: old) as? MapsforgeOverlayRenderer {
                // the old map stays visible until the new tiles are rendered
                oldTiles.cancel()
                overlay.previousTiles = oldTiles.cache
            }
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
        c.observe(location, on: mapView)
        c.target = target
        c.followPosition(on: mapView)
        c.alignToHeading(on: mapView)
        c.refreshPositionViews(on: mapView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var overlay: MapsforgeTileOverlay?
        var centerID: UUID?
        var onSelect: (CacheSummary) -> Void = { _ in }
        var onShowDetails: (CacheSummary) -> Void = { _ in }
        var onSelectWaypoint: (Waypoint) -> Void = { _ in }
        var onCameraChange: (MapCamera) -> Void = { _ in }
        var onCenterChange: (Coordinate) -> Void = { _ in }
        var onUserPan: () -> Void = {}
        var onPositionChange: (Coordinate) -> Void = { _ in }
        var onPositionArrow: () -> Void = {}
        var onTargetArrow: () -> Void = {}
        var target: Coordinate?
        private weak var location: LocationModel?
        private var position: OwnPosition?
        private var positionAnnotation: OwnPositionAnnotation?
        private var followsPosition = false
        private var alignsToHeading = false
        /// Position the map was last centered on in GPS mode.
        private var followed: Coordinate?
        private var lastCenter: CLLocationCoordinate2D?
        /// Annotations on the map by marker id; kept across updates so that a changed selection only touches the
        /// markers that changed instead of replacing thousands of annotations.
        private var annotations: [String: MarkerAnnotation] = [:]
        private var markerSize = MarkerSize.large
        private let images = MarkerImages()
        /// Keeps the SwiftUI content of the open info bubble alive.
        private var bubble: UIHostingController<AnyView>?

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
            if annotation is OwnPositionAnnotation {
                let id = "position"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? OwnPositionView
                    ?? OwnPositionView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                if let position { view.update(position: position, mapHeading: mapView.camera.heading,
                                              accuracyRadius: accuracyRadius(of: position, on: mapView)) }
                return view
            }
            guard let annotation = annotation as? MarkerAnnotation else { return nil }
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
            case .cache: marker.isSelected ? MKAnnotationViewZPriority(rawValue: 999) : .defaultUnselected
            case .waypoint: MKAnnotationViewZPriority(rawValue: 750)
            }
            view.accessibilityLabel = marker.accessibilityLabel
        }

        /// Marker icons change size at zoom 13 and 15 like in Cachebox. The own position, the edge arrows and the
        /// coordinates in the info panel move with the map; the zoom buttons follow the zoom level.
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            refreshPositionViews(on: mapView)
            (mapView as? CacheMapView)?.updateZoomButtons()
            let center = mapView.centerCoordinate
            if mapView.bounds.width > 0,
               center.latitude != lastCenter?.latitude || center.longitude != lastCenter?.longitude {
                lastCenter = center
                onCenterChange(Coordinate(latitude: center.latitude, longitude: center.longitude))
            }
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
            // GPS mode: zooming with two fingers or a double tap moves the middle; bring the position back
            if followsPosition, let position {
                // MapKit's middle is the middle of the safe area, not of the view
                let p = mapView.convert(position.clCoordinate, toPointTo: mapView)
                let c = mapView.convert(center, toPointTo: mapView)
                if hypot(p.x - c.x, p.y - c.y) > 1 {
                    mapView.setCenter(position.clCoordinate, animated: true)
                }
            }
        }

        // MARK: Own position

        /// Starts following `location` (once); every change moves the arrow and, in GPS mode, the map.
        func observe(_ location: LocationModel?, on mapView: CacheMapView) {
            guard location !== self.location else { return }
            self.location = location
            locationChanged(on: mapView)
        }

        /// Reads the position and registers for the next change (Observation calls `onChange` once, before the
        /// value is set, so the new value is read on the next turn of the main queue).
        private func locationChanged(on mapView: CacheMapView) {
            guard let location else {
                updatePosition(nil, on: mapView)
                return
            }
            let next = withObservationTracking {
                location.coordinate.map {
                    OwnPosition(coordinate: $0, accuracy: location.accuracy, heading: location.heading,
                                isCompass: location.isCompassHeading)
                }
            } onChange: { [weak self, weak mapView] in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, let mapView, self.location === location else { return }
                        self.locationChanged(on: mapView)
                    }
                }
            }
            let moved = next?.coordinate != position?.coordinate
            updatePosition(next, on: mapView)
            followPosition(on: mapView)
            alignToHeading(on: mapView)
            refreshPositionViews(on: mapView)
            if moved, let coordinate = next?.coordinate { onPositionChange(coordinate) }
        }

        /// Shows, moves or removes the arrow of the own position.
        private func updatePosition(_ newPosition: OwnPosition?, on mapView: MKMapView) {
            position = newPosition
            guard let newPosition else {
                if let positionAnnotation { mapView.removeAnnotation(positionAnnotation) }
                positionAnnotation = nil
                return
            }
            if let positionAnnotation {
                let coordinate = newPosition.clCoordinate
                if positionAnnotation.coordinate.latitude != coordinate.latitude
                    || positionAnnotation.coordinate.longitude != coordinate.longitude {
                    positionAnnotation.coordinate = coordinate
                }
            } else {
                let annotation = OwnPositionAnnotation(newPosition.clCoordinate)
                positionAnnotation = annotation
                mapView.addAnnotation(annotation)
            }
        }

        func setFollowing(_ follows: Bool) {
            followsPosition = follows
            if !follows { followed = nil }
        }

        /// A position set with `setCenter(_:zoomLevel:)` (the last session, a map change) has been applied; in GPS
        /// mode the own position goes back to the middle.
        func cameraApplied(on mapView: CacheMapView) {
            followed = nil
            followPosition(on: mapView)
            alignToHeading(on: mapView)
        }

        /// GPS mode (Cachebox `MapState.GPS`): the map centers on every new position, keeping the zoom. Without
        /// animation: MapKit dropped tile requests during animated moves, and the steps are small.
        func followPosition(on mapView: CacheMapView) {
            guard followsPosition, let position, position.coordinate != followed, mapView.bounds.width > 0,
                  !mapView.isSettingCamera else { return }
            followed = position.coordinate
            mapView.setCenter(position.clCoordinate, animated: false)
        }

        /// Switches "Nach Kompass ausrichten" on or off. While on, the heading turns the map, so the rotation
        /// gesture and MapKit's compass button (which would turn it back to north) are off; the compass rose in the
        /// info panel still shows north. Switched off, the map turns back to north (Cachebox: `mapHeading = 0`).
        func setAligning(_ aligns: Bool, on mapView: CacheMapView) {
            guard aligns != alignsToHeading else { return }
            alignsToHeading = aligns
            mapView.isRotateEnabled = !aligns
            mapView.showsCompassButton = !aligns
            if aligns {
                alignToHeading(on: mapView)
            } else if mapView.camera.heading != 0, !mapView.isSettingCamera {
                let camera = mapView.camera.copy() as! MKMapCamera
                camera.heading = 0
                mapView.setCamera(camera, animated: true)
            }
        }

        /// Turns the map so that the heading points up (Cachebox `MapViewBase.orientationChanged`: the camera
        /// rotates by `mapHeading`, the position arrow then points up). Rotates around the middle of the map, also
        /// in Free mode like Cachebox. Without a heading the map keeps its last rotation. Not animated: the compass
        /// sends small steps (`headingFilter` 2°), and MapKit's animation would lag behind.
        func alignToHeading(on mapView: CacheMapView) {
            guard alignsToHeading, let heading = position?.heading, mapView.bounds.width > 0,
                  !mapView.isSettingCamera else { return }
            let current = mapView.camera.heading
            var delta = (heading - current).truncatingRemainder(dividingBy: 360)
            if delta < 0 { delta += 360 }
            guard min(delta, 360 - delta) >= 0.5 else { return }
            let camera = mapView.camera.copy() as! MKMapCamera
            camera.heading = heading
            mapView.setCamera(camera, animated: false)
        }

        /// Accuracy circle radius in points (Cachebox `pixelsPerMeter * accuracy`).
        private func accuracyRadius(of position: OwnPosition, on mapView: MKMapView) -> CGFloat {
            guard let accuracy = position.accuracy, mapView.bounds.width > 0 else { return 0 }
            let mapPointsPerPoint = mapView.visibleMapRect.width / mapView.bounds.width
            guard mapPointsPerPoint > 0 else { return 0 }
            let mapPointsPerMeter = MKMapPointsPerMeterAtLatitude(position.coordinate.latitude)
            return CGFloat(accuracy * mapPointsPerMeter / mapPointsPerPoint)
        }

        /// Turns the position arrow with heading and map rotation, sizes the accuracy circle and places the arrows at
        /// the map edge.
        func refreshPositionViews(on mapView: MKMapView) {
            if let position, let positionAnnotation,
               let view = mapView.view(for: positionAnnotation) as? OwnPositionView {
                view.update(position: position, mapHeading: mapView.camera.heading,
                            accuracyRadius: accuracyRadius(of: position, on: mapView))
            }
            guard let mapView = mapView as? CacheMapView else { return }
            let arrows = mapView.edgeArrows
            let point = { (coordinate: Coordinate) in
                mapView.convert(CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
                                toPointTo: arrows)
            }
            arrows.update(area: mapView.freeArea, position: position.map { point($0.coordinate) },
                          target: target.map(point))
        }

        @objc func positionArrowTapped() { onPositionArrow() }

        @objc func targetArrowTapped() { onTargetArrow() }

        // MARK: Info bubble

        /// The bubble content is built only for the tapped marker, not for every one on the screen.
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation as? MarkerAnnotation else { return }
            let here = position?.coordinate
            let host: UIHostingController<AnyView>
            if let cache = annotation.marker.cache {
                let content = CacheBubble(cache: cache, isSelected: annotation.marker.isSelected, here: here) {
                    [weak self, weak mapView] in
                    mapView?.deselectAnnotation(annotation, animated: true)
                    self?.onSelect(cache)
                }
                host = UIHostingController(rootView: AnyView(content))
            } else if let waypoint = annotation.marker.waypoint {
                let coordinate = Coordinate(latitude: annotation.marker.latitude,
                                            longitude: annotation.marker.longitude)
                let content = WaypointBubble(waypoint: waypoint, coordinate: coordinate,
                                             isTarget: annotation.marker.isTarget, here: here) {
                    [weak self, weak mapView] in
                    mapView?.deselectAnnotation(annotation, animated: true)
                    self?.onSelectWaypoint(waypoint)
                }
                host = UIHostingController(rootView: AnyView(content))
            } else {
                view.detailCalloutAccessoryView = nil
                view.rightCalloutAccessoryView = nil
                return
            }
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
            if annotation.marker.cache != nil {
                let details = UIButton(type: .detailDisclosure)
                details.accessibilityLabel = "Details"
                view.rightCalloutAccessoryView = details
            } else {
                view.rightCalloutAccessoryView = nil
            }
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

        /// Moving the map with one finger ends the GPS mode (Cachebox `MapViewBase.onTouchDragged`: Pan with one
        /// finger sets `MapState.FREE`); zooming with two fingers keeps it.
        func installPanRecognizer(on mapView: MKMapView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
            pan.maximumNumberOfTouches = 1
            pan.cancelsTouchesInView = false
            pan.delaysTouchesBegan = false
            pan.delaysTouchesEnded = false
            pan.delegate = self
            panRecognizer = pan
            mapView.addGestureRecognizer(pan)
        }

        private weak var panRecognizer: UIPanGestureRecognizer?

        @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .began, followsPosition else { return }
            followsPosition = false   // before SwiftUI has passed on the new state
            onUserPan()
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
            // markers and open bubbles handle their own touches; the map also pans when dragged on a marker
            let isPan = recognizer === panRecognizer
            var view = touch.view
            while let v = view, !(v is MKMapView) {
                if (v is MKAnnotationView && !isPan) || v is UIControl
                    || NSStringFromClass(type(of: v)).contains("Callout") {
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
            if let tiles = overlay as? MapsforgeTileOverlay {
                let screen = mapView.window?.windowScene?.screen.bounds.size ?? mapView.bounds.size
                return MapsforgeOverlayRenderer(overlay: tiles, cache: TileCache(screen: screen))
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

/// MKMapView that can be put on a zoom level before it has a size (the first position is set in `makeUIView`).
/// Also holds the compass, the scale and the zoom buttons (placed outside the info panel) and the arrows at the map
/// edge.
final class CacheMapView: MKMapView {
    private var pending: (center: CLLocationCoordinate2D, zoom: Double)?
    private var isApplying = false
    let edgeArrows = EdgeArrowsView()
    private lazy var compassButton = MKCompassButton(mapView: self)
    private lazy var scaleView = MKScaleView(mapView: self)
    private let zoomButtons = ZoomButtonsView()
    /// MapKit's compass button, shown while the map is rotated; hidden while the map follows the heading.
    var showsCompassButton = true {
        didSet { compassButton.compassVisibility = showsCompassButton ? .adaptive : .hidden }
    }
    /// Called after a position set with `setCenter(_:zoomLevel:)` has been applied.
    var onCameraApplied: () -> Void = {}
    /// Parts covered by SwiftUI controls and bars.
    var chromeInsets = UIEdgeInsets.zero {
        didSet { setNeedsLayout() }
    }

    /// Zoom levels the zoom buttons step through: the levels the Mapsforge overlay renders (Cachebox
    /// `OsmMinLevel`/`OsmMaxLevel`: 7…21).
    static let zoomRange: ClosedRange<Double> = 6...21

    /// The part of the map not covered by controls or bars; the strip with the scale and the zoom buttons at the
    /// bottom is left out, so that the edge arrows stay above it.
    var freeArea: CGRect {
        var area = bounds.inset(by: chromeInsets)
        area.size.height = max(0, area.height - ZoomButtonsView.buttonSize.height - 2 * MapLayout.margin)
        return area
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        compassButton.compassVisibility = .adaptive   // only while the map is rotated, like MapKit's own
        scaleView.scaleVisibility = .visible          // always, like Cachebox `MapScale`
        scaleView.legendAlignment = .leading
        zoomButtons.zoomIn.addTarget(self, action: #selector(zoomInTapped), for: .touchUpInside)
        zoomButtons.zoomOut.addTarget(self, action: #selector(zoomOutTapped), for: .touchUpInside)
        addSubview(compassButton)
        addSubview(scaleView)
        addSubview(zoomButtons)
        addSubview(edgeArrows)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
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
        zoomStep = nil
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
        onCameraApplied()
    }

    // MARK: Zoom buttons

    @objc private func zoomInTapped() { zoom(by: 1) }

    @objc private func zoomOutTapped() { zoom(by: -1) }

    /// One zoom level in or out around the middle (Cachebox `ZoomButtons`: `zoom ± 1`, then a short zoom
    /// animation). After pinching the map is between levels; the step goes to the nearest whole level one further,
    /// where the tiles are drawn 1:1. Taps during the animation add up. While MapKit animates, the visible region
    /// still has the old level and `camera` may already have the new one (seen in the simulator), so every step
    /// is measured from the camera at rest before the first one.
    private func zoom(by step: Int) {
        zoomButtons.wake()
        let current = zoomLevel
        guard current.isFinite else { return }
        let running = zoomStep.flatMap { Date.now.timeIntervalSince($0.time) < 1 ? $0 : nil }
        let start = running.map { ($0.startLevel, $0.startDistance) } ?? (current, camera.centerCoordinateDistance)
        let base = running?.target ?? current
        let target = min(max((base + Double(step)).rounded(), Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        guard abs(target - base) > 0.01 else { return }
        zoomStep = ZoomStep(target: target, startLevel: start.0, startDistance: start.1, time: .now)
        let next = camera.copy() as! MKMapCamera
        // the camera distance halves with every level (2D map, no pitch)
        next.centerCoordinateDistance = start.1 * pow(2, start.0 - target)
        setCamera(next, animated: true)
        updateZoomButtons()
    }

    /// A zoom button animation: where it goes and the camera at rest before the first tap. Done when the level is
    /// reached, the map is touched elsewhere or after a second (MapKit may stop short of the target).
    private struct ZoomStep {
        let target: Double
        let startLevel: Double
        let startDistance: CLLocationDistance
        let time: Date
    }

    private var zoomStep: ZoomStep?

    func updateZoomButtons() {
        let level = zoomLevel
        guard level.isFinite else { return }   // MapKit may report no region while it jumps
        if let step = zoomStep, abs(level - step.target) < 0.01 || Date.now.timeIntervalSince(step.time) > 1 {
            zoomStep = nil
        }
        zoomButtons.update(zoomLevel: zoomStep?.target ?? level, range: Self.zoomRange)
    }

    /// Every touch on the map brings the faded zoom buttons back (Cachebox: when the map is moved); a touch
    /// outside them ends a zoom button step (pinching starts from where the map is).
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        if event?.type == .touches {
            zoomButtons.wake()
            if let view, !view.isDescendant(of: zoomButtons) { zoomStep = nil }
        }
        return view
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let pending, bounds.width > 0, bounds.height > 0 { setCenter(pending.center, zoomLevel: pending.zoom) }
        let area = bounds.inset(by: chromeInsets)
        let margin = MapLayout.margin
        // compass under the button column at the top right
        let compass = compassButton.sizeThatFits(CGSize(width: 100, height: 100))   // no intrinsic size (44 × 44)
        compassButton.frame = CGRect(x: area.maxX - margin - MapLayout.buttonSize / 2 - compass.width / 2,
                                     y: area.minY + MapLayout.menuSize + margin,
                                     width: compass.width, height: compass.height)
        // zoom buttons at the bottom right, the scale at the bottom left (Cachebox `MapView`: `zoomBtn`, `mapScale`)
        let zoom = zoomButtons.sizeThatFits(.zero)
        zoomButtons.frame = CGRect(x: area.maxX - margin - zoom.width, y: area.maxY - margin - zoom.height,
                                   width: zoom.width, height: zoom.height)
        let scaleWidth = max(0, min(area.width / 2, zoomButtons.frame.minX - margin - (area.minX + margin)))
        let scale = scaleView.sizeThatFits(CGSize(width: scaleWidth, height: 40))
        // level with the top of the zoom buttons, above MapKit's "Legal" link in the corner
        scaleView.frame = CGRect(x: area.minX + margin, y: zoomButtons.frame.minY - 4,
                                 width: max(scale.width, scaleWidth), height: scale.height)
        edgeArrows.frame = bounds
        updateZoomButtons()
        // MapKit inserts its own views (annotations, callouts) later; keep the controls on top
        if subviews.last !== edgeArrows {
            bringSubviewToFront(scaleView)
            bringSubviewToFront(compassButton)
            bringSubviewToFront(zoomButtons)
            bringSubviewToFront(edgeArrows)
        }
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
