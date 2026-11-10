// Minimal SVG renderer for render theme symbols and patterns.
// Supports path, rect, circle, ellipse, line, polyline, polygon, g, nested transforms,
// fill/stroke/opacity attributes and `style` declarations. Not supported (yet):
// gradients, <use>, clipping, masks, filters, text.

import CoreGraphics
import Foundation

final class SVGDocument: @unchecked Sendable {
    struct Item {
        let path: CGPath
        let fill: CGColor?
        let evenOdd: Bool
        let stroke: CGColor?
        let strokeWidth: CGFloat
        let cap: CGLineCap
        let join: CGLineJoin
    }

    /// Intrinsic size in SVG user units (width/height attributes or viewBox).
    let size: CGSize
    let viewBox: CGRect
    let items: [Item]

    init?(data: Data) {
        let p = SVGParser()
        let parser = XMLParser(data: data)
        parser.delegate = p
        guard parser.parse(), !p.items.isEmpty || p.size != nil else { return nil }
        let vb = p.viewBox ?? CGRect(origin: .zero, size: p.size ?? CGSize(width: 100, height: 100))
        size = p.size ?? vb.size
        viewBox = vb
        items = p.items
    }

    /// Draws the document scaled into `rect` (y-down coordinate system, like SVG itself).
    func draw(in cg: CGContext, rect: CGRect) {
        guard viewBox.width > 0, viewBox.height > 0 else { return }
        cg.saveGState()
        cg.translateBy(x: rect.minX, y: rect.minY)
        cg.scaleBy(x: rect.width / viewBox.width, y: rect.height / viewBox.height)
        cg.translateBy(x: -viewBox.minX, y: -viewBox.minY)
        for item in items {
            if let fill = item.fill {
                cg.addPath(item.path)
                cg.setFillColor(fill)
                cg.fillPath(using: item.evenOdd ? .evenOdd : .winding)
            }
            if let stroke = item.stroke, item.strokeWidth > 0 {
                cg.addPath(item.path)
                cg.setStrokeColor(stroke)
                cg.setLineWidth(item.strokeWidth)
                cg.setLineCap(item.cap)
                cg.setLineJoin(item.join)
                cg.strokePath()
            }
        }
        cg.restoreGState()
    }
}

private final class SVGParser: NSObject, XMLParserDelegate {
    struct Style {
        var fill: String? = "#000000"
        var stroke: String? = nil
        var strokeWidth: CGFloat = 1
        var opacity: CGFloat = 1
        var fillOpacity: CGFloat = 1
        var strokeOpacity: CGFloat = 1
        var evenOdd = false
        var cap: CGLineCap = .butt
        var join: CGLineJoin = .miter
        var transform = CGAffineTransform.identity
    }

    var size: CGSize?
    var viewBox: CGRect?
    var items: [SVGDocument.Item] = []
    private var stack: [Style] = [Style()]
    private var skipDepth = 0

