import Foundation

/// A position in UTM on WGS84: zone number, latitude band letter, easting and northing in metres.
///
/// Cachebox (`UTMConvert`) uses the series of USGS Bulletin 1532 (about 0.1 m); this implementation uses Krüger's
/// series to third order in n (Karney 2011, "Transverse Mercator with an accuracy of a few nanometers", eq. 35–36),
/// about a millimetre within a zone. Zone numbers follow the same rules: the Norway and Svalbard
/// exceptions, bands C…X with X reaching up to 84° N.
public struct UTMCoordinate: Hashable, Sendable {
    public var zone: Int
    /// Latitude band C…X (without I and O). N and later letters are on the northern hemisphere.
    public var band: Character
    public var easting: Double
    public var northing: Double

    /// Letters of the latitude bands from 80° S upwards (Cachebox `UTMConvert.sUtmLetterActual`).
    public static let bands: [Character] = Array("CDEFGHJKLMNPQRSTUVWX")

    public init(zone: Int, band: Character, easting: Double, northing: Double) {
        self.zone = zone
        self.band = band
        self.easting = easting
        self.northing = northing
    }

    public var isNorthern: Bool { band >= "N" }

    // MARK: - WGS84 and Krüger coefficients

    private static let a = 6_378_137.0
    private static let f = 1 / 298.257223563
    private static let k0 = 0.9996
    private static let falseEasting = 500_000.0
    private static let falseNorthingSouth = 10_000_000.0
    private static let n = f / (2 - f)
    /// Radius of the rectifying sphere.
    private static let A = a / (1 + n) * (1 + n * n / 4 + n * n * n * n / 64)
    private static let alpha = [n / 2 - 2 * n * n / 3 + 5 * n * n * n / 16,
                                13 * n * n / 48 - 3 * n * n * n / 5,
                                61 * n * n * n / 240]
    private static let beta = [n / 2 - 2 * n * n / 3 + 37 * n * n * n / 96,
                               n * n / 48 + n * n * n / 15,
                               17 * n * n * n / 480]
    /// First eccentricity.
    private static let e = sqrt(f * (2 - f))

    // MARK: - Zones

    /// Zone number of a position, with the exceptions for south-west Norway and Svalbard.
    public static func zone(latitude: Double, longitude: Double) -> Int {
        let lon = normalized(longitude)
        var zone = Int(floor((lon + 180) / 6)) + 1
        if zone > 60 { zone = 60 }
        if latitude >= 56 && latitude < 64 && lon >= 3 && lon < 12 { zone = 32 }
        if latitude >= 72 && latitude < 84 {
            if lon >= 0 && lon < 9 { zone = 31 }
            else if lon >= 9 && lon < 21 { zone = 33 }
            else if lon >= 21 && lon < 33 { zone = 35 }
            else if lon >= 33 && lon < 42 { zone = 37 }
        }
        return zone
    }

    /// Latitude band of a latitude; nil outside 80° S … 84° N, where UTM is not defined.
    public static func band(latitude: Double) -> Character? {
        guard latitude >= -80, latitude <= 84 else { return nil }
        let index = min(Int(floor((latitude + 80) / 8)), bands.count - 1)   // X covers 72…84
        return bands[index]
    }

    private static func centralMeridian(zone: Int) -> Double { Double(zone) * 6 - 183 }

    private static func normalized(_ longitude: Double) -> Double {
        var lon = (longitude + 180).truncatingRemainder(dividingBy: 360)
        if lon < 0 { lon += 360 }
        return lon - 180
    }

    // MARK: - Conversion

    /// The UTM position of a coordinate in its own zone; nil outside 80° S … 84° N.
    public init?(_ coordinate: Coordinate) {
        guard let band = Self.band(latitude: coordinate.latitude) else { return nil }
        let zone = Self.zone(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let φ = coordinate.latitude * .pi / 180
        var Δλ = Self.normalized(coordinate.longitude - Self.centralMeridian(zone: zone))
        Δλ *= .pi / 180
        let e = 2 * sqrt(Self.n) / (1 + Self.n)
        let t = sinh(atanh(sin(φ)) - e * atanh(e * sin(φ)))
        let ξʹ = atan2(t, cos(Δλ))
        let ηʹ = atanh(sin(Δλ) / sqrt(1 + t * t))
        var ξ = ξʹ, η = ηʹ
        for j in 1...3 {
            let k = 2 * Double(j)
            ξ += Self.alpha[j - 1] * sin(k * ξʹ) * cosh(k * ηʹ)
            η += Self.alpha[j - 1] * cos(k * ξʹ) * sinh(k * ηʹ)
        }
        self.zone = zone
        self.band = band
        easting = Self.falseEasting + Self.k0 * Self.A * η
        northing = Self.k0 * Self.A * ξ + (coordinate.latitude < 0 ? Self.falseNorthingSouth : 0)
    }

    /// Back to latitude and longitude; the band only tells the hemisphere (like Cachebox `iUTM2LatLon`).
    public var coordinate: Coordinate {
        let ξ = (northing - (isNorthern ? 0 : Self.falseNorthingSouth)) / (Self.k0 * Self.A)
        let η = (easting - Self.falseEasting) / (Self.k0 * Self.A)
        var ξʹ = ξ, ηʹ = η
        for j in 1...3 {
            let k = 2 * Double(j)
            ξʹ -= Self.beta[j - 1] * sin(k * ξ) * cosh(k * η)
            ηʹ -= Self.beta[j - 1] * cos(k * ξ) * sinh(k * η)
        }
        // conformal latitude χ to geodetic latitude, by iteration instead of the δ series (which is ~1 mm off)
        let χ = asin(sin(ξʹ) / cosh(ηʹ))
        let e = Self.e
        var φ = χ
        for _ in 0..<10 {
            let next = 2 * atan(tan(.pi / 4 + χ / 2) * pow((1 + e * sin(φ)) / (1 - e * sin(φ)), e / 2)) - .pi / 2
            if abs(next - φ) < 1e-15 { φ = next; break }
            φ = next
        }
        let λ = atan2(sinh(ηʹ), cos(ξʹ))
        return Coordinate(latitude: φ * 180 / .pi,
                          longitude: Self.normalized(Self.centralMeridian(zone: zone) + λ * 180 / .pi))
    }
}
