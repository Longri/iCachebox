import SwiftUI
import UIKit

/// The arrows of the Cachebox skin, drawn as vectors so they stay sharp at any size (the sprites are 64 px).
enum CacheboxArrow {
    /// Colors of the position arrow: red while the compass gives the heading (`arrow-Compass`), cyan while it comes
    /// from GPS (`arrow-GPS`). Sampled from the Cachebox sprites.
    private struct Palette {
        let outline: UIColor
        let bandLeft: UIColor
        let bandRight: UIColor
        let innerLeft: UIColor
        let innerRight: UIColor
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }

    private static let compass = Palette(outline: rgb(65, 0, 0), bandLeft: rgb(205, 0, 0), bandRight: rgb(255, 24, 24),
                                         innerLeft: rgb(161, 0, 0), innerRight: rgb(255, 0, 0))
    private static let gps = Palette(outline: rgb(0, 58, 58), bandLeft: rgb(0, 160, 163), bandRight: rgb(0, 238, 242),
                                     innerLeft: rgb(0, 128, 130), innerRight: rgb(0, 196, 198))

    /// Alpha of the inner area of the transparent variants (`arrow-Compass-Trans`, `arrow-GPS-Trans`, 108/255).
    private static let transparentAlpha: CGFloat = 0.42

    @MainActor private static var cache: [String: UIImage] = [:]

    /// Own position (Cachebox `MapViewBase.renderPositionMarker`) and the arrow in the info panel: a dart pointing
    /// up, `size` points square. `transparent` is the Cachebox default for the map (`PositionMarkerTransparent`).
    @MainActor
    static func position(size: CGFloat, compass isCompass: Bool, transparent: Bool) -> UIImage {
        let key = "pos-\(size)-\(isCompass)-\(transparent)"
        if let image = cache[key] { return image }
        let palette = isCompass ? compass : gps
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { context in
            let cg = context.cgContext
            let u = size / 64   // the sprite is 64 × 64
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * u, y: y * u) }
            let outer = UIBezierPath()
            outer.move(to: p(32, 1))
            outer.addLine(to: p(52.5, 63))
            outer.addLine(to: p(32, 50.5))
            outer.addLine(to: p(11.5, 63))
            outer.close()
            let inner = UIBezierPath()
            inner.move(to: p(32, 11.5))
            inner.addLine(to: p(43.5, 52))
            inner.addLine(to: p(32, 45))
            inner.addLine(to: p(20.5, 52))
            inner.close()

            // the red/cyan band between outline and inner area, darker on the left half
            cg.saveGState()
            let band = UIBezierPath()
            band.append(outer)
            band.append(inner)
            band.usesEvenOddFillRule = true
            band.addClip()
            palette.bandLeft.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: size / 2, height: size))
            palette.bandRight.setFill()
            cg.fill(CGRect(x: size / 2, y: 0, width: size / 2, height: size))
            cg.restoreGState()

            cg.saveGState()
            inner.addClip()
            let alpha = transparent ? transparentAlpha : 1
            palette.innerLeft.withAlphaComponent(alpha).setFill()
            cg.fill(CGRect(x: 0, y: 0, width: size / 2, height: size))
            palette.innerRight.withAlphaComponent(alpha).setFill()
            cg.fill(CGRect(x: size / 2, y: 0, width: size / 2, height: size))
            cg.restoreGState()

            palette.outline.withAlphaComponent(0.85).setStroke()
            inner.lineWidth = 0.8 * u
            inner.stroke()
            palette.outline.setStroke()
            outer.lineWidth = 1.6 * u
            outer.lineJoinStyle = .round
            outer.stroke()
        }
        cache[key] = image
        return image
    }

    /// Kind of the arrow at the map edge.
    enum Target {
        /// The selected cache (Cachebox `MapView.renderTargetArrow`, `target-arrow`).
        case cache
        /// The own position (not in Cachebox): the same arrow in blue.
        case position
    }

    /// Size of the edge arrow (Cachebox `GL_UISizes.targetArrow`, 12.6 × 38.4 dp).
    static let targetSize = CGSize(width: 13, height: 39)

    /// Three stacked chevrons pointing up (Cachebox `target-arrow`, 21 × 64 px).
    @MainActor
    static func target(_ kind: Target) -> UIImage {
        let key = "target-\(kind)"
        if let image = cache[key] { return image }
        let size = targetSize
        let (edge, middle): (UIColor, UIColor) = switch kind {
        case .cache: (rgb(240, 0, 0), rgb(110, 0, 0))
        case .position: (rgb(40, 120, 255), rgb(0, 30, 140))
        }
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let ux = size.width / 21, uy = size.height / 64
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * ux, y: y * uy) }
            let colors = [edge.cgColor, middle.cgColor, edge.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                      locations: [0, 0.5, 1])!
            for y0 in [CGFloat(0), 17, 34] {
                let chevron = UIBezierPath()
                chevron.move(to: p(10.5, y0 + 0.5))
                chevron.addLine(to: p(20.5, y0 + 12.5))
                chevron.addLine(to: p(20.5, y0 + 28))
                chevron.addLine(to: p(10.5, y0 + 17))
                chevron.addLine(to: p(0.5, y0 + 28))
                chevron.addLine(to: p(0.5, y0 + 12.5))
                chevron.close()
                cg.saveGState()
                chevron.addClip()
                cg.drawLinearGradient(gradient, start: p(0, 0), end: p(21, 0), options: [])
                cg.restoreGState()
                // the light seams between the chevrons
                UIColor(white: 1, alpha: 0.75).setStroke()
                chevron.lineWidth = 0.6
                chevron.lineJoinStyle = .round
                chevron.stroke()
            }
        }
        cache[key] = image
        return image
    }
}

/// The position dart as a SwiftUI view (info panel).
struct CacheboxPositionArrow: View {
    let compass: Bool
    var size: CGFloat = 28

    var body: some View {
        Image(uiImage: CacheboxArrow.position(size: size, compass: compass, transparent: false))
            .frame(width: size, height: size)
    }
}
