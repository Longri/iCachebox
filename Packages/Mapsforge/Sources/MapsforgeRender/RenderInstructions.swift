// Port of org.mapsforge.map.rendertheme.renderinstruction.* (Area, Line, Circle,
// Caption, PathText, Symbol, LineSymbol).
// Licensed under LGPL-3.0 like the original mapsforge code.

import CoreGraphics
import CoreText
import Foundation
import MapsforgeCore

enum Scale {
    case all, none, stroke
    init(_ s: String?) {
        switch s {
        case "all": self = .all
        case "none": self = .none
        default: self = .stroke
        }
    }
}

public enum Display: Sendable {
    case always, ifSpace, never
    init(_ s: String?) {
        switch s {
        case "always": self = .always
        case "never": self = .never
        default: self = .ifSpace
        }
    }
}

enum Position {
    case auto, center, below, belowLeft, belowRight, above, aboveLeft, aboveRight, left, right
    init?(_ s: String?) {
        switch s {
        case "auto": self = .auto
        case "center": self = .center
        case "below": self = .below
        case "below_left": self = .belowLeft
        case "below_right": self = .belowRight
        case "above": self = .above
        case "above_left": self = .aboveLeft
        case "above_right": self = .aboveRight
        case "left": self = .left
        case "right": self = .right
        default: return nil
        }
    }
    var isLeft: Bool { self == .left || self == .aboveLeft || self == .belowLeft }
    var isRight: Bool { self == .right || self == .aboveRight || self == .belowRight }
    var isUpper: Bool { self == .above || self == .aboveLeft || self == .aboveRight }
    var isLower: Bool { self == .below || self == .belowLeft || self == .belowRight }
}

enum TextTransform {
    case none, uppercase, lowercase, capitalize
    init(_ s: String?) {
        switch s {
        case "uppercase": self = .uppercase
        case "lowercase": self = .lowercase
        case "capitalize": self = .capitalize
        default: self = .none
        }
    }
    func apply(_ text: String) -> String {
        switch self {
        case .none: return text
        case .uppercase: return text.uppercased()
        case .lowercase: return text.lowercased()
        case .capitalize: return text.prefix(1).uppercased() + text.dropFirst()
        }
    }
}

enum Orientation {
    case auto, autoDown, right, left, up, down
    init(_ s: String?, rotate: String?) {
        switch s {
        case "auto_down": self = .autoDown
        case "right": self = .right
        case "left": self = .left
        case "up": self = .up
        case "down": self = .down
        default: self = (rotate == "false") ? .up : .auto
        }
    }
}

/// Stroke/fill description, the equivalent of a mapsforge `Paint`.
struct Paint {
    var color: ARGB
    var strokeWidth: CGFloat = 0
    var cap: CGLineCap = .round
    var join: CGLineJoin = .round
    var dash: [CGFloat]?
    var shader: ThemeBitmap?

    var isVisible: Bool { !color.isTransparent || shader != nil }
}

/// Font + colors for text rendering.
struct TextPaint {
    var family: String
    var bold: Bool
    var italic: Bool
    var size: CGFloat
    var fill: ARGB
    var stroke: ARGB
    var strokeWidth: CGFloat

    var font: CTFont { FontCache.shared.font(family: family, bold: bold, italic: italic, size: size) }
}

class RenderInstruction {
    let category: String?

    init(category: String?) {
        self.category = category
    }

    func renderNode(_ ctx: RenderContext, _ poi: PointOfInterest) {}
    func renderWay(_ ctx: RenderContext, _ way: PolylineContainer) {}
}

private func number(_ a: [String: String], _ key: String) -> CGFloat? {
    a[key].flatMap { Double($0) }.map { CGFloat($0) }
}

private func color(_ a: [String: String], _ key: String) throws -> ARGB? {
    try a[key].map(ARGB.parse)
}

// MARK: - Area

final class AreaInstruction: RenderInstruction {
    let level: Int
    let fill: ARGB
    let stroke: ARGB
    let strokeWidth: CGFloat
    let scale: Scale
    let src: String?
    let symbolWidth: CGFloat?
    let symbolHeight: CGFloat?
    let percent: Int
    let resources: ThemeResources

    init(_ a: [String: String], level: Int, resources: ThemeResources) throws {
        self.level = level
        self.resources = resources
        fill = try color(a, "fill") ?? .transparent
        stroke = try color(a, "stroke") ?? .transparent
        strokeWidth = number(a, "stroke-width") ?? 0
        scale = Scale(a["scale"])
        src = a["src"]
        symbolWidth = number(a, "symbol-width")
        symbolHeight = number(a, "symbol-height")
        percent = Int(a["symbol-percent"] ?? "") ?? 100
        super.init(category: a["cat"])
    }

