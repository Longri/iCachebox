import Foundation
import Testing
@testable import CacheboxCore

/// An answer of `getVotes.php` as GCVote writes it: one flat `vote` element per cache, numbers with many
/// decimals, an empty `voteUser` when the user has not voted, and 0 for a cache nobody has rated.
private let votesXML = """
<?xml version="1.0" encoding="UTF-8"?>
<votes userName="Longri" cacheId="" waypoint="">
<vote cacheId="1001" voteAvg="3.666700" voteCnt="12" voteMedian="4.000000" voteUser="4.000000" \
waypoint="GCTEST1" vote1="0" vote2="1" vote3="2" vote4="6" vote5="3"/>
<vote cacheId="1002" voteAvg="0.000000" voteCnt="0" voteMedian="0.000000" voteUser="" waypoint="GCTEST2"/>
<vote cacheId="1003" voteAvg="4.500000" voteCnt="2" voteMedian="4.500000" voteUser="" waypoint="GCTEST3"/>
</votes>
"""

private func rating(_ waypoint: String, _ average: Double, count: Int = 1, own: Double? = nil) -> String {
    "<vote waypoint=\"\(waypoint)\" voteAvg=\"\(average)\" voteCnt=\"\(count)\" "
        + "voteUser=\"\(own.map { String($0) } ?? "")\"/>"
}

/// `<votes>` with the given `vote` elements.
private func answer(_ votes: String...) -> String {
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?><votes>" + votes.joined() + "</votes>"
}

@Suite("GCVote-Abfrage")
struct GCVoteServiceTests {
    @Test func readsAnAnswer() throws {
        let ratings = try GCVoteService.parse(Data(votesXML.utf8))
        #expect(ratings.map(\.waypoint) == ["GCTEST1", "GCTEST2", "GCTEST3"])

        let first = ratings[0]
        #expect(abs(first.average - 3.6667) < 0.0001)
        #expect(first.count == 12)
        #expect(first.median == 4)
        #expect(first.ownVote == 4)
        #expect(first.isRated)

        // nobody has voted yet: 0 is no rating, and an empty voteUser is no own vote (Cachebox: length() == 0)
        #expect(!ratings[1].isRated)
        #expect(ratings[1].ownVote == nil)
        #expect(ratings[2].ownVote == nil)
        #expect(ratings[2].average == 4.5)
    }

    /// The old gcvote.com answers HTML for every path today; that must not look like "no ratings".
    @Test func refusesAnHTMLPage() throws {
        let page = Data("<html><head><title>ERROR</title></head><body><h1>410</h1></body></html>".utf8)
        #expect(throws: GCVoteError.self) { try GCVoteService.parse(page) }
    }

    @Test func refusesBrokenXML() throws {
        #expect(throws: GCVoteError.self) { try GCVoteService.parse(Data("<votes><vote ".utf8)) }
    }

    /// Request as Cachebox builds it, only percent encoded.
    @Test func buildsTheRequest() throws {
        let service = GCVoteService(server: "http://gcvote.com", http: StubHTTPClient([]))
        let url = try service.url(waypoints: ["GCTEST1", "GCTEST2"],
                                 credentials: GCVoteCredentials(username: "Long ri", password: "pa&ss"))
        #expect(url.path() == "/getVotes.php")
        let query = url.queryFields
        #expect(query["waypoints"] == "GCTEST1,GCTEST2")
        #expect(query["userName"] == "Long ri")
        #expect(query["password"] == "pa&ss")
        #expect(url.absoluteString.contains("pa%26ss"))     // encoded, so the & does not split the query
    }

    /// Without a password the averages are fetched anonymously - no empty user name is sent.
    @Test func asksAnonymouslyWithoutAPassword() throws {
        let service = GCVoteService(server: "gcvote.example", http: StubHTTPClient([]))
        let url = try service.url(waypoints: ["GCTEST1"],
                                 credentials: GCVoteCredentials(username: "Longri", password: ""))
        #expect(url.scheme == "http")                        // a server without a scheme gets http, as in Cachebox
        #expect(url.host() == "gcvote.example")
        #expect(url.queryFields["userName"] == nil)
        #expect(url.queryFields["password"] == nil)
    }

