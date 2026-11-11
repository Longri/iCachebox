import Foundation

/// One cache list: an SQLite file with caches, waypoints, logs and trackables (Cachebox: one database per list).
///
/// Not thread-safe; open one instance per task (SQLite in WAL mode allows readers next to an importing writer).
public final class CacheDatabase {
    public let url: URL
    let db: SQLiteConnection

    /// Schema version stored in `PRAGMA user_version`.
    static let schemaVersion = 1

    public init(url: URL) throws {
        self.url = url
        db = try SQLiteConnection(url: url)
        try db.execute("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;")
        try migrate()
    }

    private func migrate() throws {
        guard db.userVersion < Self.schemaVersion else { return }
        try db.transaction {
            try db.execute("""
                CREATE TABLE IF NOT EXISTS caches (
                    code TEXT PRIMARY KEY,
                    source_id INTEGER,
                    name TEXT NOT NULL,
                    latitude REAL NOT NULL,
                    longitude REAL NOT NULL,
                    corrected_latitude REAL,
                    corrected_longitude REAL,
                    type TEXT NOT NULL,
                    container TEXT NOT NULL,
                    difficulty REAL NOT NULL,
                    terrain REAL NOT NULL,
                    owner TEXT NOT NULL DEFAULT '',
                    placed_by TEXT NOT NULL DEFAULT '',
                    hidden REAL,
                    available INTEGER NOT NULL DEFAULT 1,
                    archived INTEGER NOT NULL DEFAULT 0,
                    found INTEGER NOT NULL DEFAULT 0,
                    country TEXT NOT NULL DEFAULT '',
                    state TEXT NOT NULL DEFAULT '',
                    url TEXT NOT NULL DEFAULT '',
                    short_description TEXT NOT NULL DEFAULT '',
                    short_html INTEGER NOT NULL DEFAULT 0,
                    long_description TEXT NOT NULL DEFAULT '',
                    long_html INTEGER NOT NULL DEFAULT 0,
                    hint TEXT NOT NULL DEFAULT '',
                    favorite_points INTEGER,
                    attributes TEXT NOT NULL DEFAULT '[]',
                    note TEXT NOT NULL DEFAULT '',
                    favorite INTEGER NOT NULL DEFAULT 0,
                    gpx_file TEXT NOT NULL DEFAULT '',
                    updated REAL
                );
                CREATE TABLE IF NOT EXISTS waypoints (
                    cache_code TEXT NOT NULL REFERENCES caches(code) ON DELETE CASCADE,
                    code TEXT NOT NULL,
                    title TEXT NOT NULL DEFAULT '',
                    comment TEXT NOT NULL DEFAULT '',
                    type TEXT NOT NULL,
                    latitude REAL,
                    longitude REAL,
                    user_created INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (cache_code, code)
                );
                CREATE TABLE IF NOT EXISTS logs (
                    id TEXT PRIMARY KEY,
                    cache_code TEXT NOT NULL REFERENCES caches(code) ON DELETE CASCADE,
                    date REAL,
                    type TEXT NOT NULL,
                    finder TEXT NOT NULL DEFAULT '',
                    text TEXT NOT NULL DEFAULT ''
                );
                CREATE INDEX IF NOT EXISTS logs_cache ON logs(cache_code, date);
                CREATE TABLE IF NOT EXISTS trackables (
                    code TEXT NOT NULL,
                    cache_code TEXT NOT NULL REFERENCES caches(code) ON DELETE CASCADE,
                    name TEXT NOT NULL DEFAULT '',
                    PRIMARY KEY (cache_code, code)
                );
                CREATE TABLE IF NOT EXISTS info (key TEXT PRIMARY KEY, value TEXT);
                PRAGMA user_version = \(Self.schemaVersion);
                """)
        }
    }

    // MARK: - Reading

    public func count() throws -> Int {
        try db.prepare("SELECT COUNT(*) FROM caches").first { $0.int(0) } ?? 0
    }

