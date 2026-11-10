// Port of org.mapsforge.map.reader.MapFile, IndexCache, QueryParameters and
// QueryCalculations, plus MapDataStore.extract for multilingual names.
// Licensed under LGPL-3.0 like the original mapsforge code.

import Foundation

/// Read access to a mapsforge binary map file (`.map`, format version 3–5).
///
/// Thread-safe: file access uses `pread` (no shared file position) and the
/// index cache is guarded by a lock, so tiles may be read from several threads.
public final class MapFile: @unchecked Sendable {
    public static var wayFilterEnabled: Bool { true }
    public static let wayFilterDistance = 20

    private static let bitmaskIndexOffset: Int64 = 0x7F_FFFF_FFFF
    private static let bitmaskIndexWater: Int64 = 0x80_0000_0000
    private static let maximumBufferSize = 10_000_000

    public let url: URL
    public let info: MapFileInfo
    public let preferredLanguage: String?
    public let timestamp: Date

    private let fd: Int32
    private let fileSize: Int64
    private let header: MapFileHeader
    private let indexCache: IndexCache

    public init(url: URL, language: String? = nil) throws {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw MapFileError("cannot open file: \(url.path)") }
        var st = stat()
        guard fstat(fd, &st) == 0 else {
            close(fd)
            throw MapFileError("cannot stat file: \(url.path)")
        }
        let fileSize = Int64(st.st_size)
        do {
            self.header = try MapFileHeader(fileSize: fileSize) { offset, length in
                try Self.pread(fd: fd, offset: offset, length: length)
            }
        } catch {
            close(fd)
            throw error
        }
        self.url = url
        self.fd = fd
        self.fileSize = fileSize
        self.info = header.info
        self.preferredLanguage = (language?.isEmpty ?? true) ? nil : language
        self.timestamp = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
        self.indexCache = IndexCache(capacity: 64)
    }

    deinit {
        close(fd)
    }

    public var boundingBox: BoundingBox { info.boundingBox }

    public var languages: [String] {
        guard let p = info.languagesPreference?.trimmingCharacters(in: .whitespaces), !p.isEmpty else { return [] }
        return p.split(separator: ",").map(String.init)
    }

    public var startPosition: LatLong { info.startPosition ?? info.boundingBox.centerPoint }
    public var startZoomLevel: Int { info.startZoomLevel ?? 12 }

    public func supportsTile(_ tile: Tile) -> Bool {
        tile.boundingBox.intersects(info.boundingBox)
    }

    // MARK: - Public queries

    public func readMapData(_ tile: Tile) -> MapReadResult? { readMapData(tile, tile, .all) }
    public func readMapData(upperLeft: Tile, lowerRight: Tile) -> MapReadResult? { readMapData(upperLeft, lowerRight, .all) }
    public func readLabels(_ tile: Tile) -> MapReadResult? { readMapData(tile, tile, .labels) }
    public func readLabels(upperLeft: Tile, lowerRight: Tile) -> MapReadResult? { readMapData(upperLeft, lowerRight, .labels) }
    public func readPoiData(_ tile: Tile) -> MapReadResult? { readMapData(tile, tile, .pois) }

    // MARK: - Implementation

    enum Selector { case all, pois, labels }

    private func readMapData(_ upperLeft: Tile, _ lowerRight: Tile, _ selector: Selector) -> MapReadResult? {
        var q = QueryParameters()
        q.queryZoomLevel = header.queryZoomLevel(upperLeft.zoomLevel)
        guard let sub = header.subFileParameter(q.queryZoomLevel) else { return nil }
        q.calculateBaseTiles(upperLeft, lowerRight, sub)
        q.calculateBlocks(sub)
        do {
            return try processBlocks(q, sub, Tile.boundingBox(upperLeft, lowerRight), selector)
        } catch {
            return nil
        }
    }

    private func processBlocks(_ q: QueryParameters, _ sub: SubFileParameter, _ bbox: BoundingBox,
                               _ selector: Selector) throws -> MapReadResult? {
        var queryIsWater = true
        var queryReadWaterInfo = false
        var result = MapReadResult()

        guard q.fromBlockY <= q.toBlockY, q.fromBlockX <= q.toBlockX else { return result }
        for row in q.fromBlockY...q.toBlockY {
            for column in q.fromBlockX...q.toBlockX {
                let blockNumber = row * sub.blocksWidth + column
                let entry = try indexEntry(sub, blockNumber)
                if queryIsWater {
                    queryIsWater = queryIsWater && (entry & Self.bitmaskIndexWater) != 0
                    queryReadWaterInfo = true
                }
                let blockPointer = entry & Self.bitmaskIndexOffset
                guard blockPointer >= 1, blockPointer <= sub.subFileSize else { return nil }
                let nextBlockPointer: Int64
                if blockNumber + 1 == sub.numberOfBlocks {
                    nextBlockPointer = sub.subFileSize
                } else {
                    nextBlockPointer = try indexEntry(sub, blockNumber + 1) & Self.bitmaskIndexOffset
                    guard nextBlockPointer <= sub.subFileSize else { return nil }
                }
                let blockSize = Int(nextBlockPointer - blockPointer)
                if blockSize < 0 { return nil }
                if blockSize == 0 { continue }
                if blockSize > Self.maximumBufferSize { continue }
                if blockPointer + Int64(blockSize) > fileSize { return nil }

                var buffer = ReadBuffer(try Self.pread(fd: fd, offset: sub.startAddress + blockPointer, length: blockSize))
                let tileLatitude = MercatorProjection.tileYToLatitude(sub.boundaryTileTop + row, zoomLevel: sub.baseZoomLevel)
                let tileLongitude = MercatorProjection.tileXToLongitude(sub.boundaryTileLeft + column, zoomLevel: sub.baseZoomLevel)
                if let bundle = processBlock(q, sub, bbox, tileLatitude, tileLongitude, selector, &buffer) {
                    result.add(pois: bundle.pois, ways: bundle.ways)
                }
            }
        }
        if queryIsWater && queryReadWaterInfo {
            result.isWater = true
        }
        return result
    }

    private func processBlock(_ q: QueryParameters, _ sub: SubFileParameter, _ bbox: BoundingBox,
                              _ tileLatitude: Double, _ tileLongitude: Double, _ selector: Selector,
                              _ buffer: inout ReadBuffer) -> (pois: [PointOfInterest], ways: [Way])? {
        if info.debugFile {
            guard let sig = buffer.readUTF8EncodedString(length: 32), sig.hasPrefix("###TileStart") else { return nil }
        }
        // zoom table
        let rows = sub.zoomLevelMax - sub.zoomLevelMin + 1
        var poisCum = 0, waysCum = 0
        var poisOnZoom = 0, waysOnZoom = 0
        let zoomRow = q.queryZoomLevel - sub.zoomLevelMin
        for row in 0..<rows {
            poisCum += buffer.readUnsignedInt()
            waysCum += buffer.readUnsignedInt()
            if row == zoomRow {
                poisOnZoom = poisCum
                waysOnZoom = waysCum
            }
        }
        var firstWayOffset = buffer.readUnsignedInt()
        guard firstWayOffset >= 0 else { return nil }
        firstWayOffset += buffer.position
        guard firstWayOffset <= buffer.size else { return nil }

        let filterRequired = q.queryZoomLevel > sub.baseZoomLevel
        guard let pois = processPOIs(tileLatitude, tileLongitude, poisOnZoom, bbox, filterRequired, &buffer) else { return nil }

        var ways: [Way] = []
        if selector != .pois {
            guard buffer.position <= firstWayOffset else { return nil }
            buffer.position = firstWayOffset
            guard let w = processWays(q, waysOnZoom, bbox, filterRequired, tileLatitude, tileLongitude, selector, &buffer) else { return nil }
            ways = w
        }
        return (pois, ways)
    }

    private func processPOIs(_ tileLatitude: Double, _ tileLongitude: Double, _ count: Int, _ bbox: BoundingBox,
                             _ filterRequired: Bool, _ buffer: inout ReadBuffer) -> [PointOfInterest]? {
        var pois = [PointOfInterest]()
        pois.reserveCapacity(count)
        let poiTags = info.poiTags
        for _ in 0..<count {
            if info.debugFile {
                guard let sig = buffer.readUTF8EncodedString(length: 32), sig.hasPrefix("***POIStart") else { return nil }
            }
            let latitude = tileLatitude + LatLongUtils.microdegreesToDegrees(buffer.readSignedInt())
            let longitude = tileLongitude + LatLongUtils.microdegreesToDegrees(buffer.readSignedInt())
            let special = buffer.readUInt8()
            let layer = Int8((special & 0xf0) >> 4)
            let numberOfTags = Int(special & 0x0f)
            guard var tags = buffer.readTags(poiTags, count: numberOfTags) else { return nil }
            let feature = buffer.readUInt8()
            if feature & 0x80 != 0 {
                tags.append(Tag(key: "name", value: extractLocalized(buffer.readUTF8EncodedString()) ?? ""))
            }
            if feature & 0x40 != 0 {
                tags.append(Tag(key: "addr:housenumber", value: buffer.readUTF8EncodedString() ?? ""))
            }
            if feature & 0x20 != 0 {
                tags.append(Tag(key: "ele", value: String(buffer.readSignedInt())))
            }
            let position = LatLong(latitude: latitude, longitude: longitude)
            if !filterRequired || bbox.contains(position) {
                pois.append(PointOfInterest(layer: layer, tags: tags, position: position))
            }
        }
        return pois
    }

    private func processWays(_ q: QueryParameters, _ count: Int, _ bbox: BoundingBox, _ filterRequired: Bool,
                             _ tileLatitude: Double, _ tileLongitude: Double, _ selector: Selector,
                             _ buffer: inout ReadBuffer) -> [Way]? {
        var ways = [Way]()
        ways.reserveCapacity(count)
        let wayTags = info.wayTags
        let wayFilterBbox = bbox.extendMeters(Self.wayFilterDistance)
        for _ in 0..<count {
            if info.debugFile {
                guard let sig = buffer.readUTF8EncodedString(length: 32), sig.hasPrefix("---WayStart") else { return nil }
            }
            let wayDataSize = buffer.readUnsignedInt()
            guard wayDataSize >= 0 else { return nil }
            if q.useTileBitmask {
                let tileBitmask = Int(UInt16(bitPattern: buffer.readShort()))
                if q.queryTileBitmask & tileBitmask == 0 {
                    buffer.skipBytes(wayDataSize - 2)
                    continue
                }
            } else {
                buffer.skipBytes(2)
            }
            let special = buffer.readUInt8()
            let layer = Int8((special & 0xf0) >> 4)
            let numberOfTags = Int(special & 0x0f)
            guard var tags = buffer.readTags(wayTags, count: numberOfTags) else { return nil }

            let feature = buffer.readUInt8()
            let featureName = feature & 0x80 != 0
            let featureHouseNumber = feature & 0x40 != 0
            let featureRef = feature & 0x20 != 0
            let featureLabelPosition = feature & 0x10 != 0
            let featureDataBlocksByte = feature & 0x08 != 0
            let featureDoubleDelta = feature & 0x04 != 0

            if featureName {
                tags.append(Tag(key: "name", value: extractLocalized(buffer.readUTF8EncodedString()) ?? ""))
            }
            if featureHouseNumber {
                tags.append(Tag(key: "addr:housenumber", value: buffer.readUTF8EncodedString() ?? ""))
            }
            if featureRef {
                tags.append(Tag(key: "ref", value: buffer.readUTF8EncodedString() ?? ""))
            }
            var labelPosition: (lat: Int32, lon: Int32)?
            if featureLabelPosition {
                let lat = buffer.readSignedInt()
                let lon = buffer.readSignedInt()
                labelPosition = (lat, lon)
            }
            let wayDataBlocks = featureDataBlocksByte ? buffer.readUnsignedInt() : 1
            guard wayDataBlocks >= 1 else { return nil }

            for _ in 0..<wayDataBlocks {
                guard let nodes = processWayDataBlock(tileLatitude, tileLongitude, featureDoubleDelta, &buffer) else { continue }
                if filterRequired && Self.wayFilterEnabled && !wayFilterBbox.intersectsArea(nodes) {
                    continue
                }
                if selector == .all || featureName || featureHouseNumber || featureRef || Self.wayAsLabelTagFilter(tags) {
                    var labelLatLong: LatLong?
                    if let lp = labelPosition {
                        labelLatLong = LatLong(latitude: nodes[0][0].latitude + LatLongUtils.microdegreesToDegrees(lp.lat),
                                               longitude: nodes[0][0].longitude + LatLongUtils.microdegreesToDegrees(lp.lon))
                    }
                    ways.append(Way(layer: layer, tags: tags, latLongs: nodes, labelPosition: labelLatLong))
                }
            }
        }
        return ways
    }

    private func processWayDataBlock(_ tileLatitude: Double, _ tileLongitude: Double, _ doubleDelta: Bool,
                                     _ buffer: inout ReadBuffer) -> [[LatLong]]? {
        let blocks = buffer.readUnsignedInt()
        guard blocks >= 1, blocks <= Int(Int16.max) else { return nil }
        var result = [[LatLong]]()
        result.reserveCapacity(blocks)
        for _ in 0..<blocks {
            let nodes = buffer.readUnsignedInt()
            guard nodes >= 2, nodes <= Int(Int16.max) else { return nil }
            result.append(doubleDelta
                ? Self.decodeDoubleDelta(nodes, tileLatitude, tileLongitude, &buffer)
                : Self.decodeSingleDelta(nodes, tileLatitude, tileLongitude, &buffer))
        }
        return result
    }

    @inline(__always)
    private static func clampLongitude(_ lon: Double) -> Double {
        if lon < LatLongUtils.longitudeMin && (LatLongUtils.longitudeMin - lon) < 0.001 { return LatLongUtils.longitudeMin }
        if lon > LatLongUtils.longitudeMax && (lon - LatLongUtils.longitudeMax) < 0.001 { return LatLongUtils.longitudeMax }
        return lon
    }

    private static func decodeDoubleDelta(_ count: Int, _ tileLatitude: Double, _ tileLongitude: Double,
                                          _ buffer: inout ReadBuffer) -> [LatLong] {
        var segment = [LatLong]()
        segment.reserveCapacity(count)
        var lat = tileLatitude + LatLongUtils.microdegreesToDegrees(buffer.readSignedInt())
        var lon = tileLongitude + LatLongUtils.microdegreesToDegrees(buffer.readSignedInt())
        segment.append(LatLong(latitude: lat, longitude: lon))
        var prevDeltaLat = 0.0, prevDeltaLon = 0.0
        for _ in 1..<count {
            let ddLat = LatLongUtils.microdegreesToDegrees(buffer.readSignedInt())
            let ddLon = LatLongUtils.microdegreesToDegrees(buffer.readSignedInt())
            let dLat = ddLat + prevDeltaLat
            let dLon = ddLon + prevDeltaLon
            lat = lat + dLat
            lon = clampLongitude(lon + dLon)
            segment.append(LatLong(latitude: lat, longitude: lon))
            prevDeltaLat = dLat
            prevDeltaLon = dLon
        }
        return segment
    }

    private static func decodeSingleDelta(_ count: Int, _ tileLatitude: Double, _ tileLongitude: Double,
                                          _ buffer: inout ReadBuffer) -> [LatLong] {
        var segment = [LatLong]()
        segment.reserveCapacity(count)
        var lat = tileLatitude + LatLongUtils.microdegreesToDegrees(buffer.readSignedInt())
        var lon = tileLongitude + LatLongUtils.microdegreesToDegrees(buffer.readSignedInt())
        segment.append(LatLong(latitude: lat, longitude: lon))
        for _ in 1..<count {
            lat = lat + LatLongUtils.microdegreesToDegrees(buffer.readSignedInt())
            lon = clampLongitude(lon + LatLongUtils.microdegreesToDegrees(buffer.readSignedInt()))
            segment.append(LatLong(latitude: lat, longitude: lon))
        }
        return segment
    }

    /// mapsforge `MapDataStore.wayAsLabelTagFilter` – returns false in the base implementation.
    private static func wayAsLabelTagFilter(_ tags: [Tag]) -> Bool {
        false
    }

    private func extractLocalized(_ s: String?) -> String? {
        Self.extract(s, language: preferredLanguage)
    }

    /// Port of `MapDataStore.extract`: names are stored as `default\rlang\bname\r...`.
    public static func extract(_ s: String?, language: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let langNames = s.components(separatedBy: "\r")
        guard let language, !language.trimmingCharacters(in: .whitespaces).isEmpty else { return langNames[0] }
        var fallback: String?
        for entry in langNames.dropFirst() {
            let parts = entry.components(separatedBy: "\u{08}")
            guard parts.count == 2 else { continue }
            if parts[0].caseInsensitiveCompare(language) == .orderedSame { return parts[1] }
            if fallback == nil, !parts[0].contains("-"), language.contains("-") || language.contains("_"),
               language.lowercased().hasPrefix(parts[0].lowercased()) {
                fallback = parts[1]
            }
        }
        return fallback ?? langNames[0]
    }

    // MARK: - File access

    private func indexEntry(_ sub: SubFileParameter, _ blockNumber: Int) throws -> Int64 {
        try indexCache.entry(sub, blockNumber) { offset, length in
            try Self.pread(fd: fd, offset: offset, length: length)
        }
    }

    static func pread(fd: Int32, offset: Int64, length: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: length)
        var done = 0
        while done < length {
            let n = bytes.withUnsafeMutableBytes { raw in
                Darwin.pread(fd, raw.baseAddress! + done, length - done, off_t(offset) + off_t(done))
            }
            if n <= 0 { throw MapFileError("could not read \(length) bytes at offset \(offset)") }
            done += n
        }
        return bytes
    }
}