    override func renderWay(_ ctx: RenderContext, _ way: PolylineContainer) {
        var fillPaint = Paint(color: fill)
        if let src {
            fillPaint.shader = resources.bitmap(src, width: symbolWidth, height: symbolHeight, percent: percent)
        }
        let s = scale == .none ? 1 : ctx.strokeScale
        let strokePaint = Paint(color: stroke, strokeWidth: strokeWidth * s)
        // mapsforge adds stroke first, then fill; levels are drawn in reverse insertion order
        ctx.addShape(level: level, ShapePaintContainer(shape: .polyline(way), paint: strokePaint, style: .stroke))
        ctx.addShape(level: level, ShapePaintContainer(shape: .polyline(way), paint: fillPaint, style: .fill))
    }
}

// MARK: - Line

final class LineInstruction: RenderInstruction {
    let level: Int
    let stroke: ARGB
    let strokeWidth: CGFloat
    let dash: [CGFloat]?
    let cap: CGLineCap
    let join: CGLineJoin
    let dy: CGFloat
    let scale: Scale
    let curve: Bool
    let src: String?
    let resources: ThemeResources

    init(_ a: [String: String], level: Int, resources: ThemeResources) throws {
        self.level = level
        self.resources = resources
        stroke = try color(a, "stroke") ?? .black
        strokeWidth = number(a, "stroke-width") ?? 0
        dash = a["stroke-dasharray"].map { $0.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }.map { CGFloat($0) } }
        switch a["stroke-linecap"] {
        case "butt": cap = .butt
        case "square": cap = .square
        default: cap = .round
        }
        switch a["stroke-linejoin"] {
        case "bevel": join = .bevel
        case "miter": join = .miter
        default: join = .round
        }
        dy = number(a, "dy") ?? 0
        scale = Scale(a["scale"])
        curve = a["curve"] == "cubic"
        src = a["src"]
        super.init(category: a["cat"])
    }

    override func renderWay(_ ctx: RenderContext, _ way: PolylineContainer) {
        let s = scale == .none ? 1 : ctx.strokeScale
        var paint = Paint(color: stroke, strokeWidth: strokeWidth * s, cap: cap, join: join)
        if let dash {
            paint.dash = scale == .all ? dash.map { $0 * s } : dash
        }
        if let src {
            paint.shader = resources.bitmap(src, width: nil, height: nil, percent: 100)
        }
        ctx.addShape(level: level, ShapePaintContainer(shape: .polyline(way), paint: paint, style: .stroke,
                                                       dy: dy * s, cubic: curve))
    }
}

// MARK: - Circle

final class CircleInstruction: RenderInstruction {
    let level: Int
    let radius: CGFloat
    let scaleRadius: Bool
    let fill: ARGB
    let stroke: ARGB
    let strokeWidth: CGFloat

    init(_ a: [String: String], level: Int) throws {
        self.level = level
        guard let r = number(a, "radius") ?? number(a, "r") else { throw RenderThemeError("circle requires radius") }
        radius = r
        scaleRadius = a["scale-radius"] == "true"
        fill = try color(a, "fill") ?? .transparent
        stroke = try color(a, "stroke") ?? .transparent
        strokeWidth = number(a, "stroke-width") ?? 0
        super.init(category: a["cat"])
    }

    override func renderNode(_ ctx: RenderContext, _ poi: PointOfInterest) {
        let r = scaleRadius ? radius * ctx.strokeScale : radius
        let center = ctx.pixelRelativeToTile(poi.position)
        let strokePaint = Paint(color: stroke, strokeWidth: strokeWidth * ctx.strokeScale)
        ctx.addShape(level: level, ShapePaintContainer(shape: .circle(center, r), paint: strokePaint, style: .stroke))
        ctx.addShape(level: level, ShapePaintContainer(shape: .circle(center, r), paint: Paint(color: fill), style: .fill))
    }
}

// MARK: - Text helpers

private func textPaint(_ a: [String: String]) throws -> TextPaint {
    let style = a["font-style"] ?? "normal"
    return TextPaint(
        family: a["font-family"] ?? "default",
        bold: style == "bold" || style == "bold_italic",
        italic: style == "italic" || style == "bold_italic",
        size: number(a, "font-size") ?? 0,
        fill: try color(a, "fill") ?? .black,
        stroke: try color(a, "stroke") ?? .black,
        strokeWidth: number(a, "stroke-width") ?? 0)
}

