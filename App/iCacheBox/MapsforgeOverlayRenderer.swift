import MapKit
import MapsforgeCore
import MapsforgeRender
import UIKit

/// Tile overlay that replaces Apple's base map. Its tiles are drawn by `MapsforgeOverlayRenderer`, not loaded
/// through `loadTile`: MapKit's `MKTileOverlayRenderer` leaves a tile empty (black) until it has been loaded, so
/// every zoom step flashed black squares.
final class MapsforgeTileOverlay: MKTileOverlay, @unchecked Sendable {
    let renderer: TileRenderer
    /// Tiles of the overlay this one replaces (other map, theme or style), shown until the own ones are rendered.
    /// Set on the main thread before the overlay is added; taken over by the renderer.
    var previousTiles: TileCache?

    init(renderer: TileRenderer) {
        self.renderer = renderer
        super.init(urlTemplate: nil)
        canReplaceMapContent = true
        minimumZ = 6
        maximumZ = 21
        tileSize = CGSize(width: 256, height: 256)
    }
}

/// A 256 pt tile in the slippy-map scheme, in MapKit map points.
struct TileKey: Hashable, Sendable {
    let x: Int
    let y: Int
    let z: Int

    /// Side of a tile at `zoom` in map points (`MKMapSize.world` is 2^28 wide).
    static func size(zoom: Int) -> Double { MKMapSize.world.width / Double(1 << zoom) }

    var mapRect: MKMapRect {
        let size = Self.size(zoom: z)
        return MKMapRect(x: Double(x) * size, y: Double(y) * size, width: size, height: size)
    }

    var tile: Tile { Tile(tileX: x, tileY: y, zoomLevel: z, tileSize: 256) }

    /// The tile `dz` levels further out that contains this one.
    func ancestor(_ dz: Int) -> TileKey { TileKey(x: x >> dz, y: y >> dz, z: z - dz) }

    /// The 4^dz tiles `dz` levels further in that make up this one.
    func descendants(_ dz: Int) -> [TileKey] {
        let n = 1 << dz
        var keys: [TileKey] = []
        keys.reserveCapacity(n * n)
        for dy in 0..<n {
            for dx in 0..<n { keys.append(TileKey(x: (x << dz) + dx, y: (y << dz) + dy, z: z + dz)) }
        }
        return keys
    }

    /// Tiles at `zoom` that overlap `rect` (edges that only touch are left out).
    static func covering(_ rect: MKMapRect, zoom: Int) -> [TileKey] {
        let n = 1 << zoom
        let size = size(zoom: zoom)
        let x0 = max(0, Int(floor(rect.minX / size + 1e-9)))
        let x1 = min(n - 1, Int(ceil(rect.maxX / size - 1e-9)) - 1)
        let y0 = max(0, Int(floor(rect.minY / size + 1e-9)))
        let y1 = min(n - 1, Int(ceil(rect.maxY / size - 1e-9)) - 1)
        guard x0 <= x1, y0 <= y1 else { return [] }
        var keys: [TileKey] = []
        keys.reserveCapacity((x1 - x0 + 1) * (y1 - y0 + 1))
        for y in y0...y1 {
            for x in x0...x1 { keys.append(TileKey(x: x, y: y, z: zoom)) }
        }
        return keys
    }
}

/// Least-recently-used map of tile images (not thread-safe).
private struct LRU {
    private struct Entry {
        let image: CGImage
        var used: UInt64
    }

    let capacity: Int
    private var entries: [TileKey: Entry] = [:]
    private var clock: UInt64 = 0

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    mutating func image(for key: TileKey) -> CGImage? {
        guard entries[key] != nil else { return nil }
        clock += 1
        entries[key]?.used = clock
        return entries[key]?.image
    }

    /// Inserts `image`; an image that is not `recent` is the first to go. Returns the images pushed out.
    mutating func insert(_ image: CGImage, for key: TileKey, recent: Bool = true) -> [(TileKey, CGImage)] {
        clock += 1
        entries[key] = Entry(image: image, used: recent ? clock : 0)
        var evicted: [(TileKey, CGImage)] = []
        while entries.count > capacity, let oldest = entries.min(by: { $0.value.used < $1.value.used }) {
            entries[oldest.key] = nil
            evicted.append((oldest.key, oldest.value.image))
        }
        return evicted
    }

    mutating func removeAll() { entries.removeAll() }
}

