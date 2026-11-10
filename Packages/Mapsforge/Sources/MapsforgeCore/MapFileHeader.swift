// Port of org.mapsforge.map.reader.header.* (MapFileHeader, RequiredFields,
// OptionalFields, SubFileParameter, MapFileInfo).
// Licensed under LGPL-3.0 like the original mapsforge code.

import Foundation

public struct MapFileError: Error, CustomStringConvertible, Sendable {
    public let description: String
    init(_ message: String) { description = message }
}

public struct MapFileInfo: Sendable {
    public var boundingBox = BoundingBox(minLatitude: 0, minLongitude: 0, maxLatitude: 0, maxLongitude: 0)
    public var comment: String?
    public var createdBy: String?
    public var debugFile = false
    public var fileSize: Int64 = 0
    public var fileVersion: Int = 0
    public var languagesPreference: String?
    public var mapDate: Int64 = 0
    public var numberOfSubFiles = 0
    public var poiTags: [Tag] = []
    public var projectionName = ""
    public var startPosition: LatLong?
    public var startZoomLevel: Int?
    public var tilePixelSize = 0
    public var wayTags: [Tag] = []
    public var zoomLevelMax = 0
    public var zoomLevelMin = 0
}

public struct SubFileParameter: Sendable {
    static let bytesPerIndexEntry = 5

    public let baseZoomLevel: Int
    public let zoomLevelMin: Int
    public let zoomLevelMax: Int
    public let startAddress: Int64
    public let indexStartAddress: Int64
    public let subFileSize: Int64

    public let boundaryTileBottom: Int
    public let boundaryTileLeft: Int
    public let boundaryTileRight: Int
    public let boundaryTileTop: Int
    public let blocksWidth: Int
    public let blocksHeight: Int
    public let numberOfBlocks: Int
    public let indexEndAddress: Int64

    init(baseZoomLevel: Int, zoomLevelMin: Int, zoomLevelMax: Int, startAddress: Int64,
         indexStartAddress: Int64, subFileSize: Int64, boundingBox: BoundingBox) {
        self.baseZoomLevel = baseZoomLevel
        self.zoomLevelMin = zoomLevelMin
        self.zoomLevelMax = zoomLevelMax
        self.startAddress = startAddress
        self.indexStartAddress = indexStartAddress
        self.subFileSize = subFileSize
        boundaryTileBottom = MercatorProjection.latitudeToTileY(boundingBox.minLatitude, zoomLevel: baseZoomLevel)
        boundaryTileLeft = MercatorProjection.longitudeToTileX(boundingBox.minLongitude, zoomLevel: baseZoomLevel)
        boundaryTileTop = MercatorProjection.latitudeToTileY(boundingBox.maxLatitude, zoomLevel: baseZoomLevel)
        boundaryTileRight = MercatorProjection.longitudeToTileX(boundingBox.maxLongitude, zoomLevel: baseZoomLevel)
        blocksWidth = boundaryTileRight - boundaryTileLeft + 1
        blocksHeight = boundaryTileBottom - boundaryTileTop + 1
        numberOfBlocks = blocksWidth * blocksHeight
        indexEndAddress = indexStartAddress + Int64(numberOfBlocks * Self.bytesPerIndexEntry)
    }
}

struct MapFileHeader: Sendable {
    private static let magic = "mapsforge binary OSM"
    private static let headerSizeMin = 70
    private static let headerSizeMax = 1_000_000
    private static let supportedVersions = 3...5
    private static let baseZoomLevelMax = 20
    private static let signatureLengthIndex: Int64 = 16

    private(set) var info = MapFileInfo()
    private(set) var subFileParameters: [SubFileParameter?] = []
    private(set) var zoomLevelMinimum = 0
    private(set) var zoomLevelMaximum = 0

    func queryZoomLevel(_ zoomLevel: Int) -> Int {
        if zoomLevel > zoomLevelMaximum { return zoomLevelMaximum }
        if zoomLevel < zoomLevelMinimum { return zoomLevelMinimum }
        return zoomLevel
    }

    func subFileParameter(_ queryZoomLevel: Int) -> SubFileParameter? {
        guard queryZoomLevel >= 0, queryZoomLevel < subFileParameters.count else { return nil }
        return subFileParameters[queryZoomLevel]
    }

