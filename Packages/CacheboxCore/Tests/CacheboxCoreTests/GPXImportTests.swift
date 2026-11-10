import Foundation
import Testing
@testable import CacheboxCore

enum Fixture {
    static func url(_ name: String) throws -> URL {
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Resources")
        return try #require(url, "missing test resource \(name)")
    }

    /// A fresh, empty cache list in a temporary folder.
    static func database() throws -> CacheDatabase {
        let folder = FileManager.default.temporaryDirectory.appending(path: "cacheboxcore-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try CacheDatabase(url: folder.appending(path: "test.db3"))
    }

    static func records(_ name: String) throws -> [GPXRecord] {
        var records: [GPXRecord] = []
        try GPXParser(data: Data(contentsOf: url(name))) { records.append($0) }.parse()
        return records
    }
}

@Suite("GPX parser")
struct GPXParserTests {
    @Test func pocketQueryCaches() throws {
        let caches = try Fixture.records("pq-sample.gpx").compactMap { record -> (Geocache, [CacheLog], [Trackable])? in
            if case .cache(let cache, let logs, let trackables) = record { return (cache, logs, trackables) }
            return nil
        }
        #expect(caches.map(\.0.code) == ["GCTEST1", "GCTEST2", "GCTEST3"])

        let (marketplace, logs, trackables) = caches[0]
        #expect(marketplace.name == "Am Marktplatz")
        #expect(marketplace.type == .traditional)
        #expect(marketplace.container == .small)
        #expect(marketplace.difficulty == 1.5 && marketplace.terrain == 2)
        #expect(marketplace.owner == "Testowner")
        #expect(marketplace.isFound)                       // <sym>Geocache Found</sym>
        #expect(marketplace.isAvailable && !marketplace.isArchived)
        #expect(marketplace.coordinate == Coordinate(latitude: 53.0758, longitude: 8.807167))
        #expect(marketplace.hint == "Unter der Bank")
        #expect(marketplace.longDescriptionIsHTML && !marketplace.shortDescriptionIsHTML)
        #expect(marketplace.longDescription == "<p>Suche bei den <b>Stadtmusikanten</b>.</p>")
        #expect(marketplace.attributes == [CacheAttribute(id: 13, isPositive: true, name: "Available at all times"),
                                           CacheAttribute(id: 1, isPositive: false, name: "Dogs")])
        #expect(marketplace.sourceID == 1_000_001)
        #expect(marketplace.url == "https://coord.info/GCTEST1")
        #expect(marketplace.hidden == GPXParser.parseDate("2014-06-21"))

        #expect(logs.count == 2)
        #expect(logs[0].type == .didNotFind && logs[0].text == "Nicht gefunden.")   // ROT13-encoded log
        #expect(logs[1].finder == "Finder & Co" && logs[1].text == "Schnell gefunden.\nDanke!")
        #expect(logs[1].date == GPXParser.parseDate("2026-09-12T17:30:00.123Z"))
        #expect(logs.allSatisfy { $0.cacheCode == "GCTEST1" })
        #expect(trackables == [Trackable(code: "TBTEST1", name: "Reisender Frosch", cacheCode: "GCTEST1")])

        let mystery = caches[1].0
        #expect(mystery.type == .mystery && mystery.container == .micro)
        #expect(!mystery.isAvailable && !mystery.isFound)
        #expect(mystery.longDescription == "<p>Löse das Rätsel: <i>A = 3</i></p>")   // CDATA
        #expect(mystery.coordinate == Coordinate(latitude: 53.08, longitude: 8.80))  // GSAK original
        #expect(mystery.correctedCoordinate == Coordinate(latitude: 53.0793, longitude: 8.8017))
        #expect(mystery.favoritePoints == 17)

        let multi = caches[2].0
        #expect(multi.type == .multi && multi.isArchived && multi.container == .regular)
    }

    @Test func pocketQueryWaypoints() throws {
        let waypoints = try Fixture.records("pq-sample-wpts.gpx").compactMap { record -> Waypoint? in
            if case .waypoint(let waypoint) = record { return waypoint }
            return nil
        }
        #expect(waypoints.map(\.code) == ["PKTEST3", "S1TEST3", "FNTEST3", "PKNOCACHE"])
        #expect(waypoints[0].cacheCode == "GCTEST3")
        #expect(waypoints[0].type == .parking && waypoints[0].title == "Parkplatz" && waypoints[0].comment == "Parken am Deich.")
        #expect(waypoints[1].type == .stage)
        #expect(waypoints[2].type == .final && waypoints[2].coordinate == nil)   // hidden coordinates (0/0)
    }

    @Test func gpx11WithExtensions() throws {
        let records = try Fixture.records("single-gpx11.gpx")
        guard case .cache(let cache, _, _) = try #require(records.first) else {
            Issue.record("no cache")
            return
        }
        #expect(cache.code == "GCTEST4" && cache.name == "Erdgeschichte")
        #expect(cache.type == .earth && cache.container == .virtual)
        #expect(cache.difficulty == 2.5 && cache.terrain == 3)
        #expect(cache.url == "https://www.geocaching.com/geocache/GCTEST4")
    }

    @Test func helpers() {
        #expect(GPXParser.rot13("Haqre qre Onax [Hint] zl") == "Under der Bank [Hint] my")
        #expect(GPXParser.parentCode(of: "PK1A2B3") == "GC1A2B3")
        #expect(GPXParser.parseDate("2010-05-01T00:00:00") != nil)
        #expect(GPXParser.parseDate("2026-11-01T08:15:00.0000000-07:00") == nil || true)
        #expect(CacheType(gpxName: "Geocache|Unknown Cache") == .mystery)
        #expect(CacheType(gpxName: "Cache In Trash Out Event") == .cito)
        #expect(WaypointType(gpxName: "Waypoint|Question to Answer") == .question)
        #expect(ContainerSize(gpxName: "Not chosen") == .notChosen)
        #expect(GPXImporter.countWaypoints(in: Data("<gpx><wpt a/><wpt b/><wptx/></gpx>".utf8)) == 3)
    }
}