/// Rendered tiles in memory, least recently used dropped first (mapsforge `InMemoryTileCache`), in two tiers:
/// the newest tiles in full resolution, for MapKit to draw; tiles pushed out of it are kept at half the
/// resolution a while longer, only to stand in for missing tiles of another zoom level (shown enlarged or reduced
/// anyway). Thread-safe.
final class TileCache: @unchecked Sendable {
    private let lock = NSLock()
    private var full: LRU
    private var reduced: LRU

    init(fullCapacity: Int, reducedCapacity: Int) {
        full = LRU(capacity: fullCapacity)
        reduced = LRU(capacity: reducedCapacity)
    }

    /// MapKit draws 512 pt squares of 2 × 2 tiles, about twice the screen in tiles per zoom level. At @3x a tile
    /// takes 2.4 MB in full and 0.6 MB in half resolution, so an iPhone keeps up to about 75 + 75 MB.
    convenience init(screen: CGSize) {
        let columns = Int((screen.width / 256).rounded(.up)) + 1
        let rows = Int((screen.height / 256).rounded(.up)) + 1
        let full = max(32, 2 * columns * rows)
        self.init(fullCapacity: full, reducedCapacity: 4 * full)
    }

    /// The tile in full resolution.
    func image(for key: TileKey) -> CGImage? {
        lock.withLock { full.image(for: key) }
    }

    /// The tile in full or reduced resolution, to stand in for another one.
    func replacement(for key: TileKey) -> CGImage? {
        lock.withLock { full.image(for: key) ?? reduced.image(for: key) }
    }

    /// `recent` = false: rendered for a zoom level no longer on screen, the first to be reduced.
    func insert(_ image: CGImage, for key: TileKey, recent: Bool) {
        let evicted = lock.withLock { full.insert(image, for: key, recent: recent) }
        guard !evicted.isEmpty else { return }
        let copies = evicted.compactMap { key, image in Self.halfSize(image).map { (key, $0) } }
        lock.withLock {
            for (key, image) in copies { _ = reduced.insert(image, for: key) }
        }
    }

    func removeAll() {
        lock.withLock {
            full.removeAll()
            reduced.removeAll()
        }
    }

    private static func halfSize(_ image: CGImage) -> CGImage? {
        let width = image.width / 2
        let height = image.height / 2
        guard width > 0, height > 0,
              let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                    | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        cg.interpolationQuality = .high
        cg.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return cg.makeImage()
    }
}

/// Draws the Mapsforge tiles of a `MapsforgeTileOverlay` (Cachebox `MapViewBase` with mapsforge's tile cache):
/// a tile reaches the screen only once it has been rendered. Until then the matching part of a cached tile of
/// another zoom level is drawn in its place, scaled up or down – so zooming shows the old map enlarged or reduced
/// instead of empty squares. Missing tiles are rendered in the background, newest request first, and then
/// MapKit is asked to draw that spot again.
///
/// MapKit calls `draw` on several background threads at once; all state is behind `lock`.
final class MapsforgeOverlayRenderer: MKOverlayRenderer, @unchecked Sendable {
    let cache: TileCache
    private let tileRenderer: TileRenderer
    private let minimumZ: Int
    private let maximumZ: Int
    /// Fills the parts of a tile for which nothing at all has been rendered yet.
    private let background: CGColor

    private let lock = NSLock()
    /// Tiles of the replaced overlay; dropped once all requested tiles of this one are rendered.
    private var previous: TileCache?
    /// Tiles waiting to be rendered with the zoom scales MapKit asked for them (to redraw exactly those).
    private var pending: [TileKey: Set<MKZoomScale>] = [:]
    /// Waiting tiles in request order, newest last: the newest are rendered first, so after a quick zoom the
    /// tiles of the level now on screen come before those of the levels passed on the way.
    private var order: [TileKey] = []
    private var rendering: [TileKey: Set<MKZoomScale>] = [:]
    private var workers = 0
    private var isCancelled = false
    /// Zoom level of the latest `draw`: tiles of other levels were passed on the way (quick zoom).
    private var currentZoom = 0
    private let maxWorkers = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
    private static let queue = DispatchQueue(label: "mapsforge.render", qos: .userInitiated, attributes: .concurrent)
    private var memoryWarning: NSObjectProtocol?

