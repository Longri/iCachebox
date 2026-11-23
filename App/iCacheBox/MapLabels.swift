import MapKit
import MapsforgeRender
import UIKit

/// Labels of the rendered tiles, kept out of the tile images so that `MapLabelsView` can draw them on the screen
/// (mapsforge `TileBasedLabelStore`). Filled on the rendering threads, read on the main thread.
final class MapLabelStore: @unchecked Sendable {
    private let lock = NSLock()
    private var tiles: [TileKey: [MapElementContainer]] = [:]
    /// Order the tiles came in; the oldest goes first when the store is full.
    private var order: [TileKey] = []
    private var version = 0
    /// Zoom level the overlay last drew its tiles at; the label layer has to use the same one.
    private var zoom: Int?
    private let capacity: Int

    init(capacity: Int = 256) {
        self.capacity = max(1, capacity)
    }

    /// The overlay is drawing tiles of this level now. Returns `true` if that is a new level, so that the
    /// label layer can be told (MapKit picks the level itself; guessing it from the camera was off by one while
    /// the map was between two levels, and then no labels were found at all).
    func setZoom(_ zoom: Int) -> Bool {
        lock.withLock {
            guard self.zoom != zoom else { return false }
            self.zoom = zoom
            return true
        }
    }

    var currentZoom: Int? { lock.withLock { zoom } }

    func store(_ labels: [MapElementContainer], for key: TileKey) {
        lock.withLock {
            if tiles.updateValue(labels, forKey: key) == nil {
                order.append(key)
                while order.count > capacity { tiles.removeValue(forKey: order.removeFirst()) }
            }
            version &+= 1
        }
    }

    /// The labels of `keys` in one list, with the version of the store they were read at: a new version means the
    /// visible labels have to be put together again.
    func labels(for keys: [TileKey]) -> (labels: [MapElementContainer], version: Int) {
        lock.withLock {
            var result: [MapElementContainer] = []
            for key in keys { result.append(contentsOf: tiles[key] ?? []) }
            return (result, version)
        }
    }

    func removeAll() {
        lock.withLock {
            tiles.removeAll()
            order.removeAll()
            zoom = nil
            version &+= 1
        }
    }
}

/// Draws the labels of the visible tiles above the map (mapsforge `LabelLayer`): the tiles are rendered without
/// them, so which label is drawn is decided over all visible tiles at once instead of tile by tile
/// (`TileDependencies` is not needed then). Every label is rendered into an image once and shown by a `CALayer`
/// of its own, so that moving the map only moves layers instead of drawing text again.
///
/// First step towards labels that keep their own direction while the map is turned: the labels still move and
/// scale exactly with the map, as they did inside the tiles.
@MainActor
final class MapLabelsView: UIView {
    private let store: MapLabelStore
    private weak var mapView: MKMapView?
    /// Zoom level, tiles and store version the current set of labels was put together for.
    private var zoom = -1
    private var tiles: [TileKey] = []
    private var version = -1
    /// The labels on screen with the part of the absolute pixel plane their image covers.
    private var placed: [(label: MapElementContainer, bounds: CGRect, layer: CALayer)] = []
    /// Rendered labels of the current set, `nil` for a label with nothing to draw.
    private var images: [MapElementContainer: (image: CGImage, bounds: CGRect)?] = [:]
    private var updateScheduled = false

    init(store: MapLabelStore) {
        self.store = store
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func attach(to mapView: MKMapView) {
        self.mapView = mapView
    }

    /// Another map, theme or style: the labels of the old one are gone.
    func reset() {
        for p in placed { p.layer.removeFromSuperlayer() }
        placed = []
        images = [:]
        tiles = []
        zoom = -1
        version = -1
    }

    /// Tiles were rendered, so there may be new labels. Coalesced: many tiles finish at about the same time.
    func setNeedsUpdate() {
        guard !updateScheduled else { return }
        updateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            updateScheduled = false
            if let mapView { update(on: mapView) }
        }
    }