    @Test func acceptsAServerWithAPathAndASlash() throws {
        let service = GCVoteService(server: "https://example.org/gcvote/", http: StubHTTPClient([]))
        let url = try service.url(waypoints: ["GCTEST1"], credentials: nil)
        #expect(url.absoluteString.hasPrefix("https://example.org/gcvote/getVotes.php?"))
    }

    @Test func refusesAnEmptyServer() throws {
        let service = GCVoteService(server: "   ", http: StubHTTPClient([]))
        #expect(throws: GCVoteError.invalidURL("   ")) { try service.url(waypoints: ["GCTEST1"], credentials: nil) }
    }

    /// 410 is what gcvote.com answers since the service was switched off - with a clear message.
    @Test func reportsAGoneService() async throws {
        let http = StubHTTPClient([.init(status: 410, json: "<html>410</html>")])
        let service = GCVoteService(server: "http://gcvote.com", http: http)
        await #expect(throws: GCVoteError.gone(host: "gcvote.com")) {
            try await service.ratings(waypoints: ["GCTEST1"])
        }
    }

    @Test func reportsAServerError() async throws {
        let http = StubHTTPClient([.init(status: 500, json: "oops")])
        let service = GCVoteService(server: "http://gcvote.com", http: http)
        await #expect(throws: GCVoteError.http(status: 500, message: "oops")) {
            try await service.ratings(waypoints: ["GCTEST1"])
        }
    }

    @Test func asksNothingForAnEmptyList() async throws {
        let http = StubHTTPClient([])
        let service = GCVoteService(server: "http://gcvote.com", http: http)
        #expect(try await service.ratings(waypoints: []).isEmpty)
        #expect(await http.requestCount() == 0)
    }
}

@Suite("GCVote-Import")
struct GCVoteImporterTests {
    /// Inserts `count` caches GCTEST1 … GCTESTn into a fresh list.
    private func list(_ count: Int) throws -> CacheDatabase {
        let database = try Fixture.database()
        try database.transaction {
            for number in 1...count {
                try database.upsert(Geocache(code: "GCTEST\(number)", name: "Cache \(number)",
                                             coordinate: Coordinate(latitude: 53, longitude: 8)))
            }
        }
        return database
    }

    @Test func writesRatingsIntoTheList() async throws {
        let database = try list(3)
        let http = StubHTTPClient([.init(json: votesXML)])
        let importer = GCVoteImporter(database: database, service: GCVoteService(server: "gcvote.test", http: http),
                                      credentials: GCVoteCredentials(username: "Longri", password: "pw"))
        let result = try await importer.importRatings(codes: ["GCTEST1", "GCTEST2", "GCTEST3"])

        #expect(result.requested == 3)
        #expect(result.rated == 2)          // GCTEST2 has no votes
        #expect(result.unrated == 1)
        #expect(result.ownVotes == 1)
        #expect(result.failedRequests == 0)

        let summaries = try database.summaries().sorted { $0.code < $1.code }
        #expect(abs((summaries[0].gcVote.rating ?? 0) - 3.6667) < 0.0001)
        #expect(summaries[0].gcVote.count == 12)
        #expect(summaries[0].gcVote.ownVote == 4)
        #expect(summaries[0].gcVote.isRated)
        #expect(summaries[1].gcVote.rating == nil)
        #expect(!summaries[1].gcVote.isRated)
        #expect(summaries[2].gcVote.rating == 4.5)
        // the list remembers when it last asked
        #expect(database.info(GCVoteImporter.updatedKey) != nil)
    }

