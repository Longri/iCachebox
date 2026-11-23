// Port of org.mapsforge.core.mapelements.* (MapElementContainer, PointTextContainer,
// SymbolContainer, WayTextContainer), WayDecorator and LayerUtil.collisionFreeOrdered.
// Licensed under LGPL-3.0 like the original mapsforge code.

import CoreGraphics
import CoreText
import Foundation
import MapsforgeCore

/// A label or symbol placed in absolute map pixel coordinates.
///
/// Public because the app can keep the labels out of the tile images and draw them in a layer of its own
/// (mapsforge `TileBasedLabelStore` + `LabelLayer`): an element is only read after it has been created, so it
/// can be handed from the rendering threads to that layer.
public class MapElementContainer: @unchecked Sendable {
    let xy: CGPoint
    let display: Display
    public let priority: Int
    /// Boundary in absolute pixel coordinates (used for collision detection).
    public internal(set) var boundaryAbsolute: CGRect = .null

    init(xy: CGPoint, display: Display, priority: Int) {
        self.xy = xy
        self.display = display
        self.priority = priority
    }

    func clashes(with other: MapElementContainer) -> Bool {
        if display == .always || other.display == .always { return false }
        return boundaryAbsolute.intersects(other.boundaryAbsolute)
    }

    public func intersects(_ rect: CGRect) -> Bool { boundaryAbsolute.intersects(rect) }

    /// Draws the element into a y-down context whose origin lies at the absolute pixel `origin`.
    public func draw(_ cg: CGContext, origin: CGPoint) {}

    /// Text of a caption, to find the labels two tiles made for the same thing; `nil` for symbols and for text
    /// along a way, which may well repeat.
    public var captionText: String? { nil }
}

public extension MapElementContainer {
    /// Draws the label on its own into an image, for a label layer that places it on the screen itself. The
    /// returned rect is the part of the absolute pixel plane the image covers; `margin` leaves room for the halo
    /// around the text, which reaches beyond the boundary used for collision detection.
    func render(scale: CGFloat, margin: CGFloat = 6) -> (image: CGImage, bounds: CGRect)? {
        let bounds = boundaryAbsolute.insetBy(dx: -margin, dy: -margin)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let px = Int((bounds.width * scale).rounded()), py = Int((bounds.height * scale).rounded())
        guard px > 0, py > 0, px * py <= 16_000_000,
              let cg = CGContext(data: nil, width: px, height: py, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                    | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        // y-down coordinate system in points, like `TileRenderer.renderTile`
        cg.translateBy(x: 0, y: CGFloat(py))
        cg.scaleBy(x: scale, y: -scale)
        cg.setShouldAntialias(true)
        draw(cg, origin: bounds.origin)
        guard let image = cg.makeImage() else { return nil }
        return (image, bounds)
    }
}

final class PointTextContainer: MapElementContainer, @unchecked Sendable {
    public override var captionText: String? { text }
    let text: String
    let paint: TextPaint
    let position: Position
    let maxTextWidth: CGFloat
    private let layout: TextLayout

    init(point: CGPoint, display: Display, priority: Int, text: String, paint: TextPaint, position: Position,
         maxTextWidth: CGFloat) {
        self.text = text
        self.paint = paint
        self.position = position
        self.maxTextWidth = maxTextWidth
        self.layout = TextLayout(text: text, paint: paint, maxWidth: maxTextWidth)
        super.init(xy: point, display: display, priority: priority)
        let w = layout.size.width, h = layout.size.height
        let b: CGRect
        switch position {
        case .below: b = CGRect(x: -w / 2, y: 0, width: w, height: h)
        case .belowLeft: b = CGRect(x: -w, y: 0, width: w, height: h)
        case .belowRight: b = CGRect(x: 0, y: 0, width: w, height: h)
        case .above: b = CGRect(x: -w / 2, y: -h, width: w, height: h)
        case .aboveLeft: b = CGRect(x: -w, y: -h, width: w, height: h)
        case .aboveRight: b = CGRect(x: 0, y: -h, width: w, height: h)
        case .left: b = CGRect(x: -w, y: -h / 2, width: w, height: h)
        case .right: b = CGRect(x: 0, y: -h / 2, width: w, height: h)
        default: b = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        }
        boundaryAbsolute = b.offsetBy(dx: point.x, dy: point.y)
    }

    public override func draw(_ cg: CGContext, origin: CGPoint) {
        let topLeft = CGPoint(x: boundaryAbsolute.minX - origin.x, y: boundaryAbsolute.minY - origin.y)
        let alignment: CTTextAlignment = position.isLeft ? .right : (position.isRight ? .left : .center)
        layout.draw(in: cg, topLeft: topLeft, alignment: alignment)
    }
}

final class SymbolContainer: MapElementContainer, @unchecked Sendable {
    let bitmap: ThemeBitmap
    let theta: CGFloat
    let boundary: CGRect