    /// The fields for the cache list, for all caches of the list.
    public func summaries() throws -> [CacheSummary] {
        try db.prepare("""
            SELECT c.code, c.name, c.latitude, c.longitude, c.corrected_latitude, c.corrected_longitude, c.type,
                   c.container, c.difficulty, c.terrain, c.owner, c.hidden, c.available, c.archived, c.found,
                   c.favorite, c.favorite_points,
                   (SELECT COUNT(*) FROM waypoints w WHERE w.cache_code = c.code),
                   (SELECT COUNT(*) FROM trackables t WHERE t.cache_code = c.code),
                   f.latitude, f.longitude
            FROM caches c
            LEFT JOIN (
                -- first final with coordinates per cache; SQLite takes the bare columns from the MIN(code) row
                SELECT cache_code, latitude, longitude, MIN(code) FROM waypoints
                WHERE type = 'final' AND latitude IS NOT NULL AND longitude IS NOT NULL
                      AND NOT (latitude = 0 AND longitude = 0)
                GROUP BY cache_code
            ) f ON f.cache_code = c.code
            """).rows { r in
            let corrected = r.isNull(4) ? nil : Coordinate(latitude: r.double(4), longitude: r.double(5))
            return CacheSummary(
                code: r.string(0), name: r.string(1),
                coordinate: corrected ?? Coordinate(latitude: r.double(2), longitude: r.double(3)),
                hasCorrectedCoordinate: corrected != nil,
                finalCoordinate: r.isNull(19) ? nil : Coordinate(latitude: r.double(19), longitude: r.double(20)),
                type: CacheType(rawValue: r.string(6)) ?? .other,
                container: ContainerSize(rawValue: r.string(7)) ?? .notChosen,
                difficulty: r.double(8), terrain: r.double(9), owner: r.string(10), hidden: r.date(11),
                isAvailable: r.bool(12), isArchived: r.bool(13), isFound: r.bool(14), isFavorite: r.bool(15),
                favoritePoints: r.isNull(16) ? nil : r.int(16), waypointCount: r.int(17), trackableCount: r.int(18))
        }
    }

    public func cache(code: String) throws -> Geocache? {
        try db.prepare("""
            SELECT code, source_id, name, latitude, longitude, corrected_latitude, corrected_longitude, type, container,
                   difficulty, terrain, owner, placed_by, hidden, available, archived, found, country, state, url,
                   short_description, short_html, long_description, long_html, hint, favorite_points, attributes,
                   note, favorite, updated, gpx_file
            FROM caches WHERE code = ?
            """).first([code]) { r in
            var cache = Geocache(code: r.string(0), name: r.string(2),
                                 coordinate: Coordinate(latitude: r.double(3), longitude: r.double(4)),
                                 type: CacheType(rawValue: r.string(7)) ?? .other,
                                 container: ContainerSize(rawValue: r.string(8)) ?? .notChosen,
                                 difficulty: r.double(9), terrain: r.double(10))
            cache.sourceID = r.isNull(1) ? nil : r.int(1)
            if !r.isNull(5) { cache.correctedCoordinate = Coordinate(latitude: r.double(5), longitude: r.double(6)) }
            cache.owner = r.string(11)
            cache.placedBy = r.string(12)
            cache.hidden = r.date(13)
            cache.isAvailable = r.bool(14)
            cache.isArchived = r.bool(15)
            cache.isFound = r.bool(16)
            cache.country = r.string(17)
            cache.state = r.string(18)
            cache.url = r.string(19)
            cache.shortDescription = r.string(20)
            cache.shortDescriptionIsHTML = r.bool(21)
            cache.longDescription = r.string(22)
            cache.longDescriptionIsHTML = r.bool(23)
            cache.hint = r.string(24)
            cache.favoritePoints = r.isNull(25) ? nil : r.int(25)
            cache.attributes = (try? JSONDecoder().decode([CacheAttribute].self, from: Data(r.string(26).utf8))) ?? []
            cache.note = r.string(27)
            cache.isFavorite = r.bool(28)
            cache.updated = r.date(29)
            cache.gpxFile = r.string(30)
            return cache
        }
    }

