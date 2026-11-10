// Port of org.mapsforge.map.layer.renderer.* (DatabaseRenderer, StandardRenderer,
// CanvasRasterer, PolylineContainer, TileDependencies) and rendertheme.RenderContext,
// drawing with CoreGraphics instead of android.graphics.
// Licensed under LGPL-3.0 like the original mapsforge code.

import CoreGraphics
import Foundation
import MapsforgeCore

// MARK: - Shapes

/// A way prepared for rendering in pixel coordinates (lazy, shared by all instructions).
final class PolylineContainer {
    let tags: [Tag]
    let layer: Int8
    let tile: Tile
    let isClosedWay: Bool
    private let way: Way?
    private var absolute: [[CGPoint]]?
    private var relative: [[CGPoint]]?
    private var center: CGPoint?

    init(way: Way, tile: Tile) {
        self.way = way
        self.tags = way.tags
        self.layer = way.layer
        self.tile = tile
        let ring = way.latLongs[0]
        let a = ring[0], b = ring[ring.count - 1]
        let d = ((a.latitude - b.latitude) * (a.latitude - b.latitude) + (a.longitude - b.longitude) * (a.longitude - b.longitude)).squareRoot()
        isClosedWay = d < 0.000000001
        if let lp = way.labelPosition {
            center = Self.pixel(lp, mapSize: tile.mapSize)
        }
    }

    /// Synthetic way from absolute pixel coordinates (used for the water background).
    init(absolute points: [CGPoint], tile: Tile, tags: [Tag]) {
        self.way = nil
        self.tags = tags
        self.layer = 0
        self.tile = tile
        self.absolute = [points]
        isClosedWay = points.first == points.last
    }

    @inline(__always)
    static func pixel(_ p: LatLong, mapSize: Int64) -> CGPoint {
        CGPoint(x: MercatorProjection.longitudeToPixelX(p.longitude, mapSize: mapSize),
                y: MercatorProjection.latitudeToPixelY(p.latitude, mapSize: mapSize))
    }

    var coordinatesAbsolute: [[CGPoint]] {
        if let absolute { return absolute }
        let ms = tile.mapSize
        let result = way!.latLongs.map { ring in ring.map { Self.pixel($0, mapSize: ms) } }
        absolute = result
        return result
    }

    var coordinatesRelativeToTile: [[CGPoint]] {
        if let relative { return relative }
        let o = tile.origin
        let result = coordinatesAbsolute.map { ring in ring.map { CGPoint(x: $0.x - o.x, y: $0.y - o.y) } }
        relative = result
        return result
    }

    var centerAbsolute: CGPoint {
        if let center { return center }
        let ring = coordinatesAbsolute[0]
        var minX = ring[0].x, maxX = ring[0].x, minY = ring[0].y, maxY = ring[0].y
        for p in ring {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let c = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        center = c
        return c
    }
}

enum PaintStyle { case fill, stroke }

struct ShapePaintContainer {
    enum Shape {
        case polyline(PolylineContainer)
        case circle(CGPoint, CGFloat)
    }
    let shape: Shape
    let paint: Paint
    let style: PaintStyle
    var dy: CGFloat = 0
    var cubic = false
}

// MARK: - Render context

/// Per-tile state while matching the theme (mapsforge `RenderContext`).
final class RenderContext {
    static let layers = 11

    let tile: Tile
    let theme: RenderTheme
    let strokeScale: CGFloat
    let textScale: CGFloat
    private let levels: Int
    private(set) var ways: [[ShapePaintContainer]]
    private var currentLayer = 0
    var labels: [MapElementContainer] = []

    init(tile: Tile, theme: RenderTheme, textScale: CGFloat = 1) {
        self.tile = tile
        self.theme = theme
        self.levels = max(theme.levels, 1)
        self.ways = Array(repeating: [], count: Self.layers * max(theme.levels, 1))
        strokeScale = CGFloat(pow(1.5, Double(max(tile.zoomLevel - 12, 0))) * theme.baseStrokeWidth)
        self.textScale = textScale * CGFloat(theme.baseTextSize)
    }

