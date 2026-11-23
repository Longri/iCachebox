import Foundation

/// Damps the jitter of a heading before something follows it (not in Cachebox, which turns the map with the raw
/// heading of `Locator`). The magnetometer swings by several degrees even while standing still, and with the map
/// aligned to the compass the whole map wobbled back and forth.
///
/// Two steps, both measured the shorter way around the circle:
///
/// 1. A dead zone of `noise` degrees: a change smaller than that is dropped completely, so noise never moves
///    anything. A bigger change passes on reduced by the dead zone, so the damped heading trails a real turn by
///    at most `noise` degrees – not visible on a map, but it keeps the dead zone from being a hard step.
/// 2. A low pass with the time constant `timeConstant`: what is left of the change is taken over only in part,
///    the more the longer the step since the last heading lasted. A real turn is many changes in the same
///    direction and gets through within about a second; noise cancels itself out.
public struct HeadingDamper: Sendable {
    /// Changes below this many degrees are noise and are dropped.
    public var noise: Double
    /// Seconds in which about 63 % of a bigger change is taken over.
    public var timeConstant: Double
    /// The damped heading in degrees (0 = north, clockwise), nil until the first one arrives.
    public private(set) var value: Double?
    private var lastTime: Double?

    public init(noise: Double = 6, timeConstant: Double = 0.7) {
        self.noise = noise
        self.timeConstant = timeConstant
    }

    /// Takes a measured heading (degrees, nil = none) at `time` (seconds from any steady clock, e.g.
    /// `CACurrentMediaTime`) and returns the damped heading.
    @discardableResult
    public mutating func update(_ heading: Double?, at time: Double) -> Double? {
        guard let heading else {
            reset()
            return nil
        }
        guard let current = value, let last = lastTime, time > last else {
            // first heading, or the clock went backwards: take it as it is
            value = Self.normalized(heading)
            lastTime = time
            return value
        }
        // after a pause (app in the background, no compass for a while) take the heading over almost completely
        let step = min(time - last, 4 * timeConstant)
        lastTime = time
        var delta = (heading - current).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
        let beyondNoise = abs(delta) - noise
        guard beyondNoise > 0 else { return current }
        let share = 1 - exp(-step / timeConstant)
        value = Self.normalized(current + (delta < 0 ? -beyondNoise : beyondNoise) * share)
        return value
    }

    /// Forgets the filter: the next heading is taken over as it is (the map alignment was just switched on).
    public mutating func reset() {
        value = nil
        lastTime = nil
    }

    private static func normalized(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}
