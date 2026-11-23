import CacheboxCore
import Foundation
import Observation

/// Loading GCVote ratings into the open cache list (Cachebox: the "GCVoteRatings" box of the import dialog and
/// `Importer.importGcVote`).
///
/// Keeps the GCVote account (user name in `UserDefaults`, password in the keychain), the server and what was
/// asked for last. The import itself runs in `CacheboxCore` (`GCVoteImporter`).
@MainActor
@Observable
final class GCVoteModel {
    /// Which caches are asked about. Cachebox always takes the caches of the current filter
    /// (`FilterInstances.getLastFilter`); "Alle Caches der Liste" is an addition.
    enum Scope: String, CaseIterable, Identifiable, Codable {
        case shown, all

        var id: Self { self }

        var title: String {
            switch self {
            case .shown: "Nur angezeigte Caches"
            case .all: "Alle Caches der Liste"
            }
        }
    }

    /// The geocaching.com user name, as GCVote knows it (Cachebox `GcLogin`).
    var username: String {
        didSet { saveCredentials() }
    }
    /// The GCVote password (Cachebox `GcVotePassword`); only needed for the user's own votes.
    var password: String {
        didSet { saveCredentials() }
    }
    /// Address of the service. gcvote.com answers 410 for every path, so this is a setting: whoever runs a copy
    /// or a compatible successor can enter it.
    var server: String {
        didSet { UserDefaults.standard.set(server, forKey: "gcvote.server") }
    }
    var scope: Scope {
        didSet { UserDefaults.standard.set(scope.rawValue, forKey: "gcvote.scope") }
    }

    private(set) var progress: GCVoteImportProgress?
    private(set) var result: GCVoteImportResult?
    private(set) var error: String?
    private(set) var isRunning = false
    /// When the open list last got ratings (`CacheDatabase.info`).
    private(set) var lastUpdated: Date?

    @ObservationIgnored private let store: any GCVoteCredentialStoring
    /// The import itself; cancelled by "Abbrechen". A detached task does not inherit the cancellation of the task
    /// that awaits it, so this is the detached one - as in `CacheListModel.importFiles`.
    @ObservationIgnored private var work: Task<Result<GCVoteImportResult, Error>, Never>?

    init(store: any GCVoteCredentialStoring = GCVoteKeychainStore()) {
        self.store = store
        let defaults = UserDefaults.standard
        let stored = try? store.load()
        username = stored?.username ?? defaults.string(forKey: "gcvote.username") ?? ""
        password = stored?.password ?? ""
        server = defaults.string(forKey: "gcvote.server") ?? GCVoteService.defaultServer
        scope = defaults.string(forKey: "gcvote.scope").flatMap(Scope.init(rawValue:)) ?? .shown
    }

    var credentials: GCVoteCredentials { GCVoteCredentials(username: username, password: password) }

    /// The server is the standard one again.
    func resetServer() {
        server = GCVoteService.defaultServer
    }

    private func saveCredentials() {
        // the user name also goes into UserDefaults, so that the field is filled without touching the keychain
        UserDefaults.standard.set(username, forKey: "gcvote.username")
        try? store.save(credentials)
    }

    /// Reads from the list when it last got ratings; called when the view appears and after an import.
    func readLastUpdated(list: URL?) {
        guard let list, let database = try? CacheDatabase(url: list),
              let text = database.info(GCVoteImporter.updatedKey) else {
            lastUpdated = nil
            return
        }
        lastUpdated = ISO8601DateFormatter().date(from: text)
    }

    /// Asks GCVote about `codes` and writes the ratings into the list at `list`.
    /// `onFinished` runs afterwards, so that the list and the selected cache are read again.
    func start(codes: [String], list: URL, onFinished: @escaping @MainActor () -> Void) {
        guard !isRunning, !codes.isEmpty else { return }
        isRunning = true
        result = nil
        error = nil
        progress = GCVoteImportProgress(done: 0, total: codes.count, rated: 0)
        let service = GCVoteService(server: server)
        let credentials = self.credentials
        let detached = Task.detached(priority: .userInitiated) { [weak self] () -> Result<GCVoteImportResult, Error> in
            await captureResult {
                let importer = GCVoteImporter(database: try CacheDatabase(url: list), service: service,
                                              credentials: credentials.isEmpty ? nil : credentials)
                importer.shouldCancel = { Task.isCancelled }
                return try await importer.importRatings(codes: codes) { progress in
                    Task { @MainActor in self?.progress = progress }
                }
            }
        }
        work = detached
        Task { [weak self] in
            let outcome = await detached.value
            guard let self else { return }
            switch outcome {
            case .success(let value): result = value
            case .failure(let failure): error = failure.localizedDescription
            }
            isRunning = false
            progress = nil
            readLastUpdated(list: list)
            onFinished()
        }
    }

    /// Stops after the running package; the ratings written so far stay (Cachebox also keeps them).
    func cancel() {
        work?.cancel()
    }

    func clearResult() {
        result = nil
        error = nil
    }

    /// "4 Bewertungen, 2 ohne Bewertung" - what the import wrote.
    static func summary(_ result: GCVoteImportResult) -> String {
        var parts = [Format.count(result.rated, "Bewertung", "Bewertungen")]
        if result.unrated > 0 { parts.append("\(result.unrated) ohne Bewertung") }
        if result.ownVotes > 0 { parts.append("\(result.ownVotes) × deine Stimme") }
        if result.skipped > 0 {
            parts.append("\(result.skipped) ohne GC-Code übersprungen")
        }
        if result.failedRequests > 0 {
            parts.append(result.failedRequests == 1 ? "1 Anfrage fehlgeschlagen"
                                                    : "\(result.failedRequests) Anfragen fehlgeschlagen")
        }
        return parts.joined(separator: ", ")
    }
}

/// `Result(catching:)` for an async body, so that the import can be wrapped in a detached task like the GPX import.
private func captureResult<Value>(_ body: () async throws -> Value) async -> Result<Value, Error> {
    do {
        return .success(try await body())
    } catch {
        return .failure(error)
    }
}