    /// Cachebox asks for 100 caches per request; 250 caches are three requests.
    @Test func asksInPackagesOfHundred() async throws {
        let database = try list(250)
        let codes = (1...250).map { "GCTEST\($0)" }
        let answers = [1, 101, 201].map { start -> StubHTTPClient.Answer in
            let count = start == 201 ? 50 : 100
            let votes = (start..<(start + count)).map { rating("GCTEST\($0)", 3) }.joined()
            return .init(json: "<votes>" + votes + "</votes>")
        }
        let http = StubHTTPClient(answers)
        let importer = GCVoteImporter(database: database, service: GCVoteService(server: "gcvote.test", http: http))

        let progress = ProgressLog()
        let result = try await importer.importRatings(codes: codes) { progress.add($0) }
        #expect(result.rated == 250)
        #expect(await http.requestCount() == 3)
        let sent = await http.requests()
        #expect(sent[0].url?.queryFields["waypoints"]?.split(separator: ",").count == 100)
        #expect(sent[2].url?.queryFields["waypoints"]?.split(separator: ",").count == 50)
        #expect(progress.steps.map(\.done) == [100, 200, 250])
        #expect(progress.steps.allSatisfy { $0.total == 250 })
    }

    /// GCVote only knows geocaching.com (Cachebox: "Not a GC.com Cache").
    @Test func leavesOutCodesThatAreNoGCCodes() async throws {
        let database = try list(1)
        try database.upsert(Geocache(code: "OC1234", name: "Opencaching",
                                     coordinate: Coordinate(latitude: 53, longitude: 8)))
        let http = StubHTTPClient([.init(json: answer(rating("GCTEST1", 2.5)))])
        let importer = GCVoteImporter(database: database, service: GCVoteService(server: "gcvote.test", http: http))
        let result = try await importer.importRatings(codes: ["GCTEST1", "OC1234"])
        #expect(result.skipped == 1)
        #expect(result.requested == 1)
        #expect(result.rated == 1)
        #expect(await http.requests().first?.url?.queryFields["waypoints"] == "GCTEST1")
    }

    /// One failed package does not stop the import - the next one still arrives (as in Cachebox).
    @Test func goesOnAfterAFailedPackage() async throws {
        let database = try list(150)
        let codes = (1...150).map { "GCTEST\($0)" }
        let good = (101...150).map { rating("GCTEST\($0)", 4) }.joined()
        let http = StubHTTPClient([.init(status: 500, json: "later"), .init(json: "<votes>" + good + "</votes>")])
        let importer = GCVoteImporter(database: database, service: GCVoteService(server: "gcvote.test", http: http))
        let result = try await importer.importRatings(codes: codes)
        #expect(result.failedRequests == 1)
        #expect(result.rated == 50)
    }

    /// Nothing arrived at all: the caller gets the reason instead of a silent "0 ratings".
    @Test func throwsWhenEveryPackageFails() async throws {
        let database = try list(1)
        let http = StubHTTPClient([.init(status: 500, json: "oops")])
        let importer = GCVoteImporter(database: database, service: GCVoteService(server: "gcvote.test", http: http))
        await #expect(throws: GCVoteError.http(status: 500, message: "oops")) {
            try await importer.importRatings(codes: ["GCTEST1"])
        }
    }

    /// A switched-off server is not asked 99 more times.
    @Test func stopsAtOnceWhenTheServerIsGone() async throws {
        let database = try list(150)
        let http = StubHTTPClient([.init(status: 410, json: "gone"), .init(json: "<votes/>")])
        let importer = GCVoteImporter(database: database, service: GCVoteService(server: "gcvote.com", http: http))
        await #expect(throws: GCVoteError.self) {
            try await importer.importRatings(codes: (1...150).map { "GCTEST\($0)" })
        }
        #expect(await http.requestCount() == 1)
    }

    /// Cancelling keeps what was written.
    @Test func keepsWhatWasWrittenWhenCancelled() async throws {
        let database = try list(200)
        let first = (1...100).map { rating("GCTEST\($0)", 3) }.joined()
        let http = StubHTTPClient([.init(json: "<votes>" + first + "</votes>"), .init(json: "<votes/>")])
        let importer = GCVoteImporter(database: database, service: GCVoteService(server: "gcvote.test", http: http))
        let cancelled = Flag()
        importer.shouldCancel = { cancelled.value }
        let result = try await importer.importRatings(codes: (1...200).map { "GCTEST\($0)" }) { _ in
            cancelled.value = true
        }
        #expect(result.rated == 100)
        #expect(await http.requestCount() == 1)
        #expect(try database.summaries().filter { $0.gcVote.isRated }.count == 100)
    }
}