/// mapsforge `TextKey`: the tag value used as text.
private func textValue(_ key: String, _ tags: [Tag]) -> String? {
    for t in tags where t.key == key { return t.value }
    return nil
}

// MARK: - Caption

final class CaptionInstruction: RenderInstruction {
    static let gap: CGFloat = 5

    let key: String
    let display: Display
    let dy: CGFloat
    let priority: Int
    let paint: TextPaint
    let position: Position
    let transform: TextTransform
    let maxTextWidth: CGFloat
    let symbol: SymbolInstruction?

    init(_ a: [String: String], symbols: [String: SymbolInstruction]) throws {
        guard let k = a["k"] else { throw RenderThemeError("caption requires k") }
        key = k
        display = Display(a["display"])
        dy = number(a, "dy") ?? 0
        priority = Int(a["priority"] ?? "") ?? 0
        paint = try textPaint(a)
        transform = TextTransform(a["text-transform"])
        if let w = number(a, "text-wrap-width") {
            maxTextWidth = w == 0 ? .greatestFiniteMagnitude : w
        } else {
            maxTextWidth = 256 * 0.7
        }
        symbol = a["symbol-id"].flatMap { symbols[$0] }
        let explicit = Position(a["position"])
        position = (explicit == nil || explicit == .auto) ? (symbol == nil ? .center : .below) : explicit!
        super.init(category: a["cat"])
    }

    private func offsets() -> (dx: CGFloat, dy: CGFloat) {
        guard let symbol, let b = symbol.boundary else { return (0, dy) }
        let dx: CGFloat
        if position.isRight { dx = b.maxX + Self.gap }
        else if position.isLeft { dx = b.minX - Self.gap }
        else { dx = (b.minX + b.maxX) / 2 }
        var v = dy
        if position.isUpper { v += b.minY - Self.gap }
        else if position.isLower { v += b.maxY + Self.gap }
        else { v += (b.minY + b.maxY) / 2 }
        return (dx, v)
    }

    private func scaledPaint(_ ctx: RenderContext) -> TextPaint {
        var p = paint
        p.size *= ctx.textScale
        p.strokeWidth *= ctx.textScale
        return p
    }

    override func renderNode(_ ctx: RenderContext, _ poi: PointOfInterest) {
        guard display != .never, let text = textValue(key, poi.tags), !text.isEmpty else { return }
        let o = offsets()
        let p = ctx.pixelAbsolute(poi.position)
        ctx.addLabel(PointTextContainer(point: CGPoint(x: p.x + o.dx, y: p.y + o.dy), display: display, priority: priority,
                                        text: transform.apply(text), paint: scaledPaint(ctx), position: position,
                                        maxTextWidth: maxTextWidth))
    }

    override func renderWay(_ ctx: RenderContext, _ way: PolylineContainer) {
        guard display != .never, let text = textValue(key, way.tags), !text.isEmpty else { return }
        let o = offsets()
        let c = way.centerAbsolute
        ctx.addLabel(PointTextContainer(point: CGPoint(x: c.x + o.dx, y: c.y + o.dy), display: display, priority: priority,
                                        text: transform.apply(text), paint: scaledPaint(ctx), position: position,
                                        maxTextWidth: maxTextWidth))
    }
}

// MARK: - PathText

final class PathTextInstruction: RenderInstruction {
    let key: String
    let display: Display
    let dy: CGFloat
    let priority: Int
    let paint: TextPaint
    let repeats: Bool
    let repeatGap: CGFloat
    let repeatStart: CGFloat
    let orientation: Orientation
    let transform: TextTransform

    init(_ a: [String: String]) throws {
        guard let k = a["k"] else { throw RenderThemeError("pathText requires k") }
        key = k
        display = Display(a["display"])
        dy = number(a, "dy") ?? 0
        priority = Int(a["priority"] ?? "") ?? 0
        paint = try textPaint(a)
        repeats = a["repeat"].map { $0 == "true" } ?? true
        repeatGap = number(a, "repeat-gap") ?? 100
        repeatStart = number(a, "repeat-start") ?? 10
        orientation = Orientation(a["text-orientation"], rotate: a["rotate"])
        transform = TextTransform(a["text-transform"])
        super.init(category: a["cat"])
    }

