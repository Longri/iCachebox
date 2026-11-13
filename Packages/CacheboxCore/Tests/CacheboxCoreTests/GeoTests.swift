import Foundation
import Testing
@testable import CacheboxCore

@Suite("Projektion")
struct ProjectionTests {
    private static let start = Coordinate(latitude: 53.0758, longitude: 8.8072)

    /// A projected point lies at the asked distance and direction again (within a centimetre resp. a thousandth
    /// of a degree), like Cachebox `Coordinate.project` with `distance`/`bearingTo`.
    @Test func keepsDistanceAndBearing() {
        for bearing in stride(from: 0.0, to: 360.0, by: 17.0) {
            for distance in [1.0, 25.0, 500.0, 12_345.0] {
                let projected = Self.start.projected(bearing: bearing, distance: distance)
                #expect(abs(Self.start.distance(to: projected) - distance) < 0.01,
                        "\(bearing)° \(distance) m: \(Self.start.distance(to: projected))")
                #expect(abs(Self.start.bearing(to: projected) - bearing) < 0.001,
                        "\(bearing)° \(distance) m: \(Self.start.bearing(to: projected))")
            }
        }
    }

    /// North, east, south and west go the way they should.
    @Test func goesInTheRightDirection() {
        let north = Self.start.projected(bearing: 0, distance: 1000)
        #expect(north.latitude > Self.start.latitude)
        #expect(abs(north.longitude - Self.start.longitude) < 1e-9)
        let east = Self.start.projected(bearing: 90, distance: 1000)
        #expect(east.longitude > Self.start.longitude)
        let south = Self.start.projected(bearing: 180, distance: 1000)
        #expect(south.latitude < Self.start.latitude)
        let west = Self.start.projected(bearing: 270, distance: 1000)
        #expect(west.longitude < Self.start.longitude)
    }

    /// Across the date line the longitude stays in −180°…+180°.
    @Test func normalisesAcrossTheDateLine() {
        let near = Coordinate(latitude: 0, longitude: 179.999)
        let projected = near.projected(bearing: 90, distance: 1000)
        #expect(projected.longitude < 0)
        #expect(projected.longitude > -180)
        #expect(abs(near.distance(to: projected) - 1000) < 0.01)
    }
}