@Suite("GCVote in der Liste")
struct GCVoteDatabaseTests {
    /// A new import of the cache must not throw its rating away (like note, favourite and corrected coordinates).
    @Test func keepsTheRatingOnReimport() throws {
        let database = try Fixture.database()
        var cache = Geocache(code: "GCTEST1", name: "Cache", coordinate: Coordinate(latitude: 53, longitude: 8))
        try database.upsert(cache)
        try database.setGCVote(rating: 4.5, count: 7, ownVote: 5, code: "GCTEST1")

        cache.name = "Cache, neu"
        try database.upsert(cache)
        let stored = try #require(try database.cache(code: "GCTEST1"))
        #expect(stored.name == "Cache, neu")
        #expect(stored.gcVote.rating == 4.5)
        #expect(stored.gcVote.count == 7)
        #expect(stored.gcVote.ownVote == 5)
    }

    /// A rating without the user's own vote does not delete the vote that is stored.
    @Test func keepsTheOwnVoteWhenTheAnswerHasNone() throws {
        let database = try Fixture.database()
        try database.upsert(Geocache(code: "GCTEST1", name: "Cache", coordinate: Coordinate(latitude: 53, longitude: 8)))
        try database.setGCVote(rating: 3, count: 2, ownVote: 4, code: "GCTEST1")
        try database.setGCVote(rating: 3.5, count: 3, ownVote: nil, code: "GCTEST1")
        let stored = try #require(try database.cache(code: "GCTEST1"))
        #expect(stored.gcVote.rating == 3.5)
        #expect(stored.gcVote.ownVote == 4)
    }

    @Test func forgetsAllRatings() throws {
        let database = try Fixture.database()
        try database.upsert(Geocache(code: "GCTEST1", name: "Cache", coordinate: Coordinate(latitude: 53, longitude: 8)))
        try database.setGCVote(rating: 3, count: 2, ownVote: 4, code: "GCTEST1")
        try database.setInfo(GCVoteImporter.updatedKey, "2026-11-23T10:00:00Z")
        try database.clearGCVotes()
        let stored = try #require(try database.cache(code: "GCTEST1"))
        #expect(stored.gcVote.rating == nil)
        #expect(stored.gcVote.count == 0)
        #expect(stored.gcVote.ownVote == nil)
        #expect(database.info(GCVoteImporter.updatedKey) == nil)
    }

    /// A list of schema 1 (before the waypoint editor) is lifted over both steps and keeps its caches.
    @Test func migratesAListOfVersionOne() throws {
        let url = try OldSchema.write(version: 1)
        let database = try CacheDatabase(url: url)
        #expect(try database.count() == 1)
        try database.setGCVote(rating: 2.5, count: 4, ownVote: nil, code: "GCTEST1")
        let stored = try #require(try database.cache(code: "GCTEST1"))
        #expect(stored.name == "Alter Cache")
        #expect(stored.gcVote.rating == 2.5)
        // the waypoint columns of schema 2 are there, too
        try database.saveUserWaypoint(Waypoint(code: "C1TEST1", cacheCode: "GCTEST1", title: "Station",
                                               clue: "unter dem Stein", type: .stage,
                                               coordinate: Coordinate(latitude: 53, longitude: 8), isStart: true))
        #expect(try database.waypoints(cacheCode: "GCTEST1").first?.clue == "unter dem Stein")
    }

