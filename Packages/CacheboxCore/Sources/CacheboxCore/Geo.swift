import Foundation

public extension Coordinate {
    private static let earthRadius = 6_371_008.8   // mean radius in metres

    /// Great-circle distance in metres (haversine).
    func distance(to other: Coordinate) -> Double {
        let φ1 = latitude * .pi / 180, φ2 = other.latitude * .pi / 180
        let Δφ = φ2 - φ1, Δλ = (other.longitude - longitude) * .pi / 180
        let a = sin(Δφ / 2) * sin(Δφ / 2) + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
        return 2 * Self.earthRadius * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Initial bearing towards `other` in degrees (0 = north, clockwise).
    func bearing(to other: Coordinate) -> Double {
        let φ1 = latitude * .pi / 180, φ2 = other.latitude * .pi / 180
        let Δλ = (other.longitude - longitude) * .pi / 180
        let y = sin(Δλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// The point `distance` metres away in the direction `bearing` (0 = north, clockwise), on the same sphere as
    /// `distance(to:)` (Cachebox `Coordinate.project`, which uses the equatorial radius instead of the mean one;
    /// over a few kilometres the difference stays below a metre).
    func projected(bearing: Double, distance: Double) -> Coordinate {
        let δ = distance / Self.earthRadius   // angular distance
        let θ = bearing * .pi / 180
        let φ1 = latitude * .pi / 180, λ1 = longitude * .pi / 180
        let φ2 = asin(sin(φ1) * cos(δ) + cos(φ1) * sin(δ) * cos(θ))
        let λ2 = λ1 + atan2(sin(θ) * sin(δ) * cos(φ1), cos(δ) - sin(φ1) * sin(φ2))
        // normalise to −180°…+180°
        let λ = (λ2 + 3 * .pi).truncatingRemainder(dividingBy: 2 * .pi) - .pi
        return Coordinate(latitude: φ2 * 180 / .pi, longitude: λ * 180 / .pi)
    }

    /// Geocaching notation, e.g. "N 53° 04.548 E 008° 48.432".
    var formatted: String {
        func part(_ value: Double, _ positive: String, _ negative: String, _ width: Int) -> String {
            let v = abs(value)
            var degrees = Int(v)
            var minutes = ((v - Double(degrees)) * 60 * 1000).rounded() / 1000
            if minutes >= 60 { degrees += 1; minutes -= 60 }
            let deg = String(degrees).leftPadded(to: width)
            let min = String(format: "%06.3f", minutes)
            return "\(value < 0 ? negative : positive) \(deg)° \(min)"
        }
        return part(latitude, "N", "S", 2) + " " + part(longitude, "E", "W", 3)
    }
}

private extension String {
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: "0", count: width - count) + self
    }
}
