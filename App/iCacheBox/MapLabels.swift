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

    /// Counted up with every change; the label layer reads it to see whether it has to put its set together again.
    var currentVersion: Int { lock.withLock { version } }

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

    /// How many of `keys` have been rendered already (a tile without any label counts too).
    func coverage(for keys: [TileKey]) -> Int {
        lock.withLock { keys.reduce(0) { $0 + (tiles[$1] != nil ? 1 : 0) } }
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

/// A label drawn into an image. Handed from the drawing queue to the main thread; `CGImage` is only read after
/// it has been made.
private struct RenderedLabel: @unchecked Sendable {
    let image: CGImage
    /// Which way round the text was drawn, so that it can be drawn again when the map turns far enough.
    let inverted: Bool
}

/// Which set of labels the drawing queue is working for. Read on the queue, counted up on the main thread: a job
/// of an older set stops instead of drawing images nobody wants any more.
private final class LabelGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var current: Int { lock.withLock { value } }
    func next() -> Int { lock.withLock { value &+= 1; return value } }
}

/// Draws the labels of the visible tiles above the map (mapsforge `LabelLayer`): the tiles are rendered without
/// them, so which label is drawn is decided over all visible tiles at once instead of tile by tile
/// (`TileDependencies` is not needed then). Every label is rendered into an image once and shown by a `CALayer`
/// of its own, so that moving the map only moves layers instead of drawing text again.
///
/// While the map is turned, the names of towns, districts and points keep their direction and stay readable
/// (Cachebox does this in its old vector renderer, `TileGL_RotateDrawables`); names of ways turn with the map,
/// but are drawn the other way round as soon as they would be upside down (`MapElementContainer.inverts(at:)`).
/// Which labels fit next to each other is decided for the screen, not for the map pointing north, so the set is
/// put together again whenever the map has turned a little further.
///
/// The images themselves are drawn on a queue of its own: a label reaches the screen a frame or two after its
/// place, but a turn or a new tile never holds up the main thread with text rendering.
@MainActor
final class MapLabelsView: UIView {
    private let store: MapLabelStore
    private weak var mapView: MKMapView?
    /// Zoom level, tiles and store version the current set of labels was put together for.
    private var zoom = -1
    private var tiles: [TileKey] = []
    private var storeVersion = -1
    /// Labels of those tiles, without the doubles two tiles worked out for the same thing; the collision check
    /// picks from these, so a turn of the map does not need the list again.
    private var candidates: [MapElementContainer] = []
    /// Turn of the map the current set was picked for (radians).
    private var builtRotation: CGFloat = 0
    private var placed: [Placed] = []
    private var layers: [MapElementContainer: CALayer] = [:]
    /// Images of the labels on the screen; one that is dropped loses its image and is drawn again if it returns.
    private var images: [MapElementContainer: RenderedLabel] = [:]
    private let generation = LabelGeneration()
    private var updateScheduled = false
    /// Everything the map draws is shown this much bigger (`MapScale`). The labels grow with the map by
    /// themselves – their place comes from the transformation, which carries the factor – but their images have
    /// to be drawn with as many pixels more, or a name would be as blurred as a stretched picture.
    var mapScale: CGFloat = 1

    /// From this much turn on the labels are picked again (about 2°): their boxes have moved against each other,
    /// so other ones fit now – and a name along a way may have to be drawn the other way round.
    private static let rebuildTurn: CGFloat = 0.035
    /// Strip at the edge of the view whose tiles the layer does not wait for while zooming.
    private static let edge: CGFloat = 32
    /// Labels are drawn here, one after the other, most important last.
    private static let drawQueue = DispatchQueue(label: "de.cachebox.icachebox.labels", qos: .userInitiated)

    /// A label on the screen: its image covers `bounds` of the absolute pixel plane around `label.anchor`.
    private struct Placed {
        let label: MapElementContainer
        let bounds: CGRect
        let layer: CALayer
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
        _ = generation.next()
        for p in placed { p.layer.removeFromSuperlayer() }
        placed = []
        layers = [:]
        images = [:]
        candidates = []
        tiles = []
        zoom = -1
        storeVersion = -1
        builtRotation = 0
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

