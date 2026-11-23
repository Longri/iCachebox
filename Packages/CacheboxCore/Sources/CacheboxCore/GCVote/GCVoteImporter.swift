import Foundation

/// Progress of a rating import, reported after every package.
public struct GCVoteImportProgress: Sendable, Equatable {
    /// Caches asked about so far.
    public var done: Int
    /// Caches to ask about.
    public var total: Int
    /// Ratings written so far.
    public var rated: Int

    public init(done: Int, total: Int, rated: Int) {
        self.done = done
        self.total = total
        self.rated = rated
    }
}

public struct GCVoteImportResult: Sendable, Equatable {
    /// Caches asked about (GC codes only; GCVote knows no others).
    public var requested = 0
    /// Caches whose rating was written.
    public var rated = 0
    /// Caches GCVote has no rating for (not in the answer or nobody voted).
    public var unrated = 0
    /// Caches left out because their code is no GC code (Cachebox: "Not a GC.com Cache").
    public var skipped = 0
    /// Requests that failed; the import goes on with the next package (as in Cachebox).
    public var failedRequests = 0
    /// Caches with a vote of the signed-in user.
    public var ownVotes = 0

    public init() {}
}

/// Loads GCVote ratings for the caches of a list and writes them into it (Cachebox `Importer.importGcVote`).
///
/// Asks in packages of 100 caches, like Cachebox, and reports after every package. Caches GCVote does not know
/// keep what is stored - a cache does not lose its rating because one request went wrong.
///
/// Create and use it inside one task: `CacheDatabase` belongs to the task that opened it.
public final class GCVoteImporter {
    private let database: CacheDatabase
    private let service: GCVoteService
    private let credentials: GCVoteCredentials?

    /// Asked before every package; returning true stops the import (what was written stays).
    /// In a task, pass `{ Task.isCancelled }`.
    public var shouldCancel: () -> Bool = { false }

    /// Key under which the list remembers when ratings were last loaded (`CacheDatabase.info`).
    public static let updatedKey = "gcvoteUpdated"

    public init(database: CacheDatabase, service: GCVoteService = GCVoteService(),
                credentials: GCVoteCredentials? = nil) {
        self.database = database
        self.service = service
        self.credentials = credentials
    }

    /// Asks GCVote about `codes` and writes every rating it answers with.
    public func importRatings(codes: [String],
                              progress: @escaping @Sendable (GCVoteImportProgress) -> Void = { _ in }) async throws -> GCVoteImportResult {
        var result = GCVoteImportResult()
        // GCVote only knows geocaching.com (Cachebox skips everything else with "Not a GC.com Cache")
        let wanted = codes.filter { $0.uppercased().hasPrefix("GC") }
        result.skipped = codes.count - wanted.count
        result.requested = wanted.count
        guard !wanted.isEmpty else { return result }

        var firstError: (any Error)?
        var cancelled = false
        var done = 0
        for package in stride(from: 0, to: wanted.count, by: GCVoteService.waypointsPerRequest) {
            if shouldCancel() {
                cancelled = true
                break
            }
            let slice = Array(wanted[package..<min(package + GCVoteService.waypointsPerRequest, wanted.count)])
            do {
                let ratings = try await service.ratings(waypoints: slice, credentials: credentials)
                let written = try write(ratings, asked: slice)
                result.rated += written.rated
                result.unrated += written.unrated
                result.ownVotes += written.ownVotes
            } catch let error as GCVoteError {
                switch error {
                // a switched-off server or a wrong address does not get another 99 tries
                case .gone, .invalidURL: throw error
                default:
                    result.failedRequests += 1
                    firstError = firstError ?? error
                }
            } catch {
                // cancelling while a request is in flight makes it fail; that is no error of the service
                if shouldCancel() || error is CancellationError || (error as? URLError)?.code == .cancelled {
                    cancelled = true
                    break
                }
                result.failedRequests += 1
                firstError = firstError ?? error
            }
            done += slice.count
            progress(GCVoteImportProgress(done: done, total: wanted.count, rated: result.rated))
        }
        // nothing arrived at all: let the caller show why (a cancelled import is not an error)
        if !cancelled, result.rated == 0, result.unrated == 0, let firstError { throw firstError }
        if result.rated > 0 || result.unrated > 0 {
            try? database.setInfo(Self.updatedKey, ISO8601DateFormatter().string(from: Date()))
        }
        return result
    }

    /// Writes the ratings of one package; caches missing from the answer count as unrated.
    private func write(_ ratings: [GCVoteRating], asked: [String]) throws -> (rated: Int, unrated: Int, ownVotes: Int) {
        var rated = 0
        var ownVotes = 0
        let answered = Set(ratings.map { $0.waypoint.uppercased() })
        try database.transaction {
            for rating in ratings {
                guard rating.isRated else { continue }
                try database.setGCVote(rating: rating.average, count: rating.count, ownVote: rating.ownVote,
                                       code: rating.waypoint)
                rated += 1
                if rating.ownVote != nil { ownVotes += 1 }
            }
        }
        let unratedInAnswer = ratings.filter { !$0.isRated }.count
        let missing = asked.filter { !answered.contains($0.uppercased()) }.count
        return (rated, unratedInAnswer + missing, ownVotes)
    }
}
