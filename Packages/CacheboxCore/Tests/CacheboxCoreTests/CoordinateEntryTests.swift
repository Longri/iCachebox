import Foundation
import Testing
@testable import CacheboxCore

@Suite("UTM")
struct UTMTests {
    /// Computed with Cachebox `UTMConvert` (USGS Bulletin 1532, about 0.1 m; further away from the central meridian
    /// a little more), so the tolerance is 1 m.
    static let reference: [(Double, Double, Int, Character, Double, Double)] = [
        (53.075800, 8.807200, 32, "U", 487083.799, 5880720.080),
        (52.516272, 13.377722, 33, "U", 389919.255, 5819698.772),
        (-33.856800, 151.215300, 56, "H", 334900.570, 6252288.753),
        (60.390000, 5.320000, 32, "V", 297230.220, 6700510.176),   // Norway exception
        (78.220000, 15.650000, 33, "X", 514813.527, 8683004.154),  // Svalbard exception
        (0.000100, -0.000100, 30, "N", 833967.414, 11.068),
        (-0.500000, -78.500000, 17, "M", 778265.778, 9944681.960),
        (47.606200, -122.332100, 10, "T", 550200.213, 5272748.592),
        (-54.800000, -68.300000, 19, "F", 545000.053, 3927239.381),
        (40.712800, -74.006000, 18, "T", 583959.372, 4507350.998),
    ]

    @Test func matchesCachebox() throws {
        for (lat, lon, zone, band, easting, northing) in Self.reference {
            let utm = try #require(UTMCoordinate(Coordinate(latitude: lat, longitude: lon)))
            #expect(utm.zone == zone, "\(lat) \(lon)")
            #expect(utm.band == band, "\(lat) \(lon)")
            #expect(abs(utm.easting - easting) < 1, "\(lat) \(lon): \(utm.easting)")
            #expect(abs(utm.northing - northing) < 1, "\(lat) \(lon): \(utm.northing)")
        }
    }

    @Test func roundTrip() throws {
        for (lat, lon, _, _, _, _) in Self.reference {
            let back = try #require(UTMCoordinate(Coordinate(latitude: lat, longitude: lon))).coordinate
            #expect(abs(back.latitude - lat) < 1e-9 && abs(back.longitude - lon) < 1e-9, "\(lat) \(lon) → \(back)")
        }
    }

    @Test func outsideUTM() {
        #expect(UTMCoordinate(Coordinate(latitude: 85, longitude: 10)) == nil)
        #expect(UTMCoordinate(Coordinate(latitude: -81, longitude: 10)) == nil)
        #expect(UTMCoordinate.band(latitude: 84) == "X")
        #expect(UTMCoordinate.band(latitude: -80) == "C")
        #expect(UTMCoordinate.zone(latitude: 0, longitude: 180) == 1)   // same meridian as -180, like Cachebox
    }
}

@Suite("Coordinate entry")
struct CoordinateEntryTests {
    static let bremen = Coordinate(latitude: 53.0758, longitude: 8.8072)   // N 53° 04.548 E 008° 48.432

    @Test func minutesCellsAndFocus() {
        var entry = CoordinateEntry(coordinate: Self.bremen)
        #expect(entry.format == .minutes)
        #expect(entry.cells == ["N", "0", "5", "3", "0", "4", "5", "4", "8", "E", "0", "0", "8", "4", "8", "4", "3", "2"])
        #expect(entry.focus == 6)   // first decimal of the latitude minutes
        entry.enter(digit: 1)
        entry.enter(digit: 2)
        #expect(entry.focus == 8)
        entry.enter(digit: 3)
        #expect(entry.focus == 15)  // jumps to the first decimal of the longitude minutes
        entry.enter(digit: 7)
        entry.enter(digit: 8)
        entry.enter(digit: 9)
        #expect(entry.focus == 2)   // after the longitude: the degrees of the latitude
        let parsed = try! #require(entry.parse())
        #expect(abs(parsed.latitude - (53 + 4.123 / 60)) < 1e-12)
        #expect(abs(parsed.longitude - (8 + 48.789 / 60)) < 1e-12)
    }