    private static let skipped: Set<String> = ["defs", "metadata", "symbol", "marker", "title", "desc", "clipPath",
                                               "mask", "linearGradient", "radialGradient", "pattern", "style"]

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes a: [String: String] = [:]) {
        if skipDepth > 0 || Self.skipped.contains(name) || name.contains(":") {
            skipDepth += 1
            return
        }
        var style = stack.last!
        apply(a, to: &style)
        stack.append(style)

        switch name {
        case "svg":
            if size == nil {
                let w = Self.length(a["width"]), h = Self.length(a["height"])
                if let vb = a["viewBox"].map(Self.numbers), vb.count == 4 {
                    viewBox = CGRect(x: vb[0], y: vb[1], width: vb[2], height: vb[3])
                }
                if let w, let h { size = CGSize(width: w, height: h) }
                else if let vb = viewBox { size = vb.size }
            }
        case "path":
            if let d = a["d"] { add(SVGPathParser.parse(d), style) }
        case "rect":
            let x = Self.length(a["x"]) ?? 0, y = Self.length(a["y"]) ?? 0
            let w = Self.length(a["width"]) ?? 0, h = Self.length(a["height"]) ?? 0
            var rx = Self.length(a["rx"]) ?? Self.length(a["ry"]) ?? 0
            var ry = Self.length(a["ry"]) ?? rx
            rx = min(rx, w / 2); ry = min(ry, h / 2)
            let r = CGRect(x: x, y: y, width: w, height: h)
            add(rx > 0 || ry > 0 ? CGPath(roundedRect: r, cornerWidth: rx, cornerHeight: ry, transform: nil) : CGPath(rect: r, transform: nil), style)
        case "circle":
            let cx = Self.length(a["cx"]) ?? 0, cy = Self.length(a["cy"]) ?? 0, r = Self.length(a["r"]) ?? 0
            add(CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r), transform: nil), style)
        case "ellipse":
            let cx = Self.length(a["cx"]) ?? 0, cy = Self.length(a["cy"]) ?? 0
            let rx = Self.length(a["rx"]) ?? 0, ry = Self.length(a["ry"]) ?? 0
            add(CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry), transform: nil), style)
        case "line":
            let p = CGMutablePath()
            p.move(to: CGPoint(x: Self.length(a["x1"]) ?? 0, y: Self.length(a["y1"]) ?? 0))
            p.addLine(to: CGPoint(x: Self.length(a["x2"]) ?? 0, y: Self.length(a["y2"]) ?? 0))
            var s = style
            s.fill = nil
            add(p, s)
        case "polyline", "polygon":
            let n = Self.numbers(a["points"] ?? "")
            guard n.count >= 4 else { break }
            let p = CGMutablePath()
            p.move(to: CGPoint(x: n[0], y: n[1]))
            var i = 2
            while i + 1 < n.count { p.addLine(to: CGPoint(x: n[i], y: n[i + 1])); i += 2 }
            if name == "polygon" { p.closeSubpath() }
            add(p, style)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
        if skipDepth > 0 { skipDepth -= 1; return }
        if stack.count > 1 { stack.removeLast() }
    }

    private func add(_ path: CGPath, _ s: Style) {
        var t = s.transform
        guard let transformed = path.copy(using: &t) else { return }
        let fill = s.fill.flatMap { Self.color($0, alpha: s.opacity * s.fillOpacity) }
        let stroke = s.stroke.flatMap { Self.color($0, alpha: s.opacity * s.strokeOpacity) }
        guard fill != nil || stroke != nil else { return }
        let scale = (abs(t.a * t.d - t.b * t.c)).squareRoot()
        items.append(.init(path: transformed, fill: fill, evenOdd: s.evenOdd, stroke: stroke,
                           strokeWidth: s.strokeWidth * scale, cap: s.cap, join: s.join))
    }

    private func apply(_ a: [String: String], to s: inout Style) {
        var props = a
        if let style = a["style"] {
            for decl in style.split(separator: ";") {
                let kv = decl.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if kv.count == 2 { props[kv[0]] = kv[1] }
            }
        }
        if let v = props["fill"] { s.fill = v == "none" ? nil : v }
        if let v = props["stroke"] { s.stroke = v == "none" ? nil : v }
        if let v = Self.length(props["stroke-width"]) { s.strokeWidth = v }
        if let v = props["opacity"].flatMap(Double.init) { s.opacity *= CGFloat(v) }
        if let v = props["fill-opacity"].flatMap(Double.init) { s.fillOpacity = CGFloat(v) }
        if let v = props["stroke-opacity"].flatMap(Double.init) { s.strokeOpacity = CGFloat(v) }
        if let v = props["fill-rule"] { s.evenOdd = v == "evenodd" }
        switch props["stroke-linecap"] {
        case "round": s.cap = .round
        case "square": s.cap = .square
        case "butt": s.cap = .butt
        default: break
        }
        switch props["stroke-linejoin"] {
        case "round": s.join = .round
        case "bevel": s.join = .bevel
        case "miter": s.join = .miter
        default: break
        }
        if let t = a["transform"] { s.transform = Self.transform(t).concatenating(s.transform) }
    }

    // MARK: value parsing

    static func length(_ s: String?) -> CGFloat? {
        guard var s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty, !s.hasSuffix("%") else { return nil }
        for unit in ["px", "pt", "mm", "cm", "in"] where s.hasSuffix(unit) { s = String(s.dropLast(unit.count)) }
        return Double(s).map { CGFloat($0) }
    }

    static func numbers(_ s: String) -> [CGFloat] {
        var scanner = SVGPathParser.Scanner(s)
        var result: [CGFloat] = []
        while let n = scanner.number() { result.append(n) }
        return result
    }

    static func transform(_ s: String) -> CGAffineTransform {
        var result = CGAffineTransform.identity
        var rest = Substring(s)
        while let open = rest.firstIndex(of: "("), let close = rest.firstIndex(of: ")") {
            let name = rest[..<open].trimmingCharacters(in: CharacterSet(charactersIn: " ,\t\n"))
            let n = numbers(String(rest[rest.index(after: open)..<close]))
            var t = CGAffineTransform.identity
            switch name {
            case "matrix" where n.count == 6: t = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5])
            case "translate" where n.count >= 1: t = CGAffineTransform(translationX: n[0], y: n.count > 1 ? n[1] : 0)
            case "scale" where n.count >= 1: t = CGAffineTransform(scaleX: n[0], y: n.count > 1 ? n[1] : n[0])
            case "rotate" where n.count >= 1:
                let r = n[0] * .pi / 180
                if n.count == 3 {
                    t = CGAffineTransform(translationX: n[1], y: n[2]).rotated(by: r).translatedBy(x: -n[1], y: -n[2])
                } else {
                    t = CGAffineTransform(rotationAngle: r)
                }
            case "skewX" where n.count == 1: t = CGAffineTransform(a: 1, b: 0, c: tan(n[0] * .pi / 180), d: 1, tx: 0, ty: 0)
            case "skewY" where n.count == 1: t = CGAffineTransform(a: 1, b: tan(n[0] * .pi / 180), c: 0, d: 1, tx: 0, ty: 0)
            default: break
            }
            // SVG transform lists apply right-to-left: the first listed is the outermost
            result = t.concatenating(result)
            rest = rest[rest.index(after: close)...]
        }
        return result
    }

    static let namedColors: [String: (UInt8, UInt8, UInt8)] = [
        "black": (0, 0, 0), "white": (255, 255, 255), "red": (255, 0, 0), "green": (0, 128, 0), "blue": (0, 0, 255),
        "yellow": (255, 255, 0), "gray": (128, 128, 128), "grey": (128, 128, 128), "orange": (255, 165, 0),
        "brown": (165, 42, 42), "purple": (128, 0, 128), "darkgreen": (0, 100, 0), "navy": (0, 0, 128),
    ]

    static func color(_ s: String, alpha: CGFloat) -> CGColor? {
        let s = s.trimmingCharacters(in: .whitespaces).lowercased()
        var rgb: (CGFloat, CGFloat, CGFloat)?
        if s.hasPrefix("#") {
            let hex = String(s.dropFirst())
            if hex.count == 3, let v = UInt32(hex, radix: 16) {
                rgb = (CGFloat((v >> 8) & 0xf) * 17 / 255, CGFloat((v >> 4) & 0xf) * 17 / 255, CGFloat(v & 0xf) * 17 / 255)
            } else if hex.count == 6, let v = UInt32(hex, radix: 16) {
                rgb = (CGFloat((v >> 16) & 0xff) / 255, CGFloat((v >> 8) & 0xff) / 255, CGFloat(v & 0xff) / 255)
            }
        } else if s.hasPrefix("rgb(") {
            let n = numbers(String(s.dropFirst(4).dropLast()))
            if n.count >= 3 { rgb = (n[0] / 255, n[1] / 255, n[2] / 255) }
        } else if let c = namedColors[s] {
            rgb = (CGFloat(c.0) / 255, CGFloat(c.1) / 255, CGFloat(c.2) / 255)
        }
        guard let rgb else { return nil }
        return CGColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: alpha)
    }
}

