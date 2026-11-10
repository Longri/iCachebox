import Foundation

/// A cache list as shown in the list management (Cachebox: one database in the "select database" screen).
public struct CacheListInfo: Identifiable, Hashable, Sendable {
    public var name: String
    public var url: URL
    public var id: String { name }
    public var cacheCount: Int
    /// Size of the database file in bytes.
    public var fileSize: Int64
    public var lastImport: Date?
    public var modified: Date?
}

/// Manages the cache lists of the app: one SQLite file (`<name>.db3`) per list in one folder.
public struct CacheListStore: Sendable {
    public static let fileExtension = "db3"
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    public func url(of name: String) -> URL {
        folder.appending(path: name + "." + Self.fileExtension)
    }

    /// All lists, sorted by name, with counts read from each file.
    public func lists() -> [CacheListInfo] {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey,
                                                                                         .contentModificationDateKey]))
            ?? []
        return files.filter { $0.pathExtension == Self.fileExtension }
            .compactMap { info(for: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func info(name: String) -> CacheListInfo? { info(for: url(of: name)) }

    private func info(for url: URL) -> CacheListInfo? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let database = try? CacheDatabase(url: url)
        let walSize = (try? URL(filePath: url.path + "-wal").resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return CacheListInfo(name: url.deletingPathExtension().lastPathComponent, url: url,
                             cacheCount: (try? database?.count()) ?? 0,
                             fileSize: Int64((values?.fileSize ?? 0) + walSize),
                             lastImport: database?.info("lastImport").flatMap { ISO8601DateFormatter().date(from: $0) },
                             modified: values?.contentModificationDate)
    }

    /// Checks a list name typed by the user; returns the cleaned name or throws a readable error.
    public func validatedName(_ name: String, excluding current: String? = nil) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CacheListError("Bitte einen Namen eingeben.") }
        guard trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\:")) == nil, !trimmed.hasPrefix(".") else {
            throw CacheListError("Der Name darf keine / \\ : enthalten und nicht mit einem Punkt beginnen.")
        }
        guard trimmed.count <= 60 else { throw CacheListError("Der Name ist zu lang (höchstens 60 Zeichen).") }
        let exists = lists().contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
        if exists, current.map({ $0.caseInsensitiveCompare(trimmed) != .orderedSame }) ?? true {
            throw CacheListError("Eine Liste mit diesem Namen gibt es schon.")
        }
        return trimmed
    }

    /// Creates an empty list and returns its name.
    @discardableResult
    public func create(_ name: String) throws -> String {
        let name = try validatedName(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try CacheDatabase(url: url(of: name))
        return name
    }

    public func rename(_ name: String, to newName: String) throws -> String {
        let newName = try validatedName(newName, excluding: name)
        guard newName != name else { return name }
        let fm = FileManager.default
        // fold the WAL into the main file so that only one file has to move
        if let database = try? CacheDatabase(url: url(of: name)) { try? database.checkpoint() }
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(filePath: url(of: name).path + suffix)
            guard fm.fileExists(atPath: source.path) else { continue }
            try fm.moveItem(at: source, to: URL(filePath: url(of: newName).path + suffix))
        }
        return newName
    }

    public func delete(_ name: String) throws {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let file = URL(filePath: url(of: name).path + suffix)
            if fm.fileExists(atPath: file.path) { try fm.removeItem(at: file) }
        }
    }
}

public struct CacheListError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