    @Test func degreesAndSecondsFocus() {
        var entry = CoordinateEntry(coordinate: Self.bremen, format: .degrees)
        #expect(entry.cells.joined() == "N05307580E00880720")
        #expect(entry.focus == 4)
        for _ in 0..<5 { entry.enter(digit: 0) }
        #expect(entry.focus == 13)
        entry = CoordinateEntry(coordinate: Self.bremen, format: .seconds)
        #expect(entry.cells.joined() == "N053043288E008482592")
        #expect(entry.focus == 6)
        for _ in 0..<4 { entry.enter(digit: 1) }
        #expect(entry.focus == 16)
        for _ in 0..<4 { entry.enter(digit: 1) }
        #expect(entry.focus == 2)
    }

    @Test func tapsAndHemispheres() throws {
        var entry = CoordinateEntry(coordinate: Self.bremen)
        entry.tap(0)
        entry.tap(9)
        #expect(entry.cells[0] == "S" && entry.cells[9] == "W")
        #expect(entry.focus == 6)            // hemispheres do not take the focus
        entry.tap(1)                         // hidden hundreds of the latitude
        #expect(entry.focus == 6)
        entry.tap(10)
        #expect(entry.focus == 10)
        entry.enter(digit: 1)
        let parsed = try #require(entry.parse())
        #expect(parsed.latitude < 0)
        #expect(abs(parsed.longitude + (108 + 48.432 / 60)) < 1e-12)
    }

    @Test func roundingCarriesIntoDegrees() {
        // 59.99996' would be "60.000" when rounding the decimals alone
        let entry = CoordinateEntry(coordinate: Coordinate(latitude: 47.9999994, longitude: -0.0000001))
        #expect(entry.cells.joined() == "N04800000W00000000")
    }

    @Test func invalidInput() {
        var entry = CoordinateEntry(coordinate: Self.bremen)
        entry.tap(4)
        entry.enter(digit: 7)                // 74 minutes
        #expect(entry.parse() == nil)
        entry = CoordinateEntry(coordinate: Self.bremen)
        entry.tap(2)
        entry.enter(digit: 9)
        entry.enter(digit: 1)                // N 91°
        #expect(entry.parse() == nil)
    }

    @Test func formatSwitchKeepsCoordinate() throws {
        var entry = CoordinateEntry(coordinate: Self.bremen)
        for format in [CoordinateEntry.Format.degrees, .seconds, .utm, .minutes] {
            entry.select(format)
            let parsed = try #require(entry.parse())
            #expect(parsed.distance(to: Self.bremen) < 1, "\(format)")
        }
        // an invalid entry keeps the last valid coordinate when switching
        entry.tap(4)
        entry.enter(digit: 9)
        entry.select(.degrees)
        #expect(try #require(entry.parse()).distance(to: Self.bremen) < 1)
    }

    @Test func utmInput() throws {
        var entry = CoordinateEntry(coordinate: Self.bremen, format: .utm)
        // 32U 487084 5880720
        #expect(entry.cells == ["4", "8", "7", "0", "8", "4", "5", "8", "8", "0", "7", "2", "0", "", "3", "2", "U"])
        #expect(entry.focus == 0)
        for _ in 0..<13 { entry.enter(digit: 5) }   // easting 555555, northing 5555555
        #expect(entry.focus == 13)
        entry.enterBlank()                          // the eighth northing cell stays empty
        entry.enter(digit: 3)
        entry.enter(digit: 3)
        #expect(entry.expectsLetter)
        entry.enter(digit: 1)                       // the number pad does nothing on the band
        entry.enter(letter: "i")                    // no band I
        #expect(entry.focus == 16)
        entry.enter(letter: "t")
        #expect(entry.cells[16] == "T" && entry.focus == 0)
        let parsed = try #require(entry.parse())
        let expected = UTMCoordinate(zone: 33, band: "T", easting: 555555, northing: 5555555).coordinate
        #expect(parsed == expected)
    }

    @Test func utmInvalid() {
        var entry = CoordinateEntry(coordinate: Self.bremen, format: .utm)
        entry.tap(14)
        entry.enter(digit: 9)
        entry.enter(digit: 9)                       // zone 99
        #expect(entry.parse() == nil)
    }
}

@Suite("Coordinate parser")
struct CoordinateParserTests {
    private func check(_ text: String, _ lat: Double, _ lon: Double, tolerance: Double = 1e-9) {
        guard let c = Coordinate(parsing: text) else {
            Issue.record("not parsed: \(text)")
            return
        }
        #expect(abs(c.latitude - lat) < tolerance && abs(c.longitude - lon) < tolerance, "\(text) → \(c)")
    }