    /// Puts the visible labels together again if the view moved, turned or got new tiles, and places them.
    func update(on mapView: MKMapView) {
        guard bounds.width > 0, bounds.height > 0, let z = store.currentZoom, z >= 0, z <= 21 else { return }
        let keys = TileKey.covering(mapView.visibleMapRect, zoom: z)
        guard let t = transform(on: mapView, zoom: z) else { return }
        // While zooming the new level has nothing rendered yet. The overlay shows the tiles of the old level
        // enlarged or reduced until then, so the labels of that level stay with them: they are placed in its
        // pixels and scale along with its tiles, instead of the screen going bare.
        if z != zoom, zoom >= 0, abs(z - zoom) <= 3, !placed.isEmpty {
            let wanted = onScreen(keys, transform: t)
            if store.coverage(for: wanted) < wanted.count {
                if let old = transform(on: mapView, zoom: zoom) { place(with: old) }
                return
            }
        }
        // the turn of the map, taken from the transformation itself
        let turn = atan2(t.b, t.a)
        var rebuildNeeded = false
        // the store's version, not the layer's own: a tile that finished rendering brings new labels for tiles
        // the layer already knows about
        if z != zoom || keys != tiles || storeVersion != store.currentVersion {
            let (labels, version) = store.labels(for: keys)
            zoom = z
            tiles = keys
            storeVersion = version
            candidates = withoutDuplicateCaptions(labels)
            rebuildNeeded = true
        }
        if abs(remainder(turn - builtRotation, 2 * .pi)) > Self.rebuildTurn { rebuildNeeded = true }
        if rebuildNeeded {
            builtRotation = turn
            rebuild(candidates, rotation: turn)
        }
        place(with: t)
    }

    /// mapsforge `LabelLayer`: of the labels of all visible tiles the clashing ones are dropped, the rest is drawn
    /// lowest priority first, so that the more important ones end up on top. The order is set through `zPosition`,
    /// so that a new set only adds and removes layers instead of sorting them all again.
    private func rebuild(_ labels: [MapElementContainer], rotation: CGFloat) {
        let scale = max(traitCollection.displayScale, 1) * max(mapScale, 1)
        let ordered = collisionFreeOrdered(labels, rotation: rotation).sorted { $0.priority < $1.priority }
        let token = generation.next()
        var nextLayers: [MapElementContainer: CALayer] = [:]
        var nextImages: [MapElementContainer: RenderedLabel] = [:]
        var next: [Placed] = []
        var missing: [MapElementContainer] = []
        next.reserveCapacity(ordered.count)
        nextLayers.reserveCapacity(ordered.count)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, label) in ordered.enumerated() {
            let bounds = label.imageBounds
            guard bounds.width > 0, bounds.height > 0 else { continue }
            let layer: CALayer
            if let known = layers[label] {
                layer = known
            } else {
                layer = makeLayer()
                self.layer.addSublayer(layer)
            }
            layer.zPosition = CGFloat(i)
            layer.contentsScale = scale
            layer.bounds = CGRect(origin: .zero, size: bounds.size)
            if let cached = images[label] {
                // the image that is there stays until the new one is drawn, so nothing blinks at a turn
                layer.contents = cached.image
                nextImages[label] = cached
                if cached.inverted != label.inverts(at: rotation) { missing.append(label) }
            } else {
                layer.contents = nil
                missing.append(label)
            }
            nextLayers[label] = layer
            next.append(Placed(label: label, bounds: bounds, layer: layer))
        }
        for (label, layer) in layers where nextLayers[label] == nil { layer.removeFromSuperlayer() }
        CATransaction.commit()

        layers = nextLayers
        images = nextImages
        placed = next
        // most important first: the queue works through the list in order, and a label that wins collisions
        // is the one the eye misses while the rest is still being drawn
        draw(Array(missing.reversed()), scale: scale, rotation: rotation, generation: token)
    }

