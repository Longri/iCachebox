// Port of org.mapsforge.core.model (LatLong, BoundingBox, Tag, Tile, Point)
// and org.mapsforge.map.datastore (PointOfInterest, Way, MapReadResult).
// Licensed under LGPL-3.0 like the original mapsforge code.

import Foundation

public struct LatLong: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double

    @inlinable
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct BoundingBox: Equatable, Sendable {
    public var minLatitude: Double
    public var minLongitude: Double
    public var maxLatitude: Double
    public var maxLongitude: Double

    public init(minLatitude: Double, minLongitude: Double, maxLatitude: Double, maxLongitude: Double) {
        self.minLatitude = minLatitude
        self.minLongitude = minLongitude
        self.maxLatitude = maxLatitude
        self.maxLongitude = maxLongitude
    }

    @inlinable
    public func contains(_ p: LatLong) -> Bool {
        minLatitude <= p.latitude && maxLatitude >= p.latitude
            && minLongitude <= p.longitude && maxLongitude >= p.longitude
    }

    public func intersects(_ o: BoundingBox) -> Bool {
        maxLatitude >= o.minLatitude && maxLongitude >= o.minLongitude
            && minLatitude <= o.maxLatitude && minLongitude <= o.maxLongitude
    }

    /// Same semantics as mapsforge `BoundingBox.intersectsArea(LatLong[][])`.
    public func intersectsArea(_ latLongs: [[LatLong]]) -> Bool {
        guard let first = latLongs.first?.first else { return false }
        for ring in latLongs {
            for p in ring where contains(p) { return true }
        }
        var minLat = first.latitude, minLon = first.longitude
        var maxLat = first.latitude, maxLon = first.longitude
        for ring in latLongs {
            for p in ring {
                minLat = min(minLat, p.latitude)
                maxLat = max(maxLat, p.latitude)
                minLon = min(minLon, p.longitude)
                maxLon = max(maxLon, p.longitude)
            }
        }
        return intersects(BoundingBox(minLatitude: minLat, minLongitude: minLon, maxLatitude: maxLat, maxLongitude: maxLon))
    }

    public func extendMeters(_ meters: Int) -> BoundingBox {
        if meters == 0 { return self }
        let vertical = LatLongUtils.latitudeDistance(meters)
        let horizontal = LatLongUtils.longitudeDistance(meters, latitude: max(abs(minLatitude), abs(maxLatitude)))
        return BoundingBox(
            minLatitude: max(MercatorProjection.latitudeMin, minLatitude - vertical),
            minLongitude: max(-180, minLongitude - horizontal),
            maxLatitude: min(MercatorProjection.latitudeMax, maxLatitude + vertical),
            maxLongitude: min(180, maxLongitude + horizontal))
    }

    public func extend(_ o: BoundingBox) -> BoundingBox {
        BoundingBox(
            minLatitude: min(minLatitude, o.minLatitude),
            minLongitude: min(minLongitude, o.minLongitude),
            maxLatitude: max(maxLatitude, o.maxLatitude),
            maxLongitude: max(maxLongitude, o.maxLongitude))
    }

    public var centerPoint: LatLong {
        LatLong(latitude: minLatitude + (maxLatitude - minLatitude) / 2,
                longitude: minLongitude + (maxLongitude - minLongitude) / 2)
    }
}

public struct Tag: Hashable, Sendable, CustomStringConvertible {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }

    /// Parses the textual `key=value` representation used in the map file header.
    public init(_ text: String) {
        if let idx = text.firstIndex(of: "=") {
            key = String(text[..<idx])
            value = String(text[text.index(after: idx)...])
        } else {
            key = text
            value = ""
        }
    }

    public var description: String { "\(key)=\(value)" }
}

public struct Point: Equatable, Sendable {
    public var x: Double
    public var y: Double

    @inlinable
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A map tile in the standard slippy-map scheme. `tileSize` only affects the pixel
/// resolution; the geographic area is defined by x, y and zoomLevel alone.
public struct Tile: Hashable, Sendable, CustomStringConvertible {
    public let tileX: Int
    public let tileY: Int
    public let zoomLevel: Int
    public let tileSize: Int

    public init(tileX: Int, tileY: Int, zoomLevel: Int, tileSize: Int = 256) {
        self.tileX = tileX
        self.tileY = tileY
        self.zoomLevel = zoomLevel
        self.tileSize = tileSize
    }

    public var mapSize: Int64 { MercatorProjection.mapSize(zoomLevel: zoomLevel, tileSize: tileSize) }

    /// Top-left pixel of this tile in absolute map pixel coordinates.
    public var origin: Point {
        Point(x: Double(tileX * tileSize), y: Double(tileY * tileSize))
    }

    public var boundingBox: BoundingBox {
        let minLat = max(MercatorProjection.latitudeMin, MercatorProjection.tileYToLatitude(tileY + 1, zoomLevel: zoomLevel))
        let minLon = max(-180, MercatorProjection.tileXToLongitude(tileX, zoomLevel: zoomLevel))
        let maxLat = min(MercatorProjection.latitudeMax, MercatorProjection.tileYToLatitude(tileY, zoomLevel: zoomLevel))
        var maxLon = min(180, MercatorProjection.tileXToLongitude(tileX + 1, zoomLevel: zoomLevel))
        if maxLon == -180 { maxLon = 180 }
        return BoundingBox(minLatitude: minLat, minLongitude: minLon, maxLatitude: maxLat, maxLongitude: maxLon)
    }

    public static func boundingBox(_ upperLeft: Tile, _ lowerRight: Tile) -> BoundingBox {
        upperLeft.boundingBox.extend(lowerRight.boundingBox)
    }

    public var description: String { "Tile(z=\(zoomLevel) x=\(tileX) y=\(tileY) size=\(tileSize))" }
}

public struct PointOfInterest: Sendable {
    public let layer: Int8
    public let tags: [Tag]
    public let position: LatLong
}

public struct Way: Sendable {
    public let layer: Int8
    public let tags: [Tag]
    /// First ring is the outer ring, following rings are inner rings (holes).
    public let latLongs: [[LatLong]]
    public let labelPosition: LatLong?

    public init(layer: Int8, tags: [Tag], latLongs: [[LatLong]], labelPosition: LatLong?) {
        self.layer = layer
        self.tags = tags
        self.latLongs = latLongs
        self.labelPosition = labelPosition
    }
}

public struct MapReadResult: Sendable {
    public var pointOfInterests: [PointOfInterest] = []
    public var ways: [Way] = []
    public var isWater = false

    public init() {}

    mutating func add(pois: [PointOfInterest], ways: [Way]) {
        pointOfInterests.append(contentsOf: pois)
        self.ways.append(contentsOf: ways)
    }
}
