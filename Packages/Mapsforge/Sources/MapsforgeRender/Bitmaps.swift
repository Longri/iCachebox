// Theme resources (symbols and patterns): PNG/JPEG via ImageIO, SVG via SVGDocument.
// Sizing follows mapsforge XmlUtils.createBitmap / AndroidSvgBitmap.

import CoreGraphics
import Foundation
import ImageIO

/// A symbol or pattern bitmap. SVGs stay vector and are drawn at device resolution.
final class ThemeBitmap: @unchecked Sendable {
    enum Content {
        case raster(CGImage)
        case vector(SVGDocument)
    }

    let content: Content
    /// Size in map points.
    let size: CGSize

    init(content: Content, size: CGSize) {
        self.content = content
        self.size = size
    }

    /// Draws into `rect` of a y-down context.
    func draw(in cg: CGContext, rect: CGRect) {
        switch content {
        case .vector(let svg):
            svg.draw(in: cg, rect: rect)
        case .raster(let image):
            cg.saveGState()
            cg.translateBy(x: rect.minX, y: rect.maxY)
            cg.scaleBy(x: 1, y: -1)
            cg.interpolationQuality = .high
            cg.draw(image, in: CGRect(origin: .zero, size: rect.size))
            cg.restoreGState()
        }
    }

    /// Fills the current path with this bitmap as repeating pattern, aligned to absolute map pixels
    /// (`origin` is the tile origin) so patterns continue seamlessly across tiles.
    func fillPath(_ path: CGPath, in cg: CGContext, origin: CGPoint) {
        guard size.width >= 1, size.height >= 1 else { return }
        var callbacks = CGPatternCallbacks(version: 0, drawPattern: { info, ctx in
            guard let info else { return }
            let bmp = Unmanaged<ThemeBitmap>.fromOpaque(info).takeUnretainedValue()
            bmp.draw(in: ctx, rect: CGRect(origin: .zero, size: bmp.size))
        }, releaseInfo: nil)
        let shiftX = -origin.x.truncatingRemainder(dividingBy: size.width)
        let shiftY = -origin.y.truncatingRemainder(dividingBy: size.height)
        // pattern space is relative to the context's base space, so include the current CTM
        let matrix = CGAffineTransform(translationX: shiftX, y: shiftY).concatenating(cg.ctm)
        guard let pattern = CGPattern(info: Unmanaged.passUnretained(self).toOpaque(),
                                      bounds: CGRect(origin: .zero, size: size), matrix: matrix,
                                      xStep: size.width, yStep: size.height, tiling: .constantSpacing,
                                      isColored: true, callbacks: &callbacks),
              let space = CGColorSpace(patternBaseSpace: nil) else { return }
        cg.saveGState()
        cg.setFillColorSpace(space)
        var alpha: CGFloat = 1
        cg.setFillPattern(pattern, colorComponents: &alpha)
        cg.addPath(path)
        cg.fillPath(using: .evenOdd)
        cg.restoreGState()
    }
}

/// Resolves and caches theme resources (`src` attributes).
final class ThemeResources: @unchecked Sendable {
    let baseDirectories: [URL]
    private var cache: [String: ThemeBitmap?] = [:]
    private let lock = NSLock()

    /// mapsforge default SVG size: area of 400 px² (≈ 20×20).
    static let svgDefaultArea: CGFloat = 400

    init(baseDirectories: [URL]) {
        self.baseDirectories = baseDirectories
    }

    func url(for src: String) -> URL? {
        var path = src
        for prefix in ["jar:", "file:", "assets:"] where path.hasPrefix(prefix) {
            path = String(path.dropFirst(prefix.count))
        }
        while path.hasPrefix("/") { path.removeFirst() }
        for base in baseDirectories {
            let u = base.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    func bitmap(_ src: String, width: CGFloat?, height: CGFloat?, percent: Int) -> ThemeBitmap? {
        let key = "\(src)|\(width ?? 0)|\(height ?? 0)|\(percent)"
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()
        let bmp = load(src, width: width, height: height, percent: percent)
        lock.lock()
        cache[key] = bmp
        lock.unlock()
        return bmp
    }

    private func load(_ src: String, width w: CGFloat?, height h: CGFloat?, percent: Int) -> ThemeBitmap? {
        guard let url = url(for: src), let data = try? Data(contentsOf: url) else { return nil }
        let content: ThemeBitmap.Content
        var natural: CGSize
        if url.pathExtension.lowercased() == "svg" {
            guard let svg = SVGDocument(data: data), svg.size.width > 0, svg.size.height > 0 else { return nil }
            content = .vector(svg)
            let scale = 1 / ((svg.size.width * svg.size.height) / Self.svgDefaultArea).squareRoot()
            natural = CGSize(width: svg.size.width * scale, height: svg.size.height * scale)
        } else {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            content = .raster(image)
            natural = CGSize(width: image.width, height: image.height)
        }
        let aspect = natural.width / max(natural.height, 1)
        switch (w ?? 0, h ?? 0) {
        case let (w, h) where w > 0 && h > 0: natural = CGSize(width: w, height: h)
        case let (0, h) where h > 0: natural = CGSize(width: h * aspect, height: h)
        case let (w, 0) where w > 0: natural = CGSize(width: w, height: w / aspect)
        default: break
        }
        if percent != 100 {
            natural = CGSize(width: natural.width * CGFloat(percent) / 100, height: natural.height * CGFloat(percent) / 100)
        }
        return ThemeBitmap(content: content, size: CGSize(width: natural.width.rounded(), height: natural.height.rounded()))
    }
}
