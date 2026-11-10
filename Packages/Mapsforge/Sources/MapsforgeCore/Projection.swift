// Port of org.mapsforge.core.util.MercatorProjection and LatLongUtils (subset).
// Licensed under LGPL-3.0 like the original mapsforge code.

import Foundation

public enum LatLongUtils {
    public static let equatorialRadius = 6378137.0
    public static let longitudeMin = -180.0
    public static let longitudeMax = 180.0
    static let conversionFactor = 1000000.0

    @inlinable
    public static func microdegreesToDegrees(_ coordinate: Int32) -> Double {
        Double(coordinate) / 1000000.0
    }

    public static func latitudeDistance(_ meters: Int) -> Double {
        Double(meters * 360) / (2 * Double.pi * equatorialRadius)
    }

    public static func longitudeDistance(_ meters: Int, latitude: Double) -> Double {
        // 0.017453292519943295 == java.lang.Math.DEGREES_TO_RADIANS (keeps results bit-identical to Java)
        Double(meters * 360) / (2 * Double.pi * equatorialRadius * cos(latitude * 0.017453292519943295))
    }
}

public enum MercatorProjection {
    public static let latitudeMax = 85.05112877980659
    public static let latitudeMin = -85.05112877980659
    static let dummyTileSize = 256

    @inlinable
    public static func mapSize(zoomLevel: Int, tileSize: Int) -> Int64 {
        Int64(tileSize) << Int64(zoomLevel)
    }

    @inlinable
    public static func latitudeToPixelY(_ latitude: Double, mapSize: Int64) -> Double {
        let sinLatitude = sin(latitude * (Double.pi / 180))
        let pixelY = (0.5 - log((1 + sinLatitude) / (1 - sinLatitude)) / (4 * Double.pi)) * Double(mapSize)
        return min(max(0, pixelY), Double(mapSize))
    }

    @inlinable
    public static func longitudeToPixelX(_ longitude: Double, mapSize: Int64) -> Double {
        (longitude + 180) / 360 * Double(mapSize)
    }

    public static func pixelXToLongitude(_ pixelX: Double, mapSize: Int64) -> Double {
        360 * ((pixelX / Double(mapSize)) - 0.5)
    }

    public static func pixelYToLatitude(_ pixelY: Double, mapSize: Int64) -> Double {
        let y = 0.5 - (pixelY / Double(mapSize))
        return 90 - 360 * atan(exp(-y * (2 * Double.pi))) / Double.pi
    }

    public static func pixelXToTileX(_ pixelX: Double, zoomLevel: Int, tileSize: Int) -> Int {
        Int(min(max(pixelX / Double(tileSize), 0), pow(2, Double(zoomLevel)) - 1))
    }

    public static func pixelYToTileY(_ pixelY: Double, zoomLevel: Int, tileSize: Int) -> Int {
        Int(min(max(pixelY / Double(tileSize), 0), pow(2, Double(zoomLevel)) - 1))
    }

    public static func latitudeToTileY(_ latitude: Double, zoomLevel: Int) -> Int {
        let ms = mapSize(zoomLevel: zoomLevel, tileSize: dummyTileSize)
        return pixelYToTileY(latitudeToPixelY(latitude, mapSize: ms), zoomLevel: zoomLevel, tileSize: dummyTileSize)
    }

    public static func longitudeToTileX(_ longitude: Double, zoomLevel: Int) -> Int {
        let ms = mapSize(zoomLevel: zoomLevel, tileSize: dummyTileSize)
        return pixelXToTileX(longitudeToPixelX(longitude, mapSize: ms), zoomLevel: zoomLevel, tileSize: dummyTileSize)
    }

    public static func tileXToLongitude(_ tileX: Int, zoomLevel: Int) -> Double {
        pixelXToLongitude(Double(tileX * dummyTileSize), mapSize: mapSize(zoomLevel: zoomLevel, tileSize: dummyTileSize))
    }

    public static func tileYToLatitude(_ tileY: Int, zoomLevel: Int) -> Double {
        pixelYToLatitude(Double(tileY * dummyTileSize), mapSize: mapSize(zoomLevel: zoomLevel, tileSize: dummyTileSize))
    }
}