    /// Reads and validates the header. `read(offset, length)` returns raw file bytes.
    init(fileSize: Int64, read: (Int64, Int) throws -> [UInt8]) throws {
        let magicLength = Self.magic.utf8.count
        var buffer = ReadBuffer(try read(0, magicLength + 4))
        guard buffer.readUTF8EncodedString(length: magicLength) == Self.magic else {
            throw MapFileError("invalid magic byte")
        }
        let remaining = Int(buffer.readInt())
        guard remaining >= Self.headerSizeMin, remaining <= Self.headerSizeMax else {
            throw MapFileError("invalid remaining header size: \(remaining)")
        }
        buffer = ReadBuffer(try read(Int64(magicLength + 4), remaining))

        var info = MapFileInfo()
        // RequiredFields
        let version = Int(buffer.readInt())
        guard Self.supportedVersions.contains(version) else { throw MapFileError("unsupported file version: \(version)") }
        info.fileVersion = version

        let headerFileSize = buffer.readLong()
        guard headerFileSize == fileSize else { throw MapFileError("invalid file size: \(headerFileSize)") }
        info.fileSize = fileSize

        let mapDate = buffer.readLong()
        guard mapDate >= 1_200_000_000_000 else { throw MapFileError("invalid map date: \(mapDate)") }
        info.mapDate = mapDate

        let minLat = LatLongUtils.microdegreesToDegrees(buffer.readInt())
        let minLon = LatLongUtils.microdegreesToDegrees(buffer.readInt())
        let maxLat = LatLongUtils.microdegreesToDegrees(buffer.readInt())
        let maxLon = LatLongUtils.microdegreesToDegrees(buffer.readInt())
        guard minLat <= maxLat, minLon <= maxLon else { throw MapFileError("invalid bounding box") }
        info.boundingBox = BoundingBox(minLatitude: minLat, minLongitude: minLon, maxLatitude: maxLat, maxLongitude: maxLon)

        info.tilePixelSize = Int(buffer.readShort())

        let projection = buffer.readUTF8EncodedString()
        guard projection == "Mercator" else { throw MapFileError("unsupported projection: \(projection ?? "nil")") }
        info.projectionName = "Mercator"

        // OptionalFields
        let flags = buffer.readUInt8()
        info.debugFile = flags & 0x80 != 0
        if flags & 0x40 != 0 {
            let lat = LatLongUtils.microdegreesToDegrees(buffer.readInt())
            let lon = LatLongUtils.microdegreesToDegrees(buffer.readInt())
            info.startPosition = LatLong(latitude: lat, longitude: lon)
        }
        if flags & 0x20 != 0 {
            let z = Int(buffer.readByte())
            guard (0...22).contains(z) else { throw MapFileError("invalid map start zoom level: \(z)") }
            info.startZoomLevel = z
        }
        if flags & 0x10 != 0 { info.languagesPreference = buffer.readUTF8EncodedString() }
        if flags & 0x08 != 0 { info.comment = buffer.readUTF8EncodedString() }
        if flags & 0x04 != 0 { info.createdBy = buffer.readUTF8EncodedString() }

        // Tag tables
        info.poiTags = try Self.readTagTable(&buffer, kind: "POI")
        info.wayTags = try Self.readTagTable(&buffer, kind: "way")

        // Sub-files
        let numberOfSubFiles = Int(buffer.readByte())
        guard numberOfSubFiles >= 1 else { throw MapFileError("invalid number of sub-files: \(numberOfSubFiles)") }
        info.numberOfSubFiles = numberOfSubFiles

        var temp = [SubFileParameter]()
        var zMin = Int.max, zMax = Int.min
        for _ in 0..<numberOfSubFiles {
            let baseZoom = Int(buffer.readByte())
            guard (0...Self.baseZoomLevelMax).contains(baseZoom) else { throw MapFileError("invalid base zoom level: \(baseZoom)") }
            let zoomMin = Int(buffer.readByte())
            let zoomMax = Int(buffer.readByte())
            guard (0...22).contains(zoomMin), (0...22).contains(zoomMax), zoomMin <= zoomMax else {
                throw MapFileError("invalid zoom level range: \(zoomMin) \(zoomMax)")
            }
            let startAddress = buffer.readLong()
            guard startAddress >= Int64(Self.headerSizeMin), startAddress < fileSize else {
                throw MapFileError("invalid start address: \(startAddress)")
            }
            let indexStart = info.debugFile ? startAddress + Self.signatureLengthIndex : startAddress
            let subFileSize = buffer.readLong()
            guard subFileSize >= 1 else { throw MapFileError("invalid sub-file size: \(subFileSize)") }
            let p = SubFileParameter(baseZoomLevel: baseZoom, zoomLevelMin: zoomMin, zoomLevelMax: zoomMax,
                                     startAddress: startAddress, indexStartAddress: indexStart,
                                     subFileSize: subFileSize, boundingBox: info.boundingBox)
            temp.append(p)
            zMin = min(zMin, zoomMin)
            zMax = max(zMax, zoomMax)
        }
        info.zoomLevelMin = zMin
        info.zoomLevelMax = zMax

        var params = [SubFileParameter?](repeating: nil, count: zMax + 1)
        for p in temp {
            for z in p.zoomLevelMin...p.zoomLevelMax { params[z] = p }
        }

        self.info = info
        self.subFileParameters = params
        self.zoomLevelMinimum = zMin
        self.zoomLevelMaximum = zMax
    }

    private static func readTagTable(_ buffer: inout ReadBuffer, kind: String) throws -> [Tag] {
        let count = Int(buffer.readShort())
        guard count >= 0 else { throw MapFileError("invalid number of \(kind) tags: \(count)") }
        var tags = [Tag]()
        tags.reserveCapacity(count)
        for i in 0..<count {
            guard let text = buffer.readUTF8EncodedString() else { throw MapFileError("\(kind) tag must not be null: \(i)") }
            tags.append(Tag(text))
        }
        return tags
    }
}