// MARK: - Index cache

final class IndexCache: @unchecked Sendable {
    private static let entriesPerBlock = 128
    private static let sizeOfIndexBlock = entriesPerBlock * SubFileParameter.bytesPerIndexEntry

    private struct Key: Hashable {
        let startAddress: Int64
        let indexBlock: Int
    }

    private let capacity: Int
    private var map: [Key: [UInt8]] = [:]
    private var order: [Key] = []
    private let lock = NSLock()

    init(capacity: Int) {
        self.capacity = capacity
    }

    func entry(_ sub: SubFileParameter, _ blockNumber: Int, read: (Int64, Int) throws -> [UInt8]) throws -> Int64 {
        guard blockNumber < sub.numberOfBlocks else { throw MapFileError("invalid block number: \(blockNumber)") }
        let indexBlockNumber = blockNumber / Self.entriesPerBlock
        let key = Key(startAddress: sub.startAddress, indexBlock: indexBlockNumber)

        lock.lock()
        var block = map[key]
        if block != nil, let i = order.lastIndex(of: key) {
            order.remove(at: i)
            order.append(key)
        }
        lock.unlock()

        if block == nil {
            let position = sub.indexStartAddress + Int64(indexBlockNumber * Self.sizeOfIndexBlock)
            let remaining = Int(sub.indexEndAddress - position)
            let size = min(Self.sizeOfIndexBlock, remaining)
            let data = try read(position, size)
            block = data
            lock.lock()
            if map[key] == nil {
                map[key] = data
                order.append(key)
                if order.count > capacity {
                    map.removeValue(forKey: order.removeFirst())
                }
            }
            lock.unlock()
        }

        let b = block!
        let address = (blockNumber % Self.entriesPerBlock) * SubFileParameter.bytesPerIndexEntry
        var v: Int64 = 0
        for i in 0..<5 { v = v << 8 | Int64(b[address + i]) }
        return v
    }
}