    /// A list of schema 2 only needs the rating columns.
    @Test func migratesAListOfVersionTwo() throws {
        let url = try OldSchema.write(version: 2)
        let database = try CacheDatabase(url: url)
        #expect(try database.count() == 1)
        #expect(try database.summaries().first?.gcVote.rating == nil)
        try database.setGCVote(rating: 5, count: 1, ownVote: 5, code: "GCTEST1")
        #expect(try database.summaries().first?.gcVote.ownVote == 5)
    }
}

/// Writes a cache list in an older schema, to check the migration.
enum OldSchema {
    /// Schema 1 and 2 as `CacheDatabase` created them before the ratings: schema 2 is schema 1 plus `clue` and
    /// `is_start` on the waypoints.
    static func write(version: Int) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "cacheboxcore-old-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "old.db3")
        let db = try SQLiteConnection(url: url)
        try db.execute("""
            CREATE TABLE caches (
                code TEXT PRIMARY KEY, source_id INTEGER, name TEXT NOT NULL, latitude REAL NOT NULL,
                longitude REAL NOT NULL, corrected_latitude REAL, corrected_longitude REAL, type TEXT NOT NULL,
                container TEXT NOT NULL, difficulty REAL NOT NULL, terrain REAL NOT NULL,
                owner TEXT NOT NULL DEFAULT '', placed_by TEXT NOT NULL DEFAULT '', hidden REAL,
                available INTEGER NOT NULL DEFAULT 1, archived INTEGER NOT NULL DEFAULT 0,
                found INTEGER NOT NULL DEFAULT 0, country TEXT NOT NULL DEFAULT '', state TEXT NOT NULL DEFAULT '',
                url TEXT NOT NULL DEFAULT '', short_description TEXT NOT NULL DEFAULT '',
                short_html INTEGER NOT NULL DEFAULT 0, long_description TEXT NOT NULL DEFAULT '',
                long_html INTEGER NOT NULL DEFAULT 0, hint TEXT NOT NULL DEFAULT '', favorite_points INTEGER,
                attributes TEXT NOT NULL DEFAULT '[]', note TEXT NOT NULL DEFAULT '',
                favorite INTEGER NOT NULL DEFAULT 0, gpx_file TEXT NOT NULL DEFAULT '', updated REAL
            );
            CREATE TABLE waypoints (
                cache_code TEXT NOT NULL REFERENCES caches(code) ON DELETE CASCADE, code TEXT NOT NULL,
                title TEXT NOT NULL DEFAULT '', comment TEXT NOT NULL DEFAULT '', type TEXT NOT NULL,
                latitude REAL, longitude REAL, user_created INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (cache_code, code)
            );
            CREATE TABLE logs (
                id TEXT PRIMARY KEY, cache_code TEXT NOT NULL REFERENCES caches(code) ON DELETE CASCADE, date REAL,
                type TEXT NOT NULL, finder TEXT NOT NULL DEFAULT '', text TEXT NOT NULL DEFAULT ''
            );
            CREATE TABLE trackables (
                code TEXT NOT NULL, cache_code TEXT NOT NULL REFERENCES caches(code) ON DELETE CASCADE,
                name TEXT NOT NULL DEFAULT '', PRIMARY KEY (cache_code, code)
            );
            CREATE TABLE info (key TEXT PRIMARY KEY, value TEXT);
            """)
        if version >= 2 {
            try db.execute("""
                ALTER TABLE waypoints ADD COLUMN clue TEXT NOT NULL DEFAULT '';
                ALTER TABLE waypoints ADD COLUMN is_start INTEGER NOT NULL DEFAULT 0;
                """)
        }
        try db.prepare("""
            INSERT INTO caches (code, name, latitude, longitude, type, container, difficulty, terrain)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """).run(["GCTEST1", "Alter Cache", 53.0, 8.0, "traditional", "small", 1.5, 2.0])
        try db.execute("PRAGMA user_version = \(version);")
        return url
    }
}

/// Collects the progress reports of an import (the callback may run on any thread).
final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [GCVoteImportProgress] = []

    func add(_ progress: GCVoteImportProgress) { lock.withLock { collected.append(progress) } }
    var steps: [GCVoteImportProgress] { lock.withLock { collected } }
}