    @Test func formats() {
        let lat = 53 + 4.548 / 60, lon = 8 + 48.432 / 60
        check("N 53° 04.548 E 008° 48.432", lat, lon)
        check(CoordinateEntryTests.bremen.formatted, 53.0758, 8.8072, tolerance: 1e-6)
        check("N53 04.548 / E8 48.432", lat, lon)
        check("n 53° 04,548 e 008° 48,432", lat, lon)
        check("S 53° 04.548 W 008° 48.432", -lat, -lon)
        check("53° 04.548 N 008° 48.432 E", lat, lon)
        check("N 53.0758° E 8.8072°", 53.0758, 8.8072)
        check("N 53° 04' 32.88\" E 8° 48' 25.92\"", 53 + 4 / 60.0 + 32.88 / 3600, 8 + 48 / 60.0 + 25.92 / 3600)
        check("53.0758 -8.8072", 53.0758, -8.8072)
        check("32U 487084 5880720", 53.0758, 8.8072, tolerance: 1e-4)
        check("32U E 487084 N 5880720", 53.0758, 8.8072, tolerance: 1e-4)
    }

    @Test func rejects() {
        for text in ["", "hallo", "N 53° 64.000 E 8° 0.000", "N 91 E 8", "E 8 N 53", "53.1", "N 53 04.5 E 8 48.4 x"] {
            #expect(Coordinate(parsing: text) == nil, "\(text)")
        }
    }
}

@Suite("User waypoints")
struct UserWaypointTests {
    @Test func saveDeleteAndStart() throws {
        let database = try Fixture.database()
        try database.upsert(Geocache(code: "GCTEST1", name: "Test", coordinate: Coordinate(latitude: 53, longitude: 8),
                                     type: .multi))
        let first = try database.freeWaypointCode(cacheCode: "GCTEST1")
        #expect(first == "C0TEST1")
        var stage = Waypoint(code: first, cacheCode: "GCTEST1", title: "Stage 1", comment: "Schild", clue: "unten",
                             type: .stage, coordinate: Coordinate(latitude: 53.1, longitude: 8.1), isStart: true)
        try database.saveUserWaypoint(stage)
        #expect(try database.freeWaypointCode(cacheCode: "GCTEST1") == "C1TEST1")
        let second = Waypoint(code: "C1TEST1", cacheCode: "GCTEST1", title: "Stage 2", type: .stage,
                              coordinate: Coordinate(latitude: 53.2, longitude: 8.2), isStart: true)
        try database.saveUserWaypoint(second)

        var waypoints = try database.waypoints(cacheCode: "GCTEST1")
        #expect(waypoints.count == 2)
        #expect(waypoints[0].clue == "unten" && waypoints[0].comment == "Schild" && waypoints[0].isUserCreated)
        #expect(waypoints.filter(\.isStart).map(\.code) == ["C1TEST1"])   // only one start per cache

        // an import does not replace the user's waypoint
        stage.title = "aus GPX"
        stage.isUserCreated = false
        try database.upsert(stage)
        #expect(try database.waypoints(cacheCode: "GCTEST1")[0].title == "Stage 1")

        try database.deleteWaypoint(code: first, cacheCode: "GCTEST1")
        waypoints = try database.waypoints(cacheCode: "GCTEST1")
        #expect(waypoints.map(\.code) == ["C1TEST1"])
    }

    @Test func migratesVersion1() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "cacheboxcore-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "v1.db3")
        do {
            // the schema of version 1 (without clue and is_start), with one waypoint
            let db = try SQLiteConnection(url: url)
            try db.execute("""
                CREATE TABLE caches (code TEXT PRIMARY KEY, name TEXT NOT NULL);
                CREATE TABLE waypoints (
                    cache_code TEXT NOT NULL, code TEXT NOT NULL, title TEXT NOT NULL DEFAULT '',
                    comment TEXT NOT NULL DEFAULT '', type TEXT NOT NULL, latitude REAL, longitude REAL,
                    user_created INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (cache_code, code));
                INSERT INTO waypoints (cache_code, code, title, type, latitude, longitude)
                    VALUES ('GCX', 'PKX', 'Parken', 'parking', 53, 8);
                PRAGMA user_version = 1;
                """)
        }
        let database = try CacheDatabase(url: url)
        let waypoints = try database.waypoints(cacheCode: "GCX")
        #expect(waypoints.count == 1 && waypoints[0].title == "Parken" && waypoints[0].clue == "" && !waypoints[0].isStart)
        _ = try CacheDatabase(url: url)   // opening again does not migrate twice
    }
}
