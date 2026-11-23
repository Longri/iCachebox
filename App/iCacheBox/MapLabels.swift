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
/// While the map is turned, the names of towns, districts and points keep their direction and stay readable
/// (Cachebox does this in its old vector renderer, `TileGL_RotateDrawables`); names of ways turn with the map,
/// but are drawn the other way round as soon as they would be upside down (`MapElementContainer.inverts(at:)`),
/// which needs their image again – that happens only when the turn passes the right angle to the way.
@MainActor
final class MapLabelsView: UIView {
    private let store: MapLabelStore
    private weak var mapView: MKMapView?
    /// Zoom level, tiles and store version the current set of labels was put together for.
    private var zoom = -1
    private var tiles: [TileKey] = []
    private var version = -1
    /// Turn of the map the labels were last drawn for (radians); a new one may turn texts round.
    private var rotation: CGFloat = 0
    private var placed: [Placed] = []
    /// Rendered labels of the current set, `nil` for a label with nothing to draw.
    private var images: [MapElementContainer: Rendered?] = [:]
    private var updateScheduled = false

    /// A label on the screen: its image covers `bounds` of the absolute pixel plane around `label.anchor`.
    private struct Placed {
        let label: MapElementContainer
        var bounds: CGRect
        var inverted: Bool
        let layer: CALayer
    }

    private struct Rendered {
        let image: CGImage
        let bounds: CGRect
        /// Which way round the text was drawn, so that it can be drawn again when the map turns far enough.
        let inverted: Bool
    }

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
        rotation = 0
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
        guard bounds.width > 0, bounds.height > 0, let z = store.currentZoom, z >= 0, z <= 21,
              let t = transform(on: mapView, zoom: z) else { return }
        // the turn of the map, taken from the transformation itself
        let turn = atan2(t.b, t.a)
        let keys = TileKey.covering(mapView.visibleMapRect, zoom: z)
        let (labels, version) = store.labels(for: keys)
        if z != zoom || keys != tiles || version != self.version {
            zoom = z
            tiles = keys
            self.version = version
            rotation = turn
            rebuild(labels, rotation: turn)
        }
        place(with: t, rotation: turn)
    }

    /// mapsforge `LabelLayer`: of the labels of all visible tiles the clashing ones are dropped, the rest is drawn
    /// lowest priority first, so that the more important ones end up on top.
    private func rebuild(_ labels: [MapElementContainer], rotation: CGFloat) {
        let scale = max(traitCollection.displayScale, 1)
        let ordered = collisionFreeOrdered(withoutDuplicateCaptions(labels)).sorted { $0.priority < $1.priority }
        var cache: [MapElementContainer: Rendered?] = [:]
        var free = placed.map(\.layer)
        var next: [Placed] = []
        next.reserveCapacity(ordered.count)
        for label in ordered {
            let rendered = image(of: label, scale: scale, rotation: rotation, cache: images[label] ?? nil)
            cache[label] = rendered
            guard let rendered else { continue }
            let layer = free.popLast() ?? makeLayer()
            layer.contents = rendered.image
            layer.contentsScale = scale
            layer.bounds = CGRect(origin: .zero, size: rendered.bounds.size)
            next.append(Placed(label: label, bounds: rendered.bounds, inverted: rendered.inverted, layer: layer))
        }
        for layer in free { layer.removeFromSuperlayer() }
        placed = next
        images = cache
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayers = next.map(\.layer)
        CATransaction.commit()
    }

    /// The image of a label at this turn of the map; the one already drawn is kept while the text still reads
    /// the same way round.
    private func image(of label: MapElementContainer, scale: CGFloat, rotation: CGFloat,
                       cache: Rendered?) -> Rendered? {
        let inverted = label.inverts(at: rotation)
        if let cache, cache.inverted == inverted { return cache }
        guard let drawn = label.render(scale: scale, rotation: rotation) else { return nil }
        return Rendered(image: drawn.image, bounds: drawn.bounds, inverted: inverted)
    }

    private func makeLayer() -> CALayer {
        let layer = CALayer()
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.actions = ["position": NSNull(), "transform": NSNull(), "contents": NSNull(), "bounds": NSNull()]
        return layer
    }

    /// Moves every label to where its place on the map is now. A label that turns with the map gets the whole
    /// scale and turn of the map; one that keeps its direction gets the scale alone, and its box is put around
    /// the anchor point in the direction of the screen, so that a name stays above its symbol.
    private func place(with t: CGAffineTransform, rotation turn: CGFloat) {
        guard !placed.isEmpty else { return }
        // between two zoom levels the tiles are drawn enlarged; the labels grow with them, as they did inside
        let scale = (abs(t.a * t.d - t.b * t.c)).squareRoot()
        let withMap = CGAffineTransform(a: t.a, b: t.b, c: t.c, d: t.d, tx: 0, ty: 0)
        let upright = CGAffineTransform(scaleX: scale, y: scale)
        let withMap3D = CATransform3DMakeAffineTransform(withMap)
        let upright3D = CATransform3DMakeScale(scale, scale, 1)
        // only when the map really turned can a text have to be drawn the other way round
        let turned = abs(turn - rotation) > 0.0005
        if turned { rotation = turn }
        let displayScale = max(traitCollection.displayScale, 1)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for i in placed.indices {
            let label = placed[i].label
            if turned, label.rotatesWithMap, label.inverts(at: turn) != placed[i].inverted,
               let rendered = image(of: label, scale: displayScale, rotation: turn, cache: nil) {
                images[label] = rendered
                placed[i].bounds = rendered.bounds
                placed[i].inverted = rendered.inverted
                placed[i].layer.contents = rendered.image
                placed[i].layer.bounds = CGRect(origin: .zero, size: rendered.bounds.size)
            }
            let p = placed[i]
            let anchor = label.anchor
            let offset = CGPoint(x: p.bounds.midX - anchor.x, y: p.bounds.midY - anchor.y)
                .applying(label.rotatesWithMap ? withMap : upright)
            let onScreen = anchor.applying(t)
            p.layer.position = CGPoint(x: onScreen.x + offset.x, y: onScreen.y + offset.y)
            p.layer.transform = label.rotatesWithMap ? withMap3D : upright3D
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