/// SVG path data (`d` attribute) parser producing a CGPath.
enum SVGPathParser {
    struct Scanner {
        let chars: [UInt8]
        var i = 0
        init(_ s: String) { chars = Array(s.utf8) }

        mutating func skipSeparators() {
            while i < chars.count, chars[i] == 32 || chars[i] == 44 || chars[i] == 9 || chars[i] == 10 || chars[i] == 13 { i += 1 }
        }

        mutating func peekCommand() -> UInt8? {
            skipSeparators()
            guard i < chars.count else { return nil }
            let c = chars[i]
            let isLetter = (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
            return isLetter && c != 101 && c != 69 ? c : nil   // 'e'/'E' belong to numbers
        }

        mutating func number() -> CGFloat? {
            skipSeparators()
            let start = i
            if i < chars.count, chars[i] == 43 || chars[i] == 45 { i += 1 }
            var digits = false, dot = false
            while i < chars.count {
                let c = chars[i]
                if c >= 48 && c <= 57 { digits = true; i += 1 }
                else if c == 46 && !dot { dot = true; i += 1 }
                else { break }
            }
            if digits, i < chars.count, chars[i] == 101 || chars[i] == 69 {
                var j = i + 1
                if j < chars.count, chars[j] == 43 || chars[j] == 45 { j += 1 }
                if j < chars.count, chars[j] >= 48 && chars[j] <= 57 {
                    i = j
                    while i < chars.count, chars[i] >= 48 && chars[i] <= 57 { i += 1 }
                }
            }
            guard digits else { i = start; return nil }
            return Double(String(decoding: chars[start..<i], as: UTF8.self)).map { CGFloat($0) }
        }

        /// Arc flags may be written without separators ("a1 1 0 01 2 2").
        mutating func flag() -> Bool? {
            skipSeparators()
            guard i < chars.count, chars[i] == 48 || chars[i] == 49 else { return nil }
            defer { i += 1 }
            return chars[i] == 49
        }
    }