/// A flag two tasks share.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false

    var value: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

// MARK: - Once through the real network stack

/// Like the sign-in test: an HTTP server on localhost plays GCVote, so that `URLSession`, the query and the
/// XML really fit together - the stub tests above only check the pieces.
@Suite("GCVote von Anfang bis Ende")
struct GCVoteEndToEndTests {
    @Test func loadsRatingsOverHTTP() async throws {
        let asked = AskedQueries()
        let server = try TinyHTTPServer { request in
            guard request.path == "/getVotes.php" else { return .init(status: 404, json: "no") }
            asked.add(request.query)
            let codes = (request.query["waypoints"] ?? "").split(separator: ",").map(String.init)
            let votes = codes.enumerated().map { index, code in
                "<vote waypoint=\"\(code)\" voteAvg=\"\(3 + Double(index) / 2)\" voteCnt=\"\(index + 1)\" "
                    + "voteUser=\"\(index == 0 ? "5.0" : "")\"/>"
            }.joined()
            return .init(json: "<?xml version=\"1.0\"?><votes>" + votes + "</votes>",
                         contentType: "text/xml; charset=utf-8")
        }
        try await server.start()
        defer { server.stop() }

        let database = try Fixture.database()
        try database.transaction {
            for number in 1...2 {
                try database.upsert(Geocache(code: "GCTEST\(number)", name: "Cache \(number)",
                                             coordinate: Coordinate(latitude: 53, longitude: 8)))
            }
        }
        let service = GCVoteService(server: server.baseURL.absoluteString)
        let importer = GCVoteImporter(database: database, service: service,
                                      credentials: GCVoteCredentials(username: "Longri", password: "pw"))
        let result = try await importer.importRatings(codes: ["GCTEST1", "GCTEST2"])

        #expect(result.rated == 2)
        #expect(result.ownVotes == 1)
        let query = try #require(asked.queries.first)
        #expect(query["waypoints"] == "GCTEST1,GCTEST2")
        #expect(query["userName"] == "Longri")
        #expect(query["password"] == "pw")
        #expect(query["version"] == "iCacheBox")

        let summaries = try database.summaries().sorted { $0.code < $1.code }
        #expect(summaries[0].gcVote.rating == 3)
        #expect(summaries[0].gcVote.ownVote == 5)
        #expect(summaries[1].gcVote.rating == 3.5)
        #expect(summaries[1].gcVote.ownVote == nil)
    }
}

/// What the test server was asked.
final class AskedQueries: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [[String: String]] = []

    func add(_ query: [String: String]) { lock.withLock { collected.append(query) } }
    var queries: [[String: String]] { lock.withLock { collected } }
}

@Suite("GCVote-Schlüsselbund")
struct GCVoteCredentialStoreTests {
    /// Round trip through the real keychain, like the token store. Skipped where the test runner has none.
    @Test func storesAndDeletesTheCredentials() throws {
        let store = GCVoteKeychainStore(service: "de.team-cachebox.icachebox.test.\(UUID().uuidString)")
        let credentials = GCVoteCredentials(username: "Longri", password: "geheim")
        do {
            try store.save(credentials)
        } catch {
            return  // no keychain here
        }
        defer { try? store.clear() }
        #expect(try store.load() == credentials)

        try store.save(GCVoteCredentials(username: "Longri", password: "anders"))
        #expect(try store.load()?.password == "anders")

        try store.clear()
        #expect(try store.load() == nil)
        try store.clear()   // deleting twice is not an error
    }

    @Test func knowsWhenThereIsNothingToSend() {
        #expect(GCVoteCredentials(username: "", password: "pw").isEmpty)
        #expect(GCVoteCredentials(username: "  ", password: "pw").isEmpty)
        #expect(GCVoteCredentials(username: "Longri", password: "").isEmpty)
        #expect(!GCVoteCredentials(username: "Longri", password: "pw").isEmpty)
    }
}