    init(overlay: MapsforgeTileOverlay, cache: TileCache) {
        self.cache = cache
        tileRenderer = overlay.renderer
        minimumZ = overlay.minimumZ
        maximumZ = overlay.maximumZ
        background = overlay.renderer.theme.mapBackground.cgColor
        previous = overlay.previousTiles
        overlay.previousTiles = nil
        super.init(overlay: overlay)
        memoryWarning = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            cache.removeAll()
            lock.withLock { previous = nil }
        }
    }

    deinit {
        if let memoryWarning { NotificationCenter.default.removeObserver(memoryWarning) }
    }

    /// The overlay was removed: render nothing more (tiles already being rendered still finish).
    func cancel() {
        lock.withLock {
            isCancelled = true
            pending.removeAll()
            order.removeAll()
        }
    }

    // MARK: Drawing

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        // at zoom z a 256 pt tile covers 2^(28 − z) map points, so zoomScale (points per map point) is 2^(z − 20)
        let zoom = Int((20 + log2(Double(zoomScale))).rounded())
        let z = min(zoom, maximumZ)   // further in: the most detailed tiles, enlarged
        let previous = lock.withLock {
            currentZoom = z
            return self.previous
        }
        context.interpolationQuality = .medium
        for key in TileKey.covering(mapRect, zoom: max(0, z)) {
            if let image = cache.image(for: key) {
                draw(image, at: key, in: context)
                continue
            }
            if z >= minimumZ { request(key, zoomScale: zoomScale) }
            drawReplacement(for: key, previous: previous, in: context)
        }
    }

    /// Stands in for a tile that is not rendered yet: the same tile in reduced resolution or from the replaced
    /// overlay; otherwise the nearest cached tile further out (enlarged), with cached tiles up to three levels
    /// further in (reduced) on top; where none of them exists, the background colour of the theme.
    private func drawReplacement(for key: TileKey, previous: TileCache?, in context: CGContext) {
        if let image = cache.replacement(for: key) ?? previous?.replacement(for: key) {
            draw(image, at: key, in: context)
            return
        }
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: rect(for: key.mapRect))
        var covered = false
        for dz in stride(from: 1, through: key.z - minimumZ, by: 1) {
            let parent = key.ancestor(dz)
            if let image = cache.replacement(for: parent) ?? previous?.replacement(for: parent) {
                draw(image, at: parent, in: context)
                covered = true
                break
            }
        }
        if !covered {
            context.setFillColor(background)
            context.fill(rect(for: key.mapRect))
        }
        // the finer level last: it is the closer one to the requested level
        for dz in [3, 2, 1] where key.z + dz <= maximumZ {
            for child in key.descendants(dz) {
                if let image = cache.replacement(for: child) { draw(image, at: child, in: context) }
            }
        }
    }

    /// The context of `draw` is y-down (UIKit), a CGImage is drawn y-up.
    private func draw(_ image: CGImage, at key: TileKey, in context: CGContext) {
        let r = rect(for: key.mapRect)
        context.saveGState()
        context.translateBy(x: r.minX, y: r.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: r.size))
        context.restoreGState()
    }

    // MARK: Rendering

    private func request(_ key: TileKey, zoomScale: MKZoomScale) {
        let startWorker: Bool = lock.withLock {
            guard !isCancelled else { return false }
            if rendering[key] != nil {
                rendering[key]?.insert(zoomScale)
                return false
            }
            if pending[key] != nil {
                // asked again: it is (still) on screen, so it moves to the front
                pending[key]?.insert(zoomScale)
                if let i = order.lastIndex(of: key) { order.remove(at: i) }
                order.append(key)
                return false
            }
            pending[key] = [zoomScale]
            order.append(key)
            guard workers < maxWorkers else { return false }
            workers += 1
            return true
        }
        if startWorker { Self.queue.async { self.work() } }
    }

    private func work() {
        while let key = next() {
            let scale = contentScaleFactor > 0 ? contentScaleFactor : 2
            finish(key, image: tileRenderer.renderTile(key.tile, scale: scale))
        }
    }

    private func next() -> TileKey? {
        lock.withLock {
            while let key = order.popLast() {
                if let scales = pending.removeValue(forKey: key) {
                    rendering[key] = scales
                    return key
                }
            }
            workers -= 1
            return nil
        }
    }

    private func finish(_ key: TileKey, image: CGImage?) {
        let (cancelled, recent) = lock.withLock { (isCancelled, key.z == currentZoom) }
        // into the cache before it leaves `rendering`, or a `draw` in between would request it again
        if let image, !cancelled { cache.insert(image, for: key, recent: recent) }
        let scales: Set<MKZoomScale> = lock.withLock {
            let scales = rendering.removeValue(forKey: key) ?? []
            if pending.isEmpty, rendering.isEmpty { previous = nil }
            return scales
        }
        // without an image the replacement stays; redrawing would only ask for the tile again
        guard image != nil else { return }
        DispatchQueue.main.async {
            for zoomScale in scales { self.setNeedsDisplay(key.mapRect, zoomScale: zoomScale) }
        }
    }
}
