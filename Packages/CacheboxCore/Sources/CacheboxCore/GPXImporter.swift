import Foundation

/// Progress of an import, reported about every 50 records.
public struct GPXImportProgress: Sendable {
    /// File currently read (inside a ZIP: the GPX file name).
    public var file: String
    /// Records (caches and waypoints) read from the current file.
    public var done: Int
    /// Records in the current file (counted before parsing).
    public var total: Int
    /// Caches imported so far over all files.
    public var caches: Int
}

/// Result of an import.
public struct GPXImportResult: Sendable, Equatable {
    public var files = 0
    public var newCaches = 0
    public var updatedCaches = 0
    public var waypoints = 0
    public var logs = 0
    /// Waypoints whose cache is neither in the file nor in the list.
    public var orphanWaypoints = 0

    public init() {}
    public var caches: Int { newCaches + updatedCaches }
}

/// Imports geocaching GPX files and pocket query ZIPs into a cache list.
///
/// Files can be given in any order: a ZIP is unpacked first, and additional waypoints ("-wpts.gpx") are written
/// after all caches, so they find their cache. Re-importing updates caches from the newer file and keeps what the
/// user changed (note, favourite mark, corrected coordinates, found mark); see `CacheDatabase.upsert(_:)`.
public final class GPXImporter {
    private let database: CacheDatabase
    private var cancelled = false

    /// Asked after every record; returning true stops the import (what was imported so far is kept).
    /// In a task, pass `{ Task.isCancelled }`.
    public var shouldCancel: () -> Bool = { false }

    public init(database: CacheDatabase) {
        self.database = database
    }

    public func importFiles(_ urls: [URL], progress: @escaping (GPXImportProgress) -> Void = { _ in }) throws -> GPXImportResult {
        var result = GPXImportResult()
        let workFolder = FileManager.default.temporaryDirectory
            .appending(path: "gpx-import-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: workFolder) }

        // unpack ZIPs, then caches before waypoint files
        var gpxFiles: [(url: URL, name: String)] = []
        for url in urls {
            if url.pathExtension.lowercased() == "zip" {
                gpxFiles += try unpackGPX(from: url, into: workFolder)
            } else {
                gpxFiles.append((url, url.lastPathComponent))
            }
        }
        guard !gpxFiles.isEmpty else { throw GPXError("Keine GPX-Datei gefunden") }
        gpxFiles.sort { !Self.isWaypointFile($0.name) && Self.isWaypointFile($1.name) }

        var pendingWaypoints: [Waypoint] = []
        for file in gpxFiles {
            guard !cancelled else { break }
            try importGPX(file.url, name: file.name, result: &result, pendingWaypoints: &pendingWaypoints,
                          progress: progress)
            result.files += 1
        }
        // waypoints that came before their cache (or in a file without it)
        if !pendingWaypoints.isEmpty {
            try database.transaction {
                for waypoint in pendingWaypoints {
                    if try database.cacheExists(waypoint.cacheCode) {
                        try database.upsert(waypoint)
                        result.waypoints += 1
                    } else {
                        result.orphanWaypoints += 1
                    }
                }
            }
        }
        try? database.setInfo("lastImport", ISO8601DateFormatter().string(from: Date()))
        return result
    }

    private func importGPX(_ url: URL, name: String, result: inout GPXImportResult, pendingWaypoints: inout [Waypoint],
                           progress: @escaping (GPXImportProgress) -> Void) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        let total = Self.countWaypoints(in: data)
        var state = GPXImportProgress(file: name, done: 0, total: total, caches: result.caches)
        progress(state)

        var failure: Error?
        var counts = result
        var pending: [Waypoint] = []
        let database = self.database
        var parser: GPXParser!
        parser = GPXParser(data: data) { [unowned self] record in
            do {
                switch record {
                case .cache(var cache, let logs, let trackables):
                    cache.gpxFile = name
                    let exists = try database.cacheExists(cache.code)
                    try database.upsert(cache)
                    for log in logs { try database.upsert(log) }
                    try database.replaceTrackables(trackables, cacheCode: cache.code)
                    if exists { counts.updatedCaches += 1 } else { counts.newCaches += 1 }
                    counts.logs += logs.count
                case .waypoint(let waypoint):
                    if try database.cacheExists(waypoint.cacheCode) {
                        try database.upsert(waypoint)
                        counts.waypoints += 1
                    } else {
                        pending.append(waypoint)
                    }
                }
            } catch {
                failure = error
                parser.abort()
            }
            state.done += 1
            state.caches = counts.caches
            if state.done % 50 == 0 { progress(state) }
            if self.shouldCancel() {
                self.cancelled = true
                parser.abort()
            }
        }
        try database.transaction {
            do {
                try parser.parse()
            } catch {
                // an abort by cancel() is no error; a write error or broken XML is
                if let failure { throw failure }
                if !cancelled { throw error }
            }
        }
        result = counts
        pendingWaypoints += pending
        state.caches = counts.caches
        progress(state)
    }

    /// GPX files inside a ZIP, unpacked into `folder` (pocket queries: "123.gpx" and "123-wpts.gpx").
    private func unpackGPX(from zip: URL, into folder: URL) throws -> [(url: URL, name: String)] {
        let accessing = zip.startAccessingSecurityScopedResource()
        defer { if accessing { zip.stopAccessingSecurityScopedResource() } }
        let archive = try ZipArchive(url: zip)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var files: [(url: URL, name: String)] = []
        for entry in archive.entries where !entry.isDirectory && entry.path.lowercased().hasSuffix(".gpx") {
            let name = URL(filePath: entry.path).lastPathComponent
            guard !name.hasPrefix(".") else { continue }   // macOS resource forks ("__MACOSX/._x.gpx")
            let target = folder.appending(path: "\(files.count)-\(name)")
            try archive.extract(entry, to: target)
            files.append((target, name))
        }
        return files
    }

    static func isWaypointFile(_ name: String) -> Bool {
        (name as NSString).deletingPathExtension.lowercased().hasSuffix("-wpts")
    }

    /// Number of `<wpt` elements, for the progress display.
    static func countWaypoints(in data: Data) -> Int {
        let pattern = Array("<wpt".utf8)
        return data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Int in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self), buffer.count >= pattern.count
            else { return 0 }
            var count = 0
            var i = 0
            let end = buffer.count - pattern.count
            while i <= end {
                if base[i] == 0x3C, base[i + 1] == pattern[1], base[i + 2] == pattern[2], base[i + 3] == pattern[3] {
                    count += 1
                    i += 4
                } else {
                    i += 1
                }
            }
            return count
        }
    }
}