    public func waypoints(cacheCode: String) throws -> [Waypoint] {
        try db.prepare("""
            SELECT code, title, comment, type, latitude, longitude, user_created
            FROM waypoints WHERE cache_code = ? ORDER BY code
            """).rows([cacheCode]) { r in
            Waypoint(code: r.string(0), cacheCode: cacheCode, title: r.string(1), comment: r.string(2),
                     type: WaypointType(rawValue: r.string(3)) ?? .other,
                     coordinate: r.isNull(4) ? nil : Coordinate(latitude: r.double(4), longitude: r.double(5)),
                     isUserCreated: r.bool(6))
        }
    }

    /// Logs of a cache, newest first.
    public func logs(cacheCode: String, limit: Int? = nil) throws -> [CacheLog] {
        let sql = "SELECT id, date, type, finder, text FROM logs WHERE cache_code = ? ORDER BY date DESC, id DESC"
            + (limit.map { " LIMIT \($0)" } ?? "")
        return try db.prepare(sql).rows([cacheCode]) { r in
            CacheLog(id: r.string(0), cacheCode: cacheCode, date: r.date(1),
                     type: LogType(rawValue: r.string(2)) ?? .other, finder: r.string(3), text: r.string(4))
        }
    }

    public func trackables(cacheCode: String) throws -> [Trackable] {
        try db.prepare("SELECT code, name FROM trackables WHERE cache_code = ? ORDER BY name").rows([cacheCode]) {
            Trackable(code: $0.string(0), name: $0.string(1), cacheCode: cacheCode)
        }
    }

    public func info(_ key: String) -> String? {
        (try? db.prepare("SELECT value FROM info WHERE key = ?").first([key]) { $0.optionalString(0) }) ?? nil
    }

    // MARK: - Writing

    public func setInfo(_ key: String, _ value: String) throws {
        try db.prepare("INSERT OR REPLACE INTO info (key, value) VALUES (?, ?)").run([key, value])
    }

    public func setFound(_ found: Bool, code: String) throws {
        try db.prepare("UPDATE caches SET found = ? WHERE code = ?").run([found, code])
    }

    public func setFavorite(_ favorite: Bool, code: String) throws {
        try db.prepare("UPDATE caches SET favorite = ? WHERE code = ?").run([favorite, code])
    }

    public func setNote(_ note: String, code: String) throws {
        try db.prepare("UPDATE caches SET note = ? WHERE code = ?").run([note, code])
    }

    public func deleteCaches(codes: [String]) throws {
        let statement = try db.prepare("DELETE FROM caches WHERE code = ?")
        try db.transaction { for code in codes { try statement.run([code]) } }
    }

    /// Writes the WAL into the database file (before moving or sharing the file).
    public func checkpoint() throws {
        try db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    }

    /// Runs `body` in one transaction (much faster for imports).
    public func transaction<T>(_ body: () throws -> T) throws -> T { try db.transaction(body) }

    private lazy var upsertCacheStatement = try? db.prepare("""
        INSERT INTO caches (code, source_id, name, latitude, longitude, type, container, difficulty, terrain, owner,
                            placed_by, hidden, available, archived, found, country, state, url, short_description,
                            short_html, long_description, long_html, hint, favorite_points, attributes, gpx_file,
                            updated)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(code) DO UPDATE SET
            source_id = COALESCE(excluded.source_id, source_id), name = excluded.name,
            latitude = CASE WHEN excluded.latitude = 0 AND excluded.longitude = 0 THEN latitude ELSE excluded.latitude END,
            longitude = CASE WHEN excluded.latitude = 0 AND excluded.longitude = 0 THEN longitude ELSE excluded.longitude END,
            type = excluded.type,
            container = excluded.container, difficulty = excluded.difficulty, terrain = excluded.terrain,
            owner = excluded.owner, placed_by = excluded.placed_by, hidden = COALESCE(excluded.hidden, hidden),
            available = excluded.available, archived = excluded.archived,
            found = MAX(found, excluded.found),
            country = excluded.country, state = excluded.state, url = excluded.url,
            short_description = CASE WHEN excluded.short_description = '' THEN short_description
                                     ELSE excluded.short_description END,
            short_html = CASE WHEN excluded.short_description = '' THEN short_html ELSE excluded.short_html END,
            long_description = CASE WHEN excluded.long_description = '' THEN long_description
                                    ELSE excluded.long_description END,
            long_html = CASE WHEN excluded.long_description = '' THEN long_html ELSE excluded.long_html END,
            hint = excluded.hint, favorite_points = COALESCE(excluded.favorite_points, favorite_points),
            attributes = excluded.attributes, gpx_file = excluded.gpx_file, updated = excluded.updated
        """)

