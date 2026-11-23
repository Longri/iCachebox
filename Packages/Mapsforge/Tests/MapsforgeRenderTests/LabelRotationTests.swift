import CoreGraphics
import Foundation
import Testing
@testable import MapsforgeCore
@testable import MapsforgeRender

/// The direction a label is drawn in while the map is turned (not in mapsforge, which turns every label with
/// the tile it is drawn into): names of ways turn along, but are drawn the other way round instead of upside
/// down; captions and the symbols of points keep their own direction on the screen.
@Suite("Labels on a turned map")
struct LabelRotationTests {
    static let paint = TextPaint(family: "Arial", bold: false, italic: false, size: 12,
                                 fill: .black, stroke: .transparent, strokeWidth: 0)

    /// A street running from `from` to `to` in absolute map pixels (y down, like the renderer).
    static func street(from: CGPoint, to: CGPoint, orientation: Orientation = .auto) -> WayTextContainer {
        WayTextContainer(points: [from, to], display: .ifSpace, priority: 0, text: "Teststraße",
                         paint: paint, textHeight: 12, orientation: orientation)
    }

    static func degrees(_ d: CGFloat) -> CGFloat { d * .pi / 180 }

    @Test("A street to the east reads as it is until the map turns it backwards")
    func eastwardStreet() {
        let street = Self.street(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        #expect(!street.inverts(at: 0))
        #expect(!street.inverts(at: Self.degrees(45)))
        #expect(street.inverts(at: Self.degrees(135)))
        #expect(street.inverts(at: Self.degrees(180)))
        #expect(street.inverts(at: Self.degrees(-135)))
        #expect(!street.inverts(at: Self.degrees(-45)))
    }

    @Test("A street to the west is drawn the other way round until the map turns it forwards")
    func westwardStreet() {
        let street = Self.street(from: CGPoint(x: 100, y: 0), to: CGPoint(x: 0, y: 0))
        #expect(street.inverts(at: 0))
        #expect(!street.inverts(at: Self.degrees(180)))
    }

    @Test("The text turns round as soon as it would point backwards on the screen")
    func flipsWhenItWouldPointBackwards() {
        // a street to the north-east (y points down): on the screen it keeps pointing to the right until the
        // map has turned it by more than 135°, and the other way round from 45° backwards
        let street = Self.street(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: -100))
        #expect(!street.inverts(at: Self.degrees(134)))
        #expect(street.inverts(at: Self.degrees(136)))
        #expect(!street.inverts(at: Self.degrees(-44)))
        #expect(street.inverts(at: Self.degrees(-46)))
    }

    @Test("Without a turn it is mapsforge's own rule")
    func matchesMapsforgeWithoutRotation() {
        // mapsforge `WayTextContainer.generatePath`: AUTO inverts when the first segment does not run to the
        // right, AUTO_DOWN the other way round, RIGHT and LEFT are fixed
        let east = CGPoint(x: 100, y: 0), origin = CGPoint.zero
        #expect(!Self.street(from: origin, to: east, orientation: .auto).inverts(at: 0))
        #expect(Self.street(from: east, to: origin, orientation: .auto).inverts(at: 0))
        #expect(Self.street(from: origin, to: east, orientation: .autoDown).inverts(at: 0))
        #expect(!Self.street(from: east, to: origin, orientation: .autoDown).inverts(at: 0))
        #expect(!Self.street(from: east, to: origin, orientation: .right).inverts(at: 0))
        #expect(Self.street(from: origin, to: east, orientation: .left).inverts(at: 0))
    }

    @Test("A fixed direction stays fixed however the map is turned")
    func fixedOrientationIgnoresRotation() {
        let right = Self.street(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0), orientation: .right)
        let left = Self.street(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0), orientation: .left)
        for angle in stride(from: CGFloat(-180), through: 180, by: 45) {
            #expect(!right.inverts(at: Self.degrees(angle)))
            #expect(left.inverts(at: Self.degrees(angle)))
        }
    }

    @Test("Captions and the symbols of points keep their direction, ways turn along")
    func whatTurnsWithTheMap() throws {
        let caption = PointTextContainer(point: .zero, display: .ifSpace, priority: 0, text: "Bremen",
                                         paint: Self.paint, position: .center, maxTextWidth: 200)
        #expect(!caption.rotatesWithMap)
        #expect(!caption.inverts(at: Self.degrees(180)))
        #expect(Self.street(from: .zero, to: CGPoint(x: 100, y: 0)).rotatesWithMap)

        let bitmap = ThemeBitmap(content: .raster(try #require(Self.pixel())),
                                 size: CGSize(width: 10, height: 10))
        let poi = SymbolContainer(point: .zero, display: .ifSpace, priority: 0, boundary: nil, bitmap: bitmap,
                                  theta: 0)
        let alongWay = SymbolContainer(point: .zero, display: .ifSpace, priority: 0, boundary: nil,
                                       bitmap: bitmap, theta: 0, alongWay: true)
        #expect(!poi.rotatesWithMap)
        #expect(alongWay.rotatesWithMap)
    }

    static func pixel() -> CGImage? {
        let cg = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        return cg?.makeImage()
    }
}