    init(point: CGPoint, display: Display, priority: Int, boundary: CGRect?, bitmap: ThemeBitmap, theta: CGFloat) {
        self.bitmap = bitmap
        self.theta = theta
        self.boundary = boundary ?? CGRect(x: -bitmap.size.width / 2, y: -bitmap.size.height / 2,
                                           width: bitmap.size.width, height: bitmap.size.height)
        super.init(xy: point, display: display, priority: priority)
        boundaryAbsolute = self.boundary.offsetBy(dx: point.x, dy: point.y)
    }

    public override func draw(_ cg: CGContext, origin: CGPoint) {
        cg.saveGState()
        cg.translateBy(x: xy.x - origin.x, y: xy.y - origin.y)
        if theta != 0 { cg.rotate(by: theta) }
        bitmap.draw(in: cg, rect: CGRect(origin: boundary.origin, size: bitmap.size))
        cg.restoreGState()
    }
}

final class WayTextContainer: MapElementContainer, @unchecked Sendable {
    let text: String
    let paint: TextPaint
    let points: [CGPoint]
    let orientation: Orientation

    init(points: [CGPoint], display: Display, priority: Int, text: String, paint: TextPaint, textHeight: CGFloat,
         orientation: Orientation) {
        self.text = text
        self.paint = paint
        self.points = points
        self.orientation = orientation
        super.init(xy: points[0], display: display, priority: priority)
        var r = CGRect.null
        for p in points { r = r.union(CGRect(origin: p, size: .zero)) }
        boundaryAbsolute = r.insetBy(dx: -textHeight / 2, dy: -textHeight / 2)
    }

    public override func draw(_ cg: CGContext, origin: CGPoint) {
        let first = points[0], second = points[1]
        let invert: Bool
        switch orientation {
        case .autoDown: invert = second.x > first.x
        case .right: invert = false
        case .left: invert = true
        default: invert = second.x <= first.x
        }
        var path = points.map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) }
        if invert { path.reverse() }
        TextRenderer.drawText(text, alongPath: path, paint: paint, in: cg)
    }
}

/// Drops captions that say the same thing at nearly the same place, before the collision check.
///
/// Not in mapsforge: a way that crosses a tile border is in the data of both tiles, and each tile works out a
/// caption of its own for it, a few pixels apart. While the labels were drawn into the tiles, `TileDependencies`
/// dropped most of these by accident – a long caption reaches into the neighbouring tile and is left to it –
/// and a caption with `display="always"` is never dropped by the collision check. mapsforge has the same
/// doubling with a `TileBasedLabelStore`; it goes away with the newer `MapDataStoreLabelStore`, which reads the
/// labels of a whole area at once instead of tile by tile.
///
/// Two captions count as the same when they read the same and lie within about one box of each other; the first
/// one in the input stays.
public func withoutDuplicateCaptions(_ input: [MapElementContainer]) -> [MapElementContainer] {
    var kept: [String: [MapElementContainer]] = [:]
    var result: [MapElementContainer] = []
    result.reserveCapacity(input.count)
    for item in input {
        guard let text = item.captionText else { result.append(item); continue }
        let box = item.boundaryAbsolute
        let same = kept[text]?.contains { other in
            let o = other.boundaryAbsolute
            return abs(box.midX - o.midX) < (box.width + o.width) / 2
                && abs(box.midY - o.midY) < box.height + o.height
        }
        if same == true { continue }
        kept[text, default: []].append(item)
        result.append(item)
    }
    return result
}

/// mapsforge `LayerUtil.collisionFreeOrdered`: highest priority first, drop clashing elements.
public func collisionFreeOrdered(_ input: [MapElementContainer]) -> [MapElementContainer] {
    // stable sort, descending priority (Collections.sort(reverseOrder()) is stable too)
    let sorted = input.enumerated().sorted { a, b in
        a.element.priority != b.element.priority ? a.element.priority > b.element.priority : a.offset < b.offset
    }.map(\.element)
    var output: [MapElementContainer] = []
    for item in sorted where !output.contains(where: { $0.clashes(with: item) }) {
        output.append(item)
    }
    return output
}

// MARK: - Way decorations

enum WayDecorator {
    static let maxLabelCornerAngle: CGFloat = 45

    static func renderSymbol(_ ctx: RenderContext, bitmap: ThemeBitmap, display: Display, priority: Int, dy: CGFloat,
                             boundary: CGRect?, repeats: Bool, repeatGap: CGFloat, repeatStart: CGFloat,
                             orientation: Orientation, way: PolylineContainer) {
        guard let first = way.coordinatesAbsolute.first, first.count >= 2 else { return }
        let c = dy == 0 ? first : Geometry.parallelPath(first, dy)
        var skipPixels = repeatStart
        var prev = c[0]
        for i in 1..<c.count {
            let cur = c[i]
            var theta: CGFloat = 0
            switch orientation {
            case .auto:
                theta = cur.x <= prev.x ? atan2(prev.y - cur.y, prev.x - cur.x) : atan2(cur.y - prev.y, cur.x - prev.x)
            case .autoDown:
                theta = cur.x <= prev.x ? atan2(cur.y - prev.y, cur.x - prev.x) : atan2(prev.y - cur.y, prev.x - cur.x)
            case .right: theta = atan2(prev.y - cur.y, prev.x - cur.x)
            case .left: theta = atan2(cur.y - prev.y, cur.x - prev.x)
            case .up: theta = 0
            case .down: theta = .pi
            }
            let dx = cur.x - prev.x, dyy = cur.y - prev.y
            let length = (dx * dx + dyy * dyy).squareRoot()
            guard length > 0 else { prev = cur; continue }
            var offset = skipPixels
            while offset + bitmap.size.width * 0.75 < length {
                let p = CGPoint(x: prev.x + offset * dx / length, y: prev.y + offset * dyy / length)
                ctx.addLabel(SymbolContainer(point: p, display: display, priority: priority, boundary: boundary,
                                             bitmap: bitmap, theta: theta))
                offset += bitmap.size.width + repeatGap
                if !repeats { return }
            }
            prev = cur
            skipPixels = max(0, offset - length)
        }
    }