// MARK: - Query parameters

struct QueryParameters {
    var fromBaseTileX = 0, fromBaseTileY = 0
    var toBaseTileX = 0, toBaseTileY = 0
    var fromBlockX = 0, fromBlockY = 0
    var toBlockX = 0, toBlockY = 0
    var queryTileBitmask = 0
    var queryZoomLevel = 0
    var useTileBitmask = false

    mutating func calculateBaseTiles(_ upperLeft: Tile, _ lowerRight: Tile, _ sub: SubFileParameter) {
        if upperLeft.zoomLevel < sub.baseZoomLevel {
            let d = sub.baseZoomLevel - upperLeft.zoomLevel
            fromBaseTileX = upperLeft.tileX << d
            fromBaseTileY = upperLeft.tileY << d
            toBaseTileX = (lowerRight.tileX << d) + (1 << d) - 1
            toBaseTileY = (lowerRight.tileY << d) + (1 << d) - 1
            useTileBitmask = false
        } else if upperLeft.zoomLevel > sub.baseZoomLevel {
            let d = upperLeft.zoomLevel - sub.baseZoomLevel
            fromBaseTileX = upperLeft.tileX >> d
            fromBaseTileY = upperLeft.tileY >> d
            toBaseTileX = lowerRight.tileX >> d
            toBaseTileY = lowerRight.tileY >> d
            useTileBitmask = true
            var mask = 0
            for x in upperLeft.tileX...lowerRight.tileX {
                for y in upperLeft.tileY...lowerRight.tileY {
                    mask |= Self.tileBitmask(x, y, d)
                }
            }
            queryTileBitmask = mask
        } else {
            fromBaseTileX = upperLeft.tileX
            fromBaseTileY = upperLeft.tileY
            toBaseTileX = lowerRight.tileX
            toBaseTileY = lowerRight.tileY
            useTileBitmask = false
        }
    }