    static func parse(_ d: String) -> CGPath {
        let path = CGMutablePath()
        var s = Scanner(d)
        var cur = CGPoint.zero, start = CGPoint.zero
        var lastCtrl: CGPoint?
        var lastCmd: UInt8 = 0
        var cmd: UInt8 = 0

        while true {
            if let c = s.peekCommand() {
                cmd = c
                s.i += 1
            } else if s.i >= s.chars.count {
                break
            } else if cmd == 0 || cmd == 90 || cmd == 122 {
                break   // numbers without command (or after closepath) are invalid
            } else if cmd == 77 { cmd = 76 } else if cmd == 109 { cmd = 108 }   // implicit lineto after moveto

            let rel = cmd >= 97
            let base = rel ? cur : .zero
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: base.x + x, y: base.y + y) }

            switch cmd | 0x20 {   // lowercase
            case 122: // z
                path.closeSubpath()
                cur = start
                lastCtrl = nil
                lastCmd = cmd
                continue
            case 109: // m
                guard let x = s.number(), let y = s.number() else { return path }
                cur = pt(x, y); start = cur
                path.move(to: cur)
                lastCtrl = nil
            case 108: // l
                guard let x = s.number(), let y = s.number() else { return path }
                cur = pt(x, y)
                if path.isEmpty { path.move(to: cur) } else { path.addLine(to: cur) }
                lastCtrl = nil
            case 104: // h
                guard let x = s.number() else { return path }
                cur = CGPoint(x: rel ? cur.x + x : x, y: cur.y)
                path.addLine(to: cur)
                lastCtrl = nil
            case 118: // v
                guard let y = s.number() else { return path }
                cur = CGPoint(x: cur.x, y: rel ? cur.y + y : y)
                path.addLine(to: cur)
                lastCtrl = nil
            case 99: // c
                guard let x1 = s.number(), let y1 = s.number(), let x2 = s.number(), let y2 = s.number(),
                      let x = s.number(), let y = s.number() else { return path }
                let c1 = pt(x1, y1), c2 = pt(x2, y2)
                cur = pt(x, y)
                path.addCurve(to: cur, control1: c1, control2: c2)
                lastCtrl = c2
            case 115: // s
                guard let x2 = s.number(), let y2 = s.number(), let x = s.number(), let y = s.number() else { return path }
                let prevWasCubic = [99, 67, 115, 83].contains(lastCmd)
                let c1 = prevWasCubic && lastCtrl != nil ? CGPoint(x: 2 * cur.x - lastCtrl!.x, y: 2 * cur.y - lastCtrl!.y) : cur
                let c2 = pt(x2, y2)
                cur = pt(x, y)
                path.addCurve(to: cur, control1: c1, control2: c2)
                lastCtrl = c2
            case 113: // q
                guard let x1 = s.number(), let y1 = s.number(), let x = s.number(), let y = s.number() else { return path }
                let c = pt(x1, y1)
                cur = pt(x, y)
                path.addQuadCurve(to: cur, control: c)
                lastCtrl = c
            case 116: // t
                guard let x = s.number(), let y = s.number() else { return path }
                let prevWasQuad = [113, 81, 116, 84].contains(lastCmd)
                let c = prevWasQuad && lastCtrl != nil ? CGPoint(x: 2 * cur.x - lastCtrl!.x, y: 2 * cur.y - lastCtrl!.y) : cur
                cur = pt(x, y)
                path.addQuadCurve(to: cur, control: c)
                lastCtrl = c
            case 97: // a
                guard let rx = s.number(), let ry = s.number(), let rot = s.number(),
                      let large = s.flag(), let sweep = s.flag(), let x = s.number(), let y = s.number() else { return path }
                let end = pt(x, y)
                addArc(path, from: cur, to: end, rx: rx, ry: ry, angle: rot, large: large, sweep: sweep)
                cur = end
                lastCtrl = nil
            default:
                return path
            }
            lastCmd = cmd
        }
        return path
    }

    /// SVG elliptical arc (endpoint parameterization) approximated with cubic Béziers.
    static func addArc(_ path: CGMutablePath, from p0: CGPoint, to p1: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat,
                       angle: CGFloat, large: Bool, sweep: Bool) {
        var rx = abs(rxIn), ry = abs(ryIn)
        guard rx > 0, ry > 0, p0 != p1 else { path.addLine(to: p1); return }
        let phi = angle * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 { rx *= lambda.squareRoot(); ry *= lambda.squareRoot() }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var coef = den == 0 ? 0 : (max(0, num / den)).squareRoot()
        if large == sweep { coef = -coef }
        let cx1 = coef * rx * y1 / ry
        let cy1 = -coef * ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (p0.x + p1.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (p0.y + p1.y) / 2
        func angleOf(_ ux: CGFloat, _ uy: CGFloat) -> CGFloat { atan2(uy, ux) }
        let theta1 = angleOf((x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angleOf((-x1 - cx1) / rx, (-y1 - cy1) / ry) - theta1
        if sweep && delta < 0 { delta += 2 * .pi }
        if !sweep && delta > 0 { delta -= 2 * .pi }
        let segments = Int(ceil(abs(delta) / (.pi / 2)))
        let step = delta / CGFloat(segments)
        let k = 4.0 / 3.0 * tan(step / 4)
        var t = theta1
        func point(_ a: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cos(a) * cosPhi - ry * sin(a) * sinPhi, y: cy + rx * cos(a) * sinPhi + ry * sin(a) * cosPhi)
        }
        func deriv(_ a: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(a) * cosPhi - ry * cos(a) * sinPhi, y: -rx * sin(a) * sinPhi + ry * cos(a) * cosPhi)
        }
        for _ in 0..<segments {
            let a0 = t, a1 = t + step
            let s = point(a0), e = point(a1), d0 = deriv(a0), d1 = deriv(a1)
            path.addCurve(to: e, control1: CGPoint(x: s.x + k * d0.x, y: s.y + k * d0.y),
                          control2: CGPoint(x: e.x - k * d1.x, y: e.y - k * d1.y))
            t = a1
        }
    }
}