    func setDrawingLayer(_ layer: Int8) {
        currentLayer = min(max(Int(layer), 0), Self.layers - 1)
    }

    func addShape(level: Int, _ shape: ShapePaintContainer) {
        ways[currentLayer * levels + level].append(shape)
    }

    func addLabel(_ label: MapElementContainer) {
        labels.append(label)
    }

    func shapes(layer: Int, level: Int) -> [ShapePaintContainer] {
        ways[layer * levels + level]
    }

    var levelCount: Int { levels }

    func pixelAbsolute(_ p: LatLong) -> CGPoint {
        PolylineContainer.pixel(p, mapSize: tile.mapSize)
    }

    func pixelRelativeToTile(_ p: LatLong) -> CGPoint {
        let a = pixelAbsolute(p), o = tile.origin
        return CGPoint(x: a.x - o.x, y: a.y - o.y)
    }
}

// MARK: - Renderer

/// Renders mapsforge tiles into CGImages. Thread-safe; tiles may be rendered concurrently.
public final class TileRenderer: @unchecked Sendable {
    public let mapFile: MapFile
    public let theme: RenderTheme
    public var renderLabels = true
    private let dependencies = TileDependencies()

    public init(mapFile: MapFile, theme: RenderTheme) {
        self.mapFile = mapFile
        self.theme = theme
    }

    public struct Statistics: Sendable {
        public var readTime: TimeInterval = 0
        public var matchTime: TimeInterval = 0
        public var drawTime: TimeInterval = 0
        public var pois = 0
        public var ways = 0
        public var labels = 0
        public var total: TimeInterval { readTime + matchTime + drawTime }
        public init() {}
    }

    /// Renders `tile` (size in points = `tile.tileSize`) into a bitmap with `scale` pixels per point.
    public func renderTile(_ tile: Tile, scale: CGFloat = 1, statistics: UnsafeMutablePointer<Statistics>? = nil) -> CGImage? {
        let px = Int((CGFloat(tile.tileSize) * scale).rounded())
        guard let cg = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        // y-down coordinate system in points, like mapsforge/Android
        cg.translateBy(x: 0, y: CGFloat(px))
        cg.scaleBy(x: scale, y: -scale)
        cg.setShouldAntialias(true)
        render(tile, into: cg, statistics: statistics)
        return cg.makeImage()
    }

    /// Renders into an existing y-down context whose user space is `tile.tileSize` points wide.
    public func render(_ tile: Tile, into cg: CGContext, statistics: UnsafeMutablePointer<Statistics>? = nil) {
        let size = CGFloat(tile.tileSize)
        let tileRect = CGRect(x: 0, y: 0, width: size, height: size)

        if theme.mapBackgroundOutside != nil && !mapFile.supportsTile(tile) {
            cg.setFillColor(theme.mapBackgroundOutside!.cgColor)
            cg.fill(tileRect)
            return
        }

        var t0 = Date()
        let result = mapFile.readMapData(tile)
        statistics?.pointee.readTime = Date().timeIntervalSince(t0)
        statistics?.pointee.pois = result?.pointOfInterests.count ?? 0
        statistics?.pointee.ways = result?.ways.count ?? 0

        t0 = Date()
        let ctx = RenderContext(tile: tile, theme: theme)
        if let result {
            for poi in result.pointOfInterests {
                ctx.setDrawingLayer(poi.layer)
                for instruction in theme.instructions(forNode: poi.tags, zoom: tile.zoomLevel) {
                    instruction.renderNode(ctx, poi)
                }
            }
            for way in result.ways {
                let container = PolylineContainer(way: way, tile: tile)
                ctx.setDrawingLayer(container.layer)
                let closed: Closed = container.isClosedWay ? .yes : .no
                for instruction in theme.instructions(forWay: container.tags, zoom: tile.zoomLevel, closed: closed) {
                    instruction.renderWay(ctx, container)
                }
            }
            if result.isWater {
                renderWaterBackground(ctx)
            }
        }
        statistics?.pointee.matchTime = Date().timeIntervalSince(t0)

        t0 = Date()
        cg.setFillColor(theme.mapBackground.cgColor)
        cg.fill(tileRect)
        drawWays(ctx, cg)

        if renderLabels {
            let labels = dependencies.processLabels(ctx.labels, tile: tile)
            statistics?.pointee.labels = labels.count
            let origin = CGPoint(x: tile.origin.x, y: tile.origin.y)
            for label in labels.sorted(by: { $0.priority < $1.priority }) {
                label.draw(cg, origin: origin)
            }
        }

        if let outside = theme.mapBackgroundOutside {
            fillOutside(cg, tile: tile, color: outside)
        }
        statistics?.pointee.drawTime = Date().timeIntervalSince(t0)
    }