    /// Inserts a cache or updates it from newer data. Kept on update: the user's note, favourite mark and
    /// corrected coordinates; a cache marked as found stays found; empty descriptions and 0/0 coordinates do not
    /// replace stored ones (as in Cachebox).
    public func upsert(_ cache: Geocache) throws {
        guard let statement = upsertCacheStatement else { throw SQLiteError(code: -1, message: "prepare upsert") }
        let attributes = String(decoding: (try? JSONEncoder().encode(cache.attributes)) ?? Data("[]".utf8), as: UTF8.self)
        try statement.run([
            cache.code, cache.sourceID, cache.name, cache.coordinate.latitude, cache.coordinate.longitude,
            cache.type.rawValue, cache.container.rawValue, cache.difficulty, cache.terrain, cache.owner,
            cache.placedBy, cache.hidden, cache.isAvailable, cache.isArchived, cache.isFound, cache.country,
            cache.state, cache.url, cache.shortDescription, cache.shortDescriptionIsHTML, cache.longDescription,
            cache.longDescriptionIsHTML, cache.hint, cache.favoritePoints, attributes, cache.gpxFile,
            cache.updated ?? Date(),
        ])
        if let corrected = cache.correctedCoordinate {
            try db.prepare("UPDATE caches SET corrected_latitude = ?, corrected_longitude = ? WHERE code = ?")
                .run([corrected.latitude, corrected.longitude, cache.code])
        }
    }

    public func cacheExists(_ code: String) throws -> Bool {
        try db.prepare("SELECT 1 FROM caches WHERE code = ?").first([code]) { _ in true } ?? false
    }

    private lazy var upsertWaypointStatement = try? db.prepare("""
        INSERT INTO waypoints (cache_code, code, title, comment, type, latitude, longitude, user_created)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(cache_code, code) DO UPDATE SET
            title = excluded.title, comment = excluded.comment, type = excluded.type,
            latitude = excluded.latitude, longitude = excluded.longitude
        WHERE user_created = 0
        """)

    /// Inserts or updates a waypoint; waypoints the user created are not overwritten.
    public func upsert(_ waypoint: Waypoint) throws {
        guard let statement = upsertWaypointStatement else { throw SQLiteError(code: -1, message: "prepare waypoint") }
        try statement.run([waypoint.cacheCode, waypoint.code, waypoint.title, waypoint.comment, waypoint.type.rawValue,
                           waypoint.coordinate?.latitude, waypoint.coordinate?.longitude, waypoint.isUserCreated])
    }

    private lazy var upsertLogStatement = try? db.prepare("""
        INSERT OR REPLACE INTO logs (id, cache_code, date, type, finder, text) VALUES (?, ?, ?, ?, ?, ?)
        """)

    public func upsert(_ log: CacheLog) throws {
        guard let statement = upsertLogStatement else { throw SQLiteError(code: -1, message: "prepare log") }
        try statement.run([log.id, log.cacheCode, log.date, log.type.rawValue, log.finder, log.text])
    }

    /// Replaces the trackables of a cache (a GPX file lists all trackables currently in the cache).
    public func replaceTrackables(_ trackables: [Trackable], cacheCode: String) throws {
        try db.prepare("DELETE FROM trackables WHERE cache_code = ?").run([cacheCode])
        let insert = try db.prepare("INSERT OR REPLACE INTO trackables (code, cache_code, name) VALUES (?, ?, ?)")
        for trackable in trackables { try insert.run([trackable.code, cacheCode, trackable.name]) }
    }
}