    /// Draws the images that are not there yet, away from the main thread, and hands them over in small batches.
    private func draw(_ labels: [MapElementContainer], scale: CGFloat, rotation: CGFloat, generation: Int) {
        guard !labels.isEmpty else { return }
        let box = self.generation
        let deliver: @MainActor @Sendable ([(MapElementContainer, RenderedLabel)]) -> Void = { [weak self] done in
            self?.show(done, generation: generation)
        }
        Self.drawQueue.async {
            var batch: [(MapElementContainer, RenderedLabel)] = []
            func hand(over done: [(MapElementContainer, RenderedLabel)]) {
                guard !done.isEmpty else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { deliver(done) } }
            }
            for label in labels {
                // another set of labels is wanted by now, so this one is not drawn any further
                guard box.current == generation else { return }
                if let drawn = label.render(scale: scale, rotation: rotation) {
                    batch.append((label, RenderedLabel(image: drawn.image, inverted: label.inverts(at: rotation))))
                }
                if batch.count >= 16 {
                    hand(over: batch)
                    batch.removeAll(keepingCapacity: true)
                }
            }
            hand(over: batch)
        }
    }

    /// Shows images the drawing queue finished. Their place is already set, so only the picture is put in.
    private func show(_ drawn: [(MapElementContainer, RenderedLabel)], generation: Int) {
        guard generation == self.generation.current else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (label, rendered) in drawn {
            images[label] = rendered
            layers[label]?.contents = rendered.image
        }
        CATransaction.commit()
    }

    private func makeLayer() -> CALayer {
        let layer = CALayer()
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.actions = ["position": NSNull(), "transform": NSNull(), "contents": NSNull(),
                         "bounds": NSNull(), "zPosition": NSNull()]
        return layer
    }

    /// Moves every label to where its place on the map is now. A label that turns with the map gets the whole
    /// scale and turn of the map; one that keeps its direction gets the scale alone, and its box is put around
    /// the anchor point in the direction of the screen, so that a name stays above its symbol.
    private func place(with t: CGAffineTransform) {
        guard !placed.isEmpty else { return }
        // between two zoom levels the tiles are drawn enlarged; the labels grow with them, as they did inside
        let scale = (abs(t.a * t.d - t.b * t.c)).squareRoot()
        let withMap = CGAffineTransform(a: t.a, b: t.b, c: t.c, d: t.d, tx: 0, ty: 0)
        let upright = CGAffineTransform(scaleX: scale, y: scale)
        let withMap3D = CATransform3DMakeAffineTransform(withMap)
        let upright3D = CATransform3DMakeScale(scale, scale, 1)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for p in placed {
            let anchor = p.label.anchor
            let offset = CGPoint(x: p.bounds.midX - anchor.x, y: p.bounds.midY - anchor.y)
                .applying(p.label.rotatesWithMap ? withMap : upright)
            let onScreen = anchor.applying(t)
            p.layer.position = CGPoint(x: onScreen.x + offset.x, y: onScreen.y + offset.y)
            p.layer.transform = p.label.rotatesWithMap ? withMap3D : upright3D
        }
        CATransaction.commit()
    }

    /// Of `keys`, the ones that really lie on the screen. `TileKey.covering` works on `visibleMapRect`, the
    /// upright rectangle around the view – while the map is turned its corners hold tiles MapKit never draws,
    /// which would never be rendered and so never arrive. The labels are still collected from all of `keys`,
    /// but only these are waited for.
    ///
    /// A tile that only reaches `edge` points into the view is left out as well: MapKit does not always draw
    /// such a sliver either, and its labels are hardly ever on the screen.
    private func onScreen(_ keys: [TileKey], transform t: CGAffineTransform) -> [TileKey] {
        let screen = bounds.insetBy(dx: Self.edge, dy: Self.edge)
        guard screen.width > 0, screen.height > 0 else { return keys }
        return keys.filter { key in
            let x = CGFloat(key.x) * 256, y = CGFloat(key.y) * 256
            let quad = [CGPoint(x: x, y: y), CGPoint(x: x + 256, y: y),
                        CGPoint(x: x + 256, y: y + 256), CGPoint(x: x, y: y + 256)].map { $0.applying(t) }
            return Self.intersects(quad, screen)
        }
    }

    /// Whether a convex quadrangle and an upright rectangle have a point in common (separating axis theorem:
    /// they are apart exactly if one of the four edge directions tells them apart).
    private static func intersects(_ quad: [CGPoint], _ rect: CGRect) -> Bool {
        guard let left = quad.map(\.x).min(), let right = quad.map(\.x).max(),
              let top = quad.map(\.y).min(), let bottom = quad.map(\.y).max() else { return false }
        if right < rect.minX || left > rect.maxX || bottom < rect.minY || top > rect.maxY { return false }
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
        for i in 0..<2 {
            let a = quad[i], b = quad[i + 1]
            let axis = CGPoint(x: a.y - b.y, y: b.x - a.x)
            var low = CGFloat.infinity, high = -CGFloat.infinity
            for p in quad {
                let d = p.x * axis.x + p.y * axis.y
                low = min(low, d)
                high = max(high, d)
            }
            var rectLow = CGFloat.infinity, rectHigh = -CGFloat.infinity
            for p in corners {
                let d = p.x * axis.x + p.y * axis.y
                rectLow = min(rectLow, d)
                rectHigh = max(rectHigh, d)
            }
            if high < rectLow || rectHigh < low { return false }
        }
        return true
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