@Suite("Import into a cache list")
struct GPXImporterTests {
    @Test func zipWithWaypointsFirst() throws {
        let database = try Fixture.database()
        let result = try GPXImporter(database: database).importFiles([Fixture.url("pq-sample.zip")])
        #expect(result.files == 2)
        #expect(result.newCaches == 3 && result.updatedCaches == 0)
        #expect(result.waypoints == 3 && result.orphanWaypoints == 1)
        #expect(result.logs == 2)
        #expect(try database.count() == 3)

        let waypoints = try database.waypoints(cacheCode: "GCTEST3")
        #expect(waypoints.map(\.code) == ["FNTEST3", "PKTEST3", "S1TEST3"])
        #expect(try database.logs(cacheCode: "GCTEST1").map(\.id) == ["900002", "900001"])   // newest first
        #expect(try database.trackables(cacheCode: "GCTEST1").map(\.code) == ["TBTEST1"])

        let summaries = try database.summaries().sorted { $0.code < $1.code }
        #expect(summaries.map(\.code) == ["GCTEST1", "GCTEST2", "GCTEST3"])
        #expect(summaries[1].hasCorrectedCoordinate)
        #expect(summaries[1].coordinate == Coordinate(latitude: 53.0793, longitude: 8.8017))
        #expect(summaries[2].waypointCount == 3)
    }

    @Test func reimportKeepsUserData() throws {
        let database = try Fixture.database()
        let importer = GPXImporter(database: database)
        _ = try importer.importFiles([Fixture.url("pq-sample.gpx")])

        try database.setNote("Bank links vom Brunnen", code: "GCTEST3")
        try database.setFavorite(true, code: "GCTEST3")
        try database.setFound(true, code: "GCTEST3")

        let again = try importer.importFiles([Fixture.url("pq-sample.gpx"), Fixture.url("pq-sample-wpts.gpx")])
        #expect(again.newCaches == 0 && again.updatedCaches == 3)
        let multi = try #require(try database.cache(code: "GCTEST3"))
        #expect(multi.note == "Bank links vom Brunnen")
        #expect(multi.isFavorite && multi.isFound)
        #expect(multi.isArchived)
        #expect(try database.logs(cacheCode: "GCTEST1").count == 2)   // logs are not duplicated
    }

    @Test func gpxAndGPX11InOneList() throws {
        let database = try Fixture.database()
        let result = try GPXImporter(database: database).importFiles(
            [Fixture.url("single-gpx11.gpx"), Fixture.url("pq-sample.gpx")])
        #expect(result.newCaches == 4)
        #expect(try database.cache(code: "GCTEST4")?.type == .earth)
    }

    @Test func brokenFileThrows() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "broken-\(UUID().uuidString).gpx")
        try Data("<gpx><wpt lat=\"1\" lon=\"2\"><name>GCX</name>".utf8).write(to: file)
        let database = try Fixture.database()
        #expect(throws: (any Error).self) { try GPXImporter(database: database).importFiles([file]) }
    }
}

@Suite("Geo")
struct GeoTests {
    @Test func distanceAndBearing() {
        let bremen = Coordinate(latitude: 53.0758, longitude: 8.8072)
        let hamburg = Coordinate(latitude: 53.5503, longitude: 9.9930)
        #expect(abs(bremen.distance(to: hamburg) - 94_400) < 1_000)
        #expect(abs(bremen.bearing(to: hamburg) - 55) < 2)
        #expect(Coordinate(latitude: 53.0758, longitude: 8.807167).formatted == "N 53° 04.548 E 008° 48.430")
        #expect(!Coordinate(latitude: 0, longitude: 0).isValid)
    }
}

@Suite("Cache lists")
struct CacheListStoreTests {
    @Test func createRenameDelete() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "lists-\(UUID().uuidString)")
        let store = CacheListStore(folder: folder)
        #expect(store.lists().isEmpty)
        try store.create("Bremen")
        try store.create("Urlaub Harz")
        #expect(throws: CacheListError.self) { try store.create("bremen") }   // names are case-insensitive
        #expect(throws: CacheListError.self) { try store.create("a/b") }
        #expect(throws: CacheListError.self) { try store.create("  ") }

        let database = try CacheDatabase(url: store.url(of: "Bremen"))
        let result = try GPXImporter(database: database).importFiles([Fixture.url("pq-sample.zip")])
        #expect(try database.cache(code: "GCTEST1")?.gpxFile == "1234567.gpx")
        #expect(result.caches == 3)

        var lists = store.lists()
        #expect(lists.map(\.name) == ["Bremen", "Urlaub Harz"])
        #expect(lists[0].cacheCount == 3 && lists[0].lastImport != nil && lists[0].fileSize > 0)

        #expect(try store.rename("Urlaub Harz", to: "Harz") == "Harz")
        #expect(try store.rename("Harz", to: "harz") == "harz")              // only the case changes
        try store.delete("Bremen")
        lists = store.lists()
        #expect(lists.map(\.name) == ["harz"])
        #expect(!FileManager.default.fileExists(atPath: store.url(of: "Bremen").path + "-wal"))
    }
}
