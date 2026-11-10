import Compression
import CryptoKit
import Foundation

/// Minimal ZIP reader for downloaded map and theme archives: central directory (with ZIP64),
/// entries stored or deflated, extracted in streaming fashion so multi-GB maps need little memory.
public struct ZipArchive: Sendable {
    public struct Entry: Sendable {
        public let path: String
        public let method: UInt16
        public let flags: UInt16
        public let compressedSize: UInt64
        public let uncompressedSize: UInt64
        public let localHeaderOffset: UInt64
        public var isDirectory: Bool { path.hasSuffix("/") }
    }

    public let url: URL
    public let entries: [Entry]

    public init(url: URL) throws {
        self.url = url
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        entries = try Self.readCentralDirectory(file)
    }

    /// Extracts `entry` to `destination` (overwritten). `progress` receives the uncompressed bytes written so far.
    public func extract(_ entry: Entry, to destination: URL, progress: @escaping (UInt64) -> Void = { _ in }) throws {
        guard entry.flags & 1 == 0 else { throw ZipError("Verschlüsselte ZIP-Einträge werden nicht unterstützt") }
        guard entry.method == 0 || entry.method == 8 else { throw ZipError("ZIP-Methode \(entry.method) nicht unterstützt") }
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }

        // local header: name and extra field lengths may differ from the central directory
        try input.seek(toOffset: entry.localHeaderOffset)
        let header = try Self.read(input, 30)
        guard header.u32(0) == 0x0403_4b50 else { throw ZipError("Ungültiger lokaler ZIP-Header") }
        try input.seek(toOffset: entry.localHeaderOffset + 30 + UInt64(header.u16(26)) + UInt64(header.u16(28)))

        try? FileManager.default.removeItem(at: destination)
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw ZipError("Datei kann nicht angelegt werden: \(destination.lastPathComponent)")
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        var written: UInt64 = 0
        let sink: (Data?) throws -> Void = { data in
            guard let data else { return }
            try output.write(contentsOf: data)
            written += UInt64(data.count)
            progress(written)
        }
        let filter = entry.method == 8 ? try OutputFilter(.decompress, using: .zlib, writingTo: sink) : nil
        var remaining = entry.compressedSize
        while remaining > 0 {
            let chunk = try autoreleasepool { () -> Data in
                let data = try input.read(upToCount: Int(min(remaining, 1 << 20))) ?? Data()
                guard !data.isEmpty else { throw ZipError("ZIP-Datei ist abgeschnitten") }
                if let filter { try filter.write(data) } else { try sink(data) }
                return data
            }
            remaining -= UInt64(chunk.count)
        }
        try filter?.finalize()
        guard written == entry.uncompressedSize else {
            throw ZipError("Entpackte Größe stimmt nicht (\(entry.path))")
        }
    }

    /// MD5 of a file as lower-case hex (the Freizeitkarte catalog lists MD5 checksums).
    public static func md5(of url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = Insecure.MD5()
        while true {
            let more = try autoreleasepool { () -> Bool in
                guard let data = try file.read(upToCount: 4 << 20), !data.isEmpty else { return false }
                hash.update(data: data)
                return true
            }
            if !more { break }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Central directory

    private static func readCentralDirectory(_ file: FileHandle) throws -> [Entry] {
        let fileSize = try file.seekToEnd()
        // end of central directory record: 22 bytes + up to 64 KB comment
        let tailLength = min(fileSize, 22 + 0xFFFF)
        try file.seek(toOffset: fileSize - tailLength)
        let tail = try read(file, Int(tailLength))
        guard let eocd = stride(from: tail.count - 22, through: 0, by: -1).first(where: { tail.u32($0) == 0x0605_4b50 }) else {
            throw ZipError("Keine ZIP-Datei")
        }
        var count = UInt64(tail.u16(eocd + 10))
        var directorySize = UInt64(tail.u32(eocd + 12))
        var directoryOffset = UInt64(tail.u32(eocd + 16))

        if count == 0xFFFF || directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF {
            // ZIP64 end of central directory locator directly precedes the classic record
            let locatorStart = fileSize - tailLength + UInt64(eocd) - 20
            try file.seek(toOffset: locatorStart)
            let locator = try read(file, 20)
            guard locator.u32(0) == 0x0706_4b50 else { throw ZipError("ZIP64-Verzeichnis fehlt") }
            try file.seek(toOffset: locator.u64(8))
            let record = try read(file, 56)
            guard record.u32(0) == 0x0606_4b50 else { throw ZipError("ZIP64-Verzeichnis ungültig") }
            count = record.u64(32)
            directorySize = record.u64(40)
            directoryOffset = record.u64(48)
        }

        try file.seek(toOffset: directoryOffset)
        let directory = try read(file, Int(directorySize))
        var entries: [Entry] = []
        var p = 0
        for _ in 0..<count {
            guard p + 46 <= directory.count, directory.u32(p) == 0x0201_4b50 else { throw ZipError("ZIP-Verzeichnis ungültig") }
            let nameLength = Int(directory.u16(p + 28)), extraLength = Int(directory.u16(p + 30))
            let commentLength = Int(directory.u16(p + 32))
            guard p + 46 + nameLength + extraLength <= directory.count else { throw ZipError("ZIP-Verzeichnis ungültig") }
            var compressed = UInt64(directory.u32(p + 20))
            var uncompressed = UInt64(directory.u32(p + 24))
            var offset = UInt64(directory.u32(p + 42))
            let name = String(decoding: directory[(directory.startIndex + p + 46)..<(directory.startIndex + p + 46 + nameLength)],
                              as: UTF8.self)

            // ZIP64 extra field: only the values that are 0xFFFFFFFF above, in this order
            var e = p + 46 + nameLength
            let extraEnd = e + extraLength
            while e + 4 <= extraEnd {
                let id = directory.u16(e), size = Int(directory.u16(e + 2))
                if id == 0x0001 {
                    var q = e + 4
                    if uncompressed == 0xFFFF_FFFF { uncompressed = directory.u64(q); q += 8 }
                    if compressed == 0xFFFF_FFFF { compressed = directory.u64(q); q += 8 }
                    if offset == 0xFFFF_FFFF { offset = directory.u64(q) }
                }
                e += 4 + size
            }
            entries.append(Entry(path: name, method: directory.u16(p + 10), flags: directory.u16(p + 8),
                                 compressedSize: compressed, uncompressedSize: uncompressed, localHeaderOffset: offset))
            p += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    private static func read(_ file: FileHandle, _ count: Int) throws -> Data {
        let data = try file.read(upToCount: count) ?? Data()
        guard data.count == count else { throw ZipError("ZIP-Datei ist abgeschnitten") }
        return data
    }
}

public struct ZipError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

private extension Data {
    func u16(_ i: Int) -> UInt16 {
        let s = startIndex + i
        return UInt16(self[s]) | UInt16(self[s + 1]) << 8
    }

    func u32(_ i: Int) -> UInt32 { UInt32(u16(i)) | UInt32(u16(i + 2)) << 16 }
    func u64(_ i: Int) -> UInt64 { UInt64(u32(i)) | UInt64(u32(i + 4)) << 32 }
}
