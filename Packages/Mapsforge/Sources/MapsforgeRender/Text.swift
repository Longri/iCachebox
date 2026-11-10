// CoreText based text rendering: captions with halo, multi-line wrapping and
// text along a path (replacement for Android's StaticLayout / drawTextOnPath).

import CoreGraphics
import CoreText
import Foundation

final class FontCache: @unchecked Sendable {
    static let shared = FontCache()
    private var cache: [String: CTFont] = [:]
    private let lock = NSLock()

    func font(family: String, bold: Bool, italic: Bool, size: CGFloat) -> CTFont {
        let key = "\(family)|\(bold)|\(italic)|\(size)"
        lock.lock()
        defer { lock.unlock() }
        if let f = cache[key] { return f }
        var base: CTFont
        switch family {
        case "serif": base = CTFontCreateWithName("TimesNewRomanPSMT" as CFString, size, nil)
        case "monospace": base = CTFontCreateWithName("Menlo-Regular" as CFString, size, nil)
        default: base = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        }
        var traits: CTFontSymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if !traits.isEmpty, let styled = CTFontCreateCopyWithSymbolicTraits(base, size, nil, traits, traits) {
            base = styled
        }
        cache[key] = base
        return base
    }
}

enum TextRenderer {
    static func line(_ text: String, font: CTFont) -> CTLine {
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorFromContextAttributeName: true,
        ]
        return CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary))
    }

    /// Width (advance) and glyph-bounds height, like Android `Paint.getTextWidth/getTextHeight`.
    static func measure(_ text: String, paint: TextPaint) -> CGSize {
        let l = line(text, font: paint.font)
        let width = CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil))
        let bounds = CTLineGetBoundsWithOptions(l, .useGlyphPathBounds)
        return CGSize(width: width, height: bounds.height)
    }

    /// Draws a CTLine with halo (stroke) and fill. The context is y-down; `baseline` is the baseline origin.
    static func draw(_ l: CTLine, at baseline: CGPoint, paint: TextPaint, in cg: CGContext) {
        cg.saveGState()
        cg.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        if paint.strokeWidth > 0 && !paint.stroke.isTransparent {
            cg.setTextDrawingMode(.stroke)
            cg.setLineWidth(paint.strokeWidth)
            cg.setLineJoin(.round)
            cg.setStrokeColor(paint.stroke.cgColor)
            cg.textPosition = baseline
            CTLineDraw(l, cg)
        }
        if !paint.fill.isTransparent {
            cg.setTextDrawingMode(.fill)
            cg.setFillColor(paint.fill.cgColor)
            cg.textPosition = baseline
            CTLineDraw(l, cg)
        }
        cg.restoreGState()
    }

    /// Draws text glyph by glyph along a polyline (y-down coordinates), centered vertically on the
    /// path like Android `drawTextOnPath(text, path, 0, textSize / 4, paint)`.
    static func drawText(_ text: String, alongPath points: [CGPoint], paint: TextPaint, in cg: CGContext) {
        guard points.count >= 2 else { return }
        let font = paint.font
        let l = line(text, font: font)
        let poly = Polyline(points)
        let vOffset = paint.size / 4
        let glyphPath = CGMutablePath()

        for run in CTLineGetGlyphRuns(l) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            var advances = [CGSize](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            CTRunGetAdvances(run, CFRange(location: 0, length: count), &advances)
            let attrs = CTRunGetAttributes(run) as NSDictionary
            let runFont = (attrs[kCTFontAttributeName] as! CTFont?) ?? font
            for i in 0..<count {
                let half = advances[i].width / 2
                let center = positions[i].x + half
                guard center <= poly.length + 1 else { break }
                let (p, angle) = poly.point(at: min(center, poly.length))
                // glyph outlines are y-up: flip, rotate onto the path, move to the glyph centre
                var t = CGAffineTransform(translationX: p.x, y: p.y)
                    .rotated(by: angle)
                    .translatedBy(x: -half, y: vOffset)
                    .scaledBy(x: 1, y: -1)
                if let gp = CTFontCreatePathForGlyph(runFont, glyphs[i], &t) {
                    glyphPath.addPath(gp)
                }
            }
        }
        cg.saveGState()
        if paint.strokeWidth > 0 && !paint.stroke.isTransparent {
            cg.addPath(glyphPath)
            cg.setLineWidth(paint.strokeWidth)
            cg.setLineJoin(.round)
            cg.setStrokeColor(paint.stroke.cgColor)
            cg.strokePath()
        }
        if !paint.fill.isTransparent {
            cg.addPath(glyphPath)
            cg.setFillColor(paint.fill.cgColor)
            cg.fillPath()
        }
        cg.restoreGState()
    }
}

/// Single- or multi-line text block (greedy word wrap at `maxWidth`, like Android StaticLayout).
struct TextLayout {
    let lines: [CTLine]
    let lineWidths: [CGFloat]
    let size: CGSize
    let paint: TextPaint
    let ascent: CGFloat
    let lineHeight: CGFloat
    let singleLine: Bool

    init(text: String, paint: TextPaint, maxWidth: CGFloat) {
        self.paint = paint
        let font = paint.font
        ascent = CTFontGetAscent(font)
        lineHeight = (CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)).rounded(.up)
        let measured = TextRenderer.measure(text, paint: paint)
        if measured.width <= maxWidth {
            let l = TextRenderer.line(text, font: font)
            lines = [l]
            lineWidths = [measured.width]
            size = CGSize(width: measured.width.rounded(.down), height: measured.height.rounded(.down))
            singleLine = true
            return
        }
        var result: [String] = []
        var current = ""
        for word in text.split(separator: " ") {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if !current.isEmpty && TextRenderer.measure(candidate, paint: paint).width > maxWidth {
                result.append(current)
                current = String(word)
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { result.append(current) }
        lines = result.map { TextRenderer.line($0, font: font) }
        lineWidths = lines.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }
        size = CGSize(width: min(maxWidth, lineWidths.max() ?? 0), height: lineHeight * CGFloat(lines.count))
        singleLine = false
    }

    func draw(in cg: CGContext, topLeft: CGPoint, alignment: CTTextAlignment) {
        if singleLine {
            // mapsforge draws single lines with the baseline at the bottom of the glyph box
            let x: CGFloat
            switch alignment {
            case .right: x = topLeft.x + size.width - lineWidths[0]
            case .left: x = topLeft.x
            default: x = topLeft.x + (size.width - lineWidths[0]) / 2
            }
            TextRenderer.draw(lines[0], at: CGPoint(x: x, y: topLeft.y + size.height), paint: paint, in: cg)
            return
        }
        for (i, l) in lines.enumerated() {
            let w = lineWidths[i]
            let x: CGFloat
            switch alignment {
            case .right: x = topLeft.x + size.width - w
            case .left: x = topLeft.x
            default: x = topLeft.x + (size.width - w) / 2
            }
            TextRenderer.draw(l, at: CGPoint(x: x, y: topLeft.y + ascent + CGFloat(i) * lineHeight), paint: paint, in: cg)
        }
    }
}