    static func renderText(_ ctx: RenderContext, text: String, display: Display, priority: Int, dy: CGFloat,
                           paint: TextPaint, repeats: Bool, repeatGap: CGFloat, repeatStart: CGFloat,
                           orientation: Orientation, way: PolylineContainer) {
        guard let first = way.coordinatesAbsolute.first, first.count >= 2 else { return }
        let c = dy == 0 ? first : Geometry.parallelPath(first, dy)
        let line = Polyline(c)
        let metrics = TextRenderer.measure(text, paint: paint)
        let textWidth = metrics.width.rounded(.down), textHeight = metrics.height.rounded(.down)
        var pos = repeatStart
        while pos + textWidth < line.length {
            let part = line.extract(from: pos, to: pos + textWidth)
            var tooSharp = false
            if part.count > 2 {
                for i in 2..<part.count {
                    let a1 = atan2(part[i - 1].y - part[i - 2].y, part[i - 1].x - part[i - 2].x)
                    let a2 = atan2(part[i].y - part[i - 1].y, part[i].x - part[i - 1].x)
                    var d = (a2 - a1) * 180 / .pi
                    while d > 180 { d -= 360 }
                    while d < -180 { d += 360 }
                    if abs(d) > maxLabelCornerAngle { tooSharp = true; break }
                }
            }
            if !tooSharp && part.count >= 2 {
                ctx.addLabel(WayTextContainer(points: part, display: display, priority: priority, text: text,
                                              paint: paint, textHeight: textHeight, orientation: orientation))
            }
            if !repeats { break }
            pos += repeatGap + textWidth
        }
    }
}

/// Polyline with arc-length helpers (mapsforge `LineString` / `LineSegment`).
struct Polyline {
    let points: [CGPoint]
    let cumulative: [CGFloat]

    init(_ points: [CGPoint]) {
        self.points = points
        var acc: [CGFloat] = [0]
        acc.reserveCapacity(points.count)
        for i in 1..<max(points.count, 1) {
            acc.append(acc[i - 1] + hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y))
        }
        cumulative = acc
    }

    var length: CGFloat { cumulative.last ?? 0 }

    /// Point and segment angle at arc length `d`.
    func point(at d: CGFloat) -> (CGPoint, CGFloat) {
        var i = 1
        while i < points.count - 1 && cumulative[i] < d { i += 1 }
        let a = points[i - 1], b = points[i]
        let segLen = cumulative[i] - cumulative[i - 1]
        let t = segLen > 0 ? (d - cumulative[i - 1]) / segLen : 0
        return (CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), atan2(b.y - a.y, b.x - a.x))
    }

    /// Sub-polyline between arc lengths `from` and `to`.
    func extract(from: CGFloat, to: CGFloat) -> [CGPoint] {
        var result = [point(at: from).0]
        for i in 1..<points.count where cumulative[i] > from && cumulative[i] < to {
            result.append(points[i])
        }
        result.append(point(at: to).0)
        return result
    }
}

enum Geometry {
    /// mapsforge `RendererUtils.parallelPath`: offsets a polyline by `dy` pixels.
    static func parallelPath(_ p: [CGPoint], _ dy: CGFloat) -> [CGPoint] {
        let n = p.count - 1
        guard n >= 1 else { return p }
        var u = [CGPoint](repeating: .zero, count: n)
        for i in 0..<n {
            let dx = p[i + 1].x - p[i].x, dyy = p[i + 1].y - p[i].y
            let l = (dx * dx + dyy * dyy).squareRoot()
            u[i] = l > 0 ? CGPoint(x: dx / l, y: dyy / l) : .zero
        }
        var h = [CGPoint](repeating: .zero, count: p.count)
        h[0] = CGPoint(x: p[0].x - dy * u[0].y, y: p[0].y + dy * u[0].x)
        for i in 1..<n {
            let l = dy / (1 + u[i].x * u[i - 1].x + u[i].y * u[i - 1].y)
            h[i] = CGPoint(x: p[i].x - l * (u[i].y + u[i - 1].y), y: p[i].y + l * (u[i].x + u[i - 1].x))
        }
        h[n] = CGPoint(x: p[n].x - dy * u[n - 1].y, y: p[n].y + dy * u[n - 1].x)
        return h
    }
}