    mutating func calculateBlocks(_ sub: SubFileParameter) {
        fromBlockX = max(fromBaseTileX - sub.boundaryTileLeft, 0)
        fromBlockY = max(fromBaseTileY - sub.boundaryTileTop, 0)
        toBlockX = min(toBaseTileX - sub.boundaryTileLeft, sub.blocksWidth - 1)
        toBlockY = min(toBaseTileY - sub.boundaryTileTop, sub.blocksHeight - 1)
    }

    static func tileBitmask(_ tileX: Int, _ tileY: Int, _ zoomLevelDifference: Int) -> Int {
        if zoomLevelDifference == 1 {
            switch (tileX % 2, tileY % 2) {
            case (0, 0): return 0xcc00
            case (1, 0): return 0x3300
            case (0, 1): return 0xcc
            default: return 0x33
            }
        }
        let subX = tileX >> (zoomLevelDifference - 2)
        let subY = tileY >> (zoomLevelDifference - 2)
        let parentX = subX >> 1
        let parentY = subY >> 1
        let sx = subX % 2, sy = subY % 2
        let table: [Int]
        switch (parentX % 2, parentY % 2) {
        case (0, 0): table = [0x8000, 0x4000, 0x800, 0x400]   // upper left
        case (1, 0): table = [0x2000, 0x1000, 0x200, 0x100]   // upper right
        case (0, 1): table = [0x80, 0x40, 0x8, 0x4]           // lower left
        default: table = [0x20, 0x10, 0x2, 0x1]               // lower right
        }
        return table[sy * 2 + sx]
    }
}