    /// Puts the visible labels together again if the view moved to other tiles, and places them.
    func update(on mapView: MKMapView) {
        guard bounds.width > 0, bounds.height > 0, let z = store.currentZoom, z >= 0, z <= 21 else { return }
        let keys = TileKey.covering(mapView.visibleMapRect, zoom: z)
        let (labels, version) = store.labels(for: keys)
        if z != zoom || keys != tiles || version != self.version {
            zoom = z
            tiles = keys
            self.version = version
            rebuild(labels)
        }
        position(on: mapView)
    }

    /// mapsforge `LabelLayer`: of the labels of all visible tiles the clashing ones are dropped, the rest is drawn
    /// lowest priority first, so that the more important ones end up on top.
    private func rebuild(_ labels: [MapElementContainer]) {
        let scale = max(traitCollection.displayScale, 1)
        let ordered = collisionFreeOrdered(withoutDuplicateCaptions(labels)).sorted { $0.priority < $1.priority }
        var cache: [MapElementContainer: (image: CGImage, bounds: CGRect)?] = [:]
        var free = placed.map(\.layer)
        var next: [(label: MapElementContainer, bounds: CGRect, layer: CALayer)] = []
        next.reserveCapacity(ordered.count)
        for label in ordered {
            let rendered = images[label] ?? label.render(scale: scale)
            cache[label] = rendered
            guard let rendered else { continue }
            let layer = free.popLast() ?? makeLayer()
            layer.contents = rendered.image
            layer.contentsScale = scale
            layer.bounds = CGRect(origin: .zero, size: rendered.bounds.size)
            next.append((label, rendered.bounds, layer))
        }
        for layer in free { layer.removeFromSuperlayer() }
        placed = next
        images = cache
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayers = next.map(\.layer)
        CATransaction.commit()
    }

    private func makeLayer() -> CALayer {
        let layer = CALayer()
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.actions = ["position": NSNull(), "transform": NSNull(), "contents": NSNull(), "bounds": NSNull()]
        layer.isGeometryFlipped = false
        return layer
    }

    /// Moves every label to where its place on the map is now.
    private func position(on mapView: MKMapView) {
        guard !placed.isEmpty, let t = transform(on: mapView, zoom: zoom) else { return }
        // Scale and rotation of the map, without the shift: between two zoom levels the tiles are drawn
        // enlarged and the labels grow with them, and a turned map turns them – both as it was while they were
        // part of the tile. Letting a label keep its own direction is the next step.
        let turn = CATransform3DMakeAffineTransform(CGAffineTransform(a: t.a, b: t.b, c: t.c, d: t.d,
                                                                      tx: 0, ty: 0))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for p in placed {
            p.layer.position = CGPoint(x: p.bounds.midX, y: p.bounds.midY).applying(t)
            p.layer.transform = turn
        }
        CATransaction.commit()
    }

    /// Maps absolute Mapsforge pixels at `zoom` to points in this view. The linear part is taken from MapKit
    /// itself (three converted points), so that it also holds while the map is turned.
    private func transform(on mapView: MKMapView, zoom: Int) -> CGAffineTransform? {
        let rect = mapView.visibleMapRect
        guard rect.width > 0, zoom >= 0, zoom <= 21 else { return nil }
        let o = MKMapPoint(x: rect.midX, y: rect.midY)
        let d = rect.width / 8
        let p0 = mapView.convert(o.coordinate, toPointTo: self)
        let px = mapView.convert(MKMapPoint(x: o.x + d, y: o.y).coordinate, toPointTo: self)
        let py = mapView.convert(MKMapPoint(x: o.x, y: o.y + d).coordinate, toPointTo: self)
        let linear = CGAffineTransform(a: (px.x - p0.x) / d, b: (px.y - p0.y) / d,
                                       c: (py.x - p0.x) / d, d: (py.y - p0.y) / d,
                                       tx: p0.x, ty: p0.y)
        guard linear.a.isFinite, linear.b.isFinite, linear.c.isFinite, linear.d.isFinite,
              p0.x.isFinite, p0.y.isFinite else { return nil }
        // a pixel at `zoom` is `MKMapSize.world.width / (256 · 2^zoom)` map points wide
        let s = MKMapSize.world.width / Double(256 << zoom)
        return CGAffineTransform(scaleX: s, y: s)
            .concatenating(CGAffineTransform(translationX: -o.x, y: -o.y))
            .concatenating(linear)
    }
}