    private func renderWaterBackground(_ ctx: RenderContext) {
        ctx.setDrawingLayer(0)
        let o = ctx.tile.origin, s = Double(ctx.tile.tileSize)
        let pts = [CGPoint(x: o.x, y: o.y), CGPoint(x: o.x + s, y: o.y), CGPoint(x: o.x + s, y: o.y + s),
                   CGPoint(x: o.x, y: o.y + s), CGPoint(x: o.x, y: o.y)]
        let way = PolylineContainer(absolute: pts, tile: ctx.tile, tags: [Tag(key: "natural", value: "water")])
        for instruction in theme.instructions(forWay: way.tags, zoom: ctx.tile.zoomLevel, closed: .yes) {
            instruction.renderWay(ctx, way)
        }
    }

    // MARK: drawing (CanvasRasterer)

    private func drawWays(_ ctx: RenderContext, _ cg: CGContext) {
        let origin = CGPoint(x: ctx.tile.origin.x, y: ctx.tile.origin.y)
        for layer in 0..<RenderContext.layers {
            for level in 0..<ctx.levelCount {
                let list = ctx.shapes(layer: layer, level: level)
                for shape in list.reversed() {   // mapsforge draws each level back to front
                    draw(shape, cg, origin: origin)
                }
            }
        }
    }

    private func draw(_ s: ShapePaintContainer, _ cg: CGContext, origin: CGPoint) {
        guard s.paint.isVisible else { return }
        let path: CGPath
        switch s.shape {
        case .circle(let c, let r):
            path = CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil)
        case .polyline(let way):
            let p = CGMutablePath()
            for ring in way.coordinatesRelativeToTile {
                let pts = s.dy != 0 ? Geometry.parallelPath(ring, s.dy) : ring
                guard pts.count >= 2 else { continue }
                if s.cubic {
                    var p1 = pts[0], p2 = pts[0]
                    p.move(to: p1)
                    for i in 1..<pts.count {
                        let p3 = pts[i]
                        p2 = CGPoint(x: (p1.x + p3.x) / 2, y: (p1.y + p3.y) / 2)
                        p.addQuadCurve(to: p2, control: p1)
                        p1 = p3
                    }
                    p.addQuadCurve(to: pts[pts.count - 1], control: p2)
                } else {
                    p.addLines(between: pts)
                }
            }
            path = p
        }

        switch s.style {
        case .fill:
            if let shader = s.paint.shader {
                shader.fillPath(path, in: cg, origin: origin)
            } else {
                cg.addPath(path)
                cg.setFillColor(s.paint.color.cgColor)
                cg.fillPath(using: .evenOdd)
            }
        case .stroke:
            cg.saveGState()
            cg.addPath(path)
            cg.setLineWidth(s.paint.strokeWidth)
            cg.setLineCap(s.paint.cap)
            cg.setLineJoin(s.paint.join)
            if let dash = s.paint.dash, !dash.isEmpty {
                cg.setLineDash(phase: 0, lengths: dash)
            }
            if let shader = s.paint.shader {
                cg.replacePathWithStrokedPath()
                let stroked = cg.path ?? path
                cg.beginPath()
                shader.fillPath(stroked, in: cg, origin: origin)
            } else {
                cg.setStrokeColor(s.paint.color.cgColor)
                cg.strokePath()
            }
            cg.restoreGState()
        }
    }