    override func renderWay(_ ctx: RenderContext, _ way: PolylineContainer) {
        guard display != .never, let text = textValue(key, way.tags), !text.isEmpty else { return }
        var p = paint
        p.size *= ctx.textScale
        p.strokeWidth *= ctx.textScale
        WayDecorator.renderText(ctx, text: transform.apply(text), display: display, priority: priority,
                                dy: dy * ctx.strokeScale, paint: p, repeats: repeats, repeatGap: repeatGap,
                                repeatStart: repeatStart, orientation: orientation, way: way)
    }
}

// MARK: - Symbol

final class SymbolInstruction: RenderInstruction {
    let id: String?
    let src: String?
    let display: Display
    let priority: Int
    let width: CGFloat?
    let height: CGFloat?
    let percent: Int
    let position: Position
    let resources: ThemeResources

    init(_ a: [String: String], resources: ThemeResources) throws {
        self.resources = resources
        id = a["id"]
        src = a["src"]
        display = Display(a["display"])
        priority = Int(a["priority"] ?? "") ?? 0
        width = number(a, "symbol-width")
        height = number(a, "symbol-height")
        percent = Int(a["symbol-percent"] ?? "") ?? 100
        position = Position(a["position"]) ?? .center
        super.init(category: a["cat"])
    }

    var bitmap: ThemeBitmap? {
        src.flatMap { resources.bitmap($0, width: width, height: height, percent: percent) }
    }

    /// Boundary relative to the anchor point (mapsforge `computeBoundary`).
    var boundary: CGRect? {
        guard let bmp = bitmap else { return nil }
        let w = bmp.size.width, h = bmp.size.height
        var xf: CGFloat = -0.5, yf: CGFloat = -0.5
        if position.isLeft { xf = -1 } else if position.isRight { xf = 0 }
        if position.isUpper { yf = -1 } else if position.isLower { yf = 0 }
        return CGRect(x: xf * w, y: yf * h, width: w, height: h)
    }

    override func renderNode(_ ctx: RenderContext, _ poi: PointOfInterest) {
        guard display != .never, let bmp = bitmap else { return }
        let p = ctx.pixelAbsolute(poi.position)
        ctx.addLabel(SymbolContainer(point: p, display: display, priority: priority, boundary: boundary, bitmap: bmp, theta: 0))
    }

    override func renderWay(_ ctx: RenderContext, _ way: PolylineContainer) {
        guard display != .never, let bmp = bitmap else { return }
        ctx.addLabel(SymbolContainer(point: way.centerAbsolute, display: display, priority: priority, boundary: nil, bitmap: bmp, theta: 0))
    }
}

// MARK: - LineSymbol

final class LineSymbolInstruction: RenderInstruction {
    let src: String?
    let display: Display
    let priority: Int
    let dy: CGFloat
    let alignCenter: Bool
    let repeats: Bool
    let repeatGap: CGFloat
    let repeatStart: CGFloat
    let orientation: Orientation
    let width: CGFloat?
    let height: CGFloat?
    let percent: Int
    let resources: ThemeResources

    init(_ a: [String: String], resources: ThemeResources) throws {
        self.resources = resources
        src = a["src"]
        display = Display(a["display"])
        priority = Int(a["priority"] ?? "") ?? 0
        dy = number(a, "dy") ?? 0
        alignCenter = a["align-center"] == "true"
        repeats = a["repeat"] == "true"
        repeatGap = number(a, "repeat-gap") ?? 200
        repeatStart = number(a, "repeat-start") ?? 30
        orientation = Orientation(a["symbol-orientation"], rotate: a["rotate"])
        width = number(a, "symbol-width")
        height = number(a, "symbol-height")
        percent = Int(a["symbol-percent"] ?? "") ?? 100
        super.init(category: a["cat"])
    }

    override func renderWay(_ ctx: RenderContext, _ way: PolylineContainer) {
        guard display != .never, let src, let bmp = resources.bitmap(src, width: width, height: height, percent: percent) else { return }
        let boundary: CGRect? = alignCenter
            ? CGRect(x: -bmp.size.width / 2, y: -bmp.size.height / 2, width: bmp.size.width, height: bmp.size.height)
            : nil
        WayDecorator.renderSymbol(ctx, bitmap: bmp, display: display, priority: priority, dy: dy * ctx.strokeScale,
                                  boundary: boundary, repeats: repeats, repeatGap: repeatGap, repeatStart: repeatStart,
                                  orientation: orientation, way: way)
    }
}
