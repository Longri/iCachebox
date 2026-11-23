import Foundation
import Testing
@testable import CacheboxCore

@Suite("Kompass dämpfen")
struct HeadingDamperTests {
    /// Headings measured every 0.1 s, as the compass delivers them.
    private func feed(_ headings: [Double], into damper: inout HeadingDamper, from start: Double = 100) -> Double? {
        var time = start
        var last: Double?
        for heading in headings {
            last = damper.update(heading, at: time)
            time += 0.1
        }
        return last
    }

    /// The first heading is taken over as it is, there is nothing to damp yet.
    @Test func takesTheFirstHeadingAsItIs() {
        var damper = HeadingDamper()
        #expect(damper.update(123, at: 100) == 123)
        #expect(damper.value == 123)
    }

    /// The compass swinging around a direction while standing still does not move the damped heading at all.
    @Test func ignoresJitterWhileStandingStill() {
        var damper = HeadingDamper()
        let jitter = (0..<60).map { 90 + 5 * sin(Double($0) * 0.7) }
        _ = feed([90], into: &damper)
        _ = feed(jitter, into: &damper, from: 101)
        #expect(damper.value == 90)
    }

    /// A real turn gets through: after about a second the damped heading is at the new direction.
    @Test func followsARealTurn() {
        var damper = HeadingDamper()
        _ = feed([0], into: &damper)
        // the compass turns to 90° and stays there
        _ = feed(Array(repeating: 90.0, count: 10), into: &damper, from: 101)
        let after1s = damper.value ?? 0
        #expect(after1s > 70 && after1s < 90, "nach 1 s: \(after1s)")
        _ = feed(Array(repeating: 90.0, count: 30), into: &damper, from: 102)
        // what is left is the dead zone: the damped heading creeps towards it but never through it
        #expect(abs((damper.value ?? 0) - 90) <= damper.noise + 0.5)
    }

    /// Turning across north goes the short way, not 350 degrees around.
    @Test func turnsTheShortWayAroundNorth() {
        var damper = HeadingDamper()
        _ = feed([350], into: &damper)
        _ = feed(Array(repeating: 10.0, count: 40), into: &damper, from: 101)
        let value = damper.value ?? 0
        #expect(value > 350 || value < 20, "\(value)")
        var difference = abs(value - 10).truncatingRemainder(dividingBy: 360)
        if difference > 180 { difference = 360 - difference }
        #expect(difference <= damper.noise + 0.5, "\(value)")
    }

    /// The damped heading stays between 0 and 360 degrees.
    @Test func staysInTheCircle() {
        var damper = HeadingDamper()
        _ = feed([5], into: &damper)
        for _ in 0..<50 { _ = feed(Array(repeating: 350.0, count: 5), into: &damper, from: 101) }
        let value = damper.value ?? -1
        #expect(value >= 0 && value < 360, "\(value)")
    }

    /// After a long pause (app was in the background) the heading is taken over almost completely instead of
    /// crawling towards it.
    @Test func catchesUpAfterAPause() {
        var damper = HeadingDamper()
        _ = damper.update(0, at: 100)
        let value = damper.update(180, at: 160) ?? 0
        #expect(value > 170, "\(value)")
    }

    /// Without a heading the filter starts over, so the next one is taken as it is.
    @Test func forgetsWithoutAHeading() {
        var damper = HeadingDamper()
        _ = damper.update(10, at: 100)
        #expect(damper.update(nil, at: 100.1) == nil)
        #expect(damper.value == nil)
        #expect(damper.update(200, at: 100.2) == 200)
    }
}