    private func fillOutside(_ cg: CGContext, tile: Tile, color: ARGB) {
        let bbox = mapFile.boundingBox
        let ms = tile.mapSize, o = tile.origin, size = CGFloat(tile.tileSize)
        let left = MercatorProjection.longitudeToPixelX(bbox.minLongitude, mapSize: ms) - o.x
        let right = MercatorProjection.longitudeToPixelX(bbox.maxLongitude, mapSize: ms) - o.x
        let top = MercatorProjection.latitudeToPixelY(bbox.maxLatitude, mapSize: ms) - o.y
        let bottom = MercatorProjection.latitudeToPixelY(bbox.minLatitude, mapSize: ms) - o.y
        let inside = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        let tileRect = CGRect(x: 0, y: 0, width: size, height: size)
        guard !inside.contains(tileRect) else { return }
        cg.saveGState()
        cg.addRect(tileRect)
        cg.addRect(inside)
        cg.setFillColor(color.cgColor)
        cg.fillPath(using: .evenOdd)
        cg.restoreGState()
    }
}

// MARK: - Label dependencies between neighbouring tiles

extension MapElementContainer: Hashable {
    static func == (lhs: MapElementContainer, rhs: MapElementContainer) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// Port of mapsforge `TileDependencies` + `DatabaseRenderer.processLabels`: labels crossing tile
/// borders are drawn consistently on all affected tiles, independent of rendering order.
final class TileDependencies: @unchecked Sendable {
    /// overlapData[from][to] = elements of tile `from` that reach into tile `to`
    private var overlapData: [Tile: [Tile: Set<MapElementContainer>]] = [:]
    private var processed: Set<Tile> = []
    private let lock = NSLock()

    func processLabels(_ labels: [MapElementContainer], tile: Tile) -> [MapElementContainer] {
        lock.lock()
        defer { lock.unlock() }

        var current = labels
        var labelsToDraw = Set<MapElementContainer>()
        var remainingNeighbours: [Tile] = []
        var undrawable = Set<MapElementContainer>()

        for neighbour in Self.neighbours(of: tile) {
            if processed.contains(neighbour) {
                // elements the neighbour pushed into us, and ours it has already drawn
                labelsToDraw.formUnion(overlapData[neighbour]?[tile] ?? [])
                labelsToDraw.formUnion(overlapData[tile]?[neighbour] ?? [])
                let nb = Self.boundary(neighbour)
                for l in current where l.intersects(nb) { undrawable.insert(l) }
            } else {
                overlapData[neighbour] = nil
                remainingNeighbours.append(neighbour)
            }
        }
        current.removeAll { undrawable.contains($0) }

        var ordered = collisionFreeOrdered(current)
        ordered.removeAll { item in labelsToDraw.contains { $0.clashes(with: item) } }
        labelsToDraw.formUnion(ordered)

        for neighbour in remainingNeighbours {
            let nb = Self.boundary(neighbour)
            let reaching = labelsToDraw.filter { $0.intersects(nb) }
            var forTile = overlapData[tile] ?? [:]
            forTile[neighbour] = reaching.isEmpty ? nil : reaching
            overlapData[tile] = forTile
        }
        processed.insert(tile)
        return Array(labelsToDraw)
    }

    static func boundary(_ t: Tile) -> CGRect {
        CGRect(x: t.origin.x, y: t.origin.y, width: Double(t.tileSize), height: Double(t.tileSize))
    }

    static func neighbours(of t: Tile) -> [Tile] {
        let n = 1 << t.zoomLevel
        var result: [Tile] = []
        for dy in -1...1 {
            for dx in -1...1 where dx != 0 || dy != 0 {
                let y = t.tileY + dy
                guard y >= 0, y < n else { continue }
                let x = (t.tileX + dx + n) % n
                result.append(Tile(tileX: x, tileY: y, zoomLevel: t.zoomLevel, tileSize: t.tileSize))
            }
        }
        return result
    }
}
