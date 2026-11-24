import CoreGraphics
import Foundation
import Testing
@testable import MapsforgeCore
@testable import MapsforgeRender

/// Which labels fit next to each other while the map is turned. mapsforge only ever compares the boxes of a map
/// pointing north; here the boxes are compared as they lie on the screen, because a name that keeps its own
/// direction no longer covers the same ground once the map has turned.
@Suite("Labels next to each other on a turned map")
struct LabelCollisionTests {
    static let paint = TextPaint(family: "Arial", bold: false, italic: false, size: 12,
                                 fill: .black, stroke: .transparent, strokeWidth: 0)

    static func caption(at point: CGPoint, text: String = "Testort", display: Display = .ifSpace,
                        priority: Int = 0) -> PointTextContainer {
        PointTextContainer(point: point, display: display, priority: priority, text: text, paint: paint,
                           position: .center, maxTextWidth: 200)
    }

    static func street(from: CGPoint, to: CGPoint) -> WayTextContainer {
        WayTextContainer(points: [from, to], display: .ifSpace, priority: 0, text: "Teststraße",
                         paint: paint, textHeight: 12, orientation: .auto)
    }

    static func degrees(_ d: CGFloat) -> CGFloat { d * .pi / 180 }

    /// A caption is wider than it is high; both tests below rest on that.
    static func captionSize() -> (width: CGFloat, height: CGFloat) {
        let box = caption(at: .zero).boundaryAbsolute
        return (box.width, box.height)
    }

    @Test("Without a turn the box is the one mapsforge uses")
    func sameBoxWithoutRotation() {
        let caption = Self.caption(at: CGPoint(x: 500, y: 300))
        let street = Self.street(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 40))
        #expect(caption.screenBoundary(at: 0) == caption.boundaryAbsolute)
        #expect(street.screenBoundary(at: 0) == street.boundaryAbsolute)
    }

    @Test("A name that keeps its direction keeps its box, only the place moves")
    func uprightLabelKeepsItsBox() {
        let caption = Self.caption(at: CGPoint(x: 100, y: 0))
        let box = caption.boundaryAbsolute
        for angle in stride(from: CGFloat(-180), through: 180, by: 30) {
            let turned = caption.screenBoundary(at: Self.degrees(angle))
            #expect(abs(turned.width - box.width) < 1e-9)
            #expect(abs(turned.height - box.height) < 1e-9)
        }
        // a quarter turn clockwise takes (100, 0) to (0, 100): the box goes with its anchor point
        let quarter = caption.screenBoundary(at: Self.degrees(90))
        #expect(abs(quarter.midX - 0) < 1e-6)
        #expect(abs(quarter.midY - 100) < 1e-6)
    }

    @Test("A name along a way lies across the screen, so its box grows")
    func wayTextGetsTheUprightBoxAroundTheTurnedOne() {
        let street = Self.street(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        let box = street.boundaryAbsolute
        #expect(box.width > box.height)
        let quarter = street.screenBoundary(at: Self.degrees(90))
        #expect(abs(quarter.width - box.height) < 1e-6)
        #expect(abs(quarter.height - box.width) < 1e-6)
    }

    @Test("Two names that cover each other on the map can both fit once it is turned")
    func turnMakesRoom() {
        let (w, h) = Self.captionSize()
        #expect(w > 2 * h)
        // side by side, closer than one caption is wide: on a map pointing north one of them has to go
        let first = Self.caption(at: CGPoint(x: 0, y: 0), priority: 1)
        let second = Self.caption(at: CGPoint(x: w / 2, y: 0), priority: 0)
        #expect(collisionFreeOrdered([first, second]).count == 1)
        // a quarter turn puts them above each other, further apart than a caption is high
        let turned = collisionFreeOrdered([first, second], rotation: Self.degrees(90))
        #expect(turned.count == 2)
    }

    @Test("Two names with room on the map can come into each other's way when it is turned")
    func turnTakesRoomAway() {
        let (w, h) = Self.captionSize()
        #expect(w > 2 * h)
        // above each other, further apart than a caption is high: both fit on a map pointing north
        let first = Self.caption(at: CGPoint(x: 0, y: 0), priority: 1)
        let second = Self.caption(at: CGPoint(x: 0, y: h * 1.5), priority: 0)
        #expect(collisionFreeOrdered([first, second]).count == 2)
        // turned a quarter they stand side by side, closer than one of them is wide
        let turned = collisionFreeOrdered([first, second], rotation: Self.degrees(90))
        #expect(turned.count == 1)
        #expect(turned.first === first)
    }

    @Test("A label that is always drawn stays, turned or not")
    func alwaysIsNeverDropped() {
        let (w, _) = Self.captionSize()
        let always = Self.caption(at: CGPoint(x: 0, y: 0), display: .always, priority: 0)
        let other = Self.caption(at: CGPoint(x: w / 4, y: 0), priority: 1)
        for angle in [CGFloat(0), 30, 90, 180] {
            let kept = collisionFreeOrdered([always, other], rotation: Self.degrees(angle))
            #expect(kept.count == 2)
        }
    }

    @Test("Without a turn the same labels come out as before")
    func unchangedWithoutRotation() {
        let (w, h) = Self.captionSize()
        var input: [MapElementContainer] = []
        for i in 0..<20 {
            input.append(Self.caption(at: CGPoint(x: CGFloat(i) * w / 3, y: CGFloat(i % 4) * h / 2),
                                      text: "Ort \(i)", priority: i % 3))
        }
        input.append(Self.street(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 10)))
        let old = collisionFreeOrdered(input)
        let new = collisionFreeOrdered(input, rotation: 0)
        #expect(old.count == new.count)
        #expect(zip(old, new).allSatisfy { $0 === $1 })
    }

    @Test("The place of the image is known before it is drawn")
    func imageBoundsMatchTheDrawnImage() throws {
        let caption = Self.caption(at: CGPoint(x: 120, y: 80))
        let street = Self.street(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 40))
        for label in [caption as MapElementContainer, street] {
            let drawn = try #require(label.render(scale: 2))
            #expect(drawn.bounds == label.imageBounds)
            #expect(drawn.image.width == Int((label.imageBounds.width * 2).rounded()))
        }
    }
}
