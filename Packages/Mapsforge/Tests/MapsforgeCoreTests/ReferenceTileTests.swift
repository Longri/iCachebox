import Foundation
import Testing
@testable import MapsforgeCore

/// Locates `TestData/` at the repository root (walking up from this file).
enum TestData {
    static func url(_ name: String) -> URL? {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir.appendingPathComponent("TestData").appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }
}

@Suite("bremen.map vs. Java reference (mapsforge 0.21.0)")
struct ReferenceTileTests {

    @Test func headerMatchesReference() throws {
        let url = try #require(TestData.url("bremen.map"), "TestData/bremen.map missing – see CLAUDE.md")
        let map = try MapFile(url: url)
        #expect(map.info.fileVersion == 5)
        #expect(map.info.fileSize == 13_933_274)
        #expect(map.info.tilePixelSize == 256)
        #expect(map.info.mapDate == 1_767_792_848_826)
        #expect(map.info.createdBy == "mapsforge-map-writer-master-SNAPSHOT")
        #expect(map.info.comment == "Map data (c) OpenStreetMap contributors")
        #expect(map.info.languagesPreference == "en,de,fr,es")
        #expect(map.info.poiTags.count == 83)
        #expect(map.info.wayTags.count == 283)
        #expect(map.info.poiTags[0] == MapsforgeCore.Tag(key: "amenity", value: "bench"))
        #expect(map.info.zoomLevelMin == 0)
        #expect(map.info.zoomLevelMax == 21)
        #expect(map.info.startZoomLevel == 8)
        #expect(abs(map.info.boundingBox.minLatitude - 52.910340) < 1e-6)
        #expect(abs(map.info.boundingBox.maxLongitude - 9.091268) < 1e-6)
    }

    @Test func tilesMatchReference() throws {
        let mapURL = try #require(TestData.url("bremen.map"))
        let jsonURL = try #require(TestData.url("expected-bremen-tiles.json"))
        let map = try MapFile(url: mapURL)
        let doc = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: jsonURL)) as? [String: Any])
        let tiles = try #require(doc["tiles"] as? [[String: Any]])
        #expect(tiles.count == 4)

        for expected in tiles {
            let z = expected["zoomLevel"] as! Int
            let x = expected["tileX"] as! Int
            let y = expected["tileY"] as! Int
            let tile = Tile(tileX: x, tileY: y, zoomLevel: z, tileSize: 256)
            let label = "z\(z)/\(x)/\(y)"

            let bbox = expected["boundingBox"] as! [String: Double]
            #expect(close(tile.boundingBox.minLatitude, bbox["minLat"]!), "\(label) bbox")
            #expect(close(tile.boundingBox.maxLongitude, bbox["maxLon"]!), "\(label) bbox")

            let result = try #require(map.readMapData(tile), "\(label) returned nil")
            let pois = expected["pois"] as! [[String: Any]]
            let ways = expected["ways"] as! [[String: Any]]
            #expect(result.pointOfInterests.count == pois.count, "\(label) POI count")
            #expect(result.ways.count == ways.count, "\(label) way count")

            var poiMismatches = 0
            for (actual, exp) in zip(result.pointOfInterests, pois) {
                if !matches(actual, exp) {
                    poiMismatches += 1
                    if poiMismatches <= 3 { Issue.record("\(label) POI mismatch: \(actual) vs \(exp)") }
                }
            }
            var wayMismatches = 0
            for (actual, exp) in zip(result.ways, ways) {
                if !matches(actual, exp) {
                    wayMismatches += 1
                    if wayMismatches <= 3 { Issue.record("\(label) way mismatch: \(actual.tags) vs \(exp["tags"] ?? "")") }
                }
            }
            #expect(poiMismatches == 0, "\(label): \(poiMismatches) POI mismatches")
            #expect(wayMismatches == 0, "\(label): \(wayMismatches) way mismatches")
        }
    }

    // MARK: helpers

    private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    private func tagDict(_ tags: [MapsforgeCore.Tag]) -> [String: String] {
        var d = [String: String]()
        for t in tags { d[t.key] = t.value }   // LinkedHashMap semantics: last wins
        return d
    }

    private func matches(_ poi: PointOfInterest, _ exp: [String: Any]) -> Bool {
        let layer = exp["layer"] as? Int ?? 0
        let tags = exp["tags"] as? [String: String] ?? [:]
        return Int(poi.layer) == layer
            && close(poi.position.latitude, exp["lat"] as! Double)
            && close(poi.position.longitude, exp["lon"] as! Double)
            && tagDict(poi.tags) == tags
    }

    private func matches(_ way: Way, _ exp: [String: Any]) -> Bool {
        let layer = exp["layer"] as? Int ?? 0
        let tags = exp["tags"] as? [String: String] ?? [:]
        guard Int(way.layer) == layer, tagDict(way.tags) == tags else { return false }
        if let lp = exp["labelPosition"] as? [String: Double] {
            guard let actual = way.labelPosition, close(actual.latitude, lp["lat"]!), close(actual.longitude, lp["lon"]!) else { return false }
        } else if way.labelPosition != nil {
            return false
        }
        let geometry = exp["geometry"] as? [[[String: Double]]] ?? []
        guard geometry.count == way.latLongs.count else { return false }
        for (ring, expRing) in zip(way.latLongs, geometry) {
            guard ring.count == expRing.count else { return false }
            for (p, e) in zip(ring, expRing) where !close(p.latitude, e["lat"]!) || !close(p.longitude, e["lon"]!) {
                return false
            }
        }
        return true
    }
}
