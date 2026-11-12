import Foundation

/// Where sun and moon stand in the sky, for the symbols around the compass (Cachebox `SunMoonCalculator` in the
/// `CompassView`). Low-precision formulas from Astronomy Answers ("Position of the Sun", "Position of the Moon",
/// aa.quae.nl), the same as in the BSD-licensed suncalc library; accurate to a fraction of a degree, which is plenty
/// for a symbol at the edge of the compass. Refraction and parallax are left out.
enum SkyPosition {
    struct Position: Equatable {
        /// Degrees from north, clockwise.
        var azimuth: Double
        /// Degrees above the horizon (negative: below).
        var elevation: Double
    }

    private static let rad = Double.pi / 180
    /// Obliquity of the ecliptic.
    private static let obliquity = rad * 23.4397

    static func sun(at date: Date, latitude: Double, longitude: Double) -> Position {
        let d = days(since2000: date)
        let meanAnomaly = rad * (357.5291 + 0.98560028 * d)
        let center = rad * (1.9148 * sin(meanAnomaly) + 0.02 * sin(2 * meanAnomaly) + 0.0003 * sin(3 * meanAnomaly))
        let perihelion = rad * 102.9372
        let eclipticLongitude = meanAnomaly + center + perihelion + .pi
        return horizontal(eclipticLongitude: eclipticLongitude, eclipticLatitude: 0, days: d,
                          latitude: latitude, longitude: longitude)
    }

    static func moon(at date: Date, latitude: Double, longitude: Double) -> Position {
        let d = days(since2000: date)
        let meanLongitude = rad * (218.316 + 13.176396 * d)
        let meanAnomaly = rad * (134.963 + 13.064993 * d)
        let meanDistance = rad * (93.272 + 13.229350 * d)
        let eclipticLongitude = meanLongitude + rad * 6.289 * sin(meanAnomaly)
        let eclipticLatitude = rad * 5.128 * sin(meanDistance)
        return horizontal(eclipticLongitude: eclipticLongitude, eclipticLatitude: eclipticLatitude, days: d,
                          latitude: latitude, longitude: longitude)
    }

    /// Days since 1 January 2000, 12:00 UT (Julian date − 2451545).
    private static func days(since2000 date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 - 0.5 + 2_440_588 - 2_451_545
    }

    /// Ecliptic → equatorial → horizontal coordinates.
    private static func horizontal(eclipticLongitude l: Double, eclipticLatitude b: Double, days d: Double,
                                   latitude: Double, longitude: Double) -> Position {
        let rightAscension = atan2(sin(l) * cos(obliquity) - tan(b) * sin(obliquity), cos(l))
        let declination = asin(sin(b) * cos(obliquity) + cos(b) * sin(obliquity) * sin(l))
        let phi = rad * latitude
        let siderealTime = rad * (280.16 + 360.9856235 * d) + rad * longitude
        let hourAngle = siderealTime - rightAscension
        // azimuth from south towards west, as in the formulas; turned to "from north, clockwise"
        let azimuthFromSouth = atan2(sin(hourAngle), cos(hourAngle) * sin(phi) - tan(declination) * cos(phi))
        let elevation = asin(sin(phi) * sin(declination) + cos(phi) * cos(declination) * cos(hourAngle))
        var azimuth = (azimuthFromSouth / rad + 180).truncatingRemainder(dividingBy: 360)
        if azimuth < 0 { azimuth += 360 }
        return Position(azimuth: azimuth, elevation: elevation / rad)
    }
}
