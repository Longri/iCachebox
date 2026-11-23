import CacheboxCore
import Foundation
import Observation

/// Sort orders of the cache list. Cachebox sorts by distance only; the others are additions.
enum CacheSortOrder: String, CaseIterable, Identifiable, Codable {
    case distance, name, code, difficulty, terrain, hidden, favoritePoints

    var id: Self { self }

    var title: String {
        switch self {
        case .distance: "Entfernung"
        case .name: "Name"
        case .code: "GC-Code"
        case .difficulty: "Schwierigkeit"
        case .terrain: "Gelände"
        case .hidden: "Neueste zuerst"
        case .favoritePoints: "Favoritenpunkte"
        }
    }
}

/// Filter of the cache list (a small subset of Cachebox's `FilterProperties`).
struct CacheFilter: Codable, Equatable {
    enum Tristate: String, Codable, CaseIterable, Identifiable {
        case all, only, hide
        var id: Self { self }
    }

    var found = Tristate.all
    var unavailable = Tristate.all
    var archived = Tristate.all
    var favorites = Tristate.all
    /// Empty = all types.
    var types: Set<CacheType> = []
    var difficulty: ClosedRange<Double> = 1...5
    var terrain: ClosedRange<Double> = 1...5

    static let all = CacheFilter()
    /// Cachebox preset "All to find": not found, available, not archived.
    static let toFind = CacheFilter(found: .hide, unavailable: .hide, archived: .hide)

    var isActive: Bool { self != .all }

    func matches(_ cache: CacheSummary) -> Bool {
        func check(_ state: Tristate, _ value: Bool) -> Bool {
            switch state {
            case .all: true
            case .only: value
            case .hide: !value
            }
        }
        return check(found, cache.isFound)
            && check(unavailable, !cache.isAvailable && !cache.isArchived)
            && check(archived, cache.isArchived)
            && check(favorites, cache.isFavorite)
            && (types.isEmpty || types.contains(cache.type))
            && difficulty.contains(cache.difficulty) && terrain.contains(cache.terrain)
    }
}

/// A row of the cache list: the cache plus distance and bearing from the reference point.
struct CacheRow: Identifiable, Equatable {
    let cache: CacheSummary
    let distance: Double?
    let bearing: Double?
    var id: String { cache.code }
}

/// Import state shown as a sheet while files are read.
struct ImportStatus: Equatable {
    var listName: String
    var progress: GPXImportProgress?
    var result: GPXImportResult?
    var error: String?
    var isRunning: Bool { result == nil && error == nil }

    static func == (a: Self, b: Self) -> Bool {
        a.listName == b.listName && a.result == b.result && a.error == b.error
            && a.progress?.done == b.progress?.done && a.progress?.file == b.progress?.file
    }
}

/// The cache lists of the app and the caches of the open list (Cachebox: database selection and `CacheList`).
///
/// Lists are SQLite files in `Documents/Lists`; the open list, sort order and filter are kept in user defaults.
/// Database work runs off the main actor with its own connection.
@MainActor
@Observable
final class CacheListModel {
    nonisolated static let folder = URL.documentsDirectory.appending(path: "Lists", directoryHint: .isDirectory)
    nonisolated static let defaultListName = "Meine Caches"
    let store = CacheListStore(folder: CacheListModel.folder)

    private(set) var lists: [CacheListInfo] = []
    private(set) var currentName: String?
    /// All caches of the open list.
    private(set) var caches: [CacheSummary] = []
    /// Filtered and sorted caches with distances.
    private(set) var rows: [CacheRow] = []
    private(set) var isLoading = false
    var importStatus: ImportStatus?

    var sortOrder: CacheSortOrder {
        didSet { save(sortOrder, "cacheList.sort"); refreshRows() }
    }
    var filter: CacheFilter {
        didSet { save(filter, "cacheList.filter"); refreshRows() }
    }
    /// Reference point for distances: the device position, otherwise the selected cache.
    private(set) var reference: Coordinate?
    private(set) var referenceIsDevice = false

    /// Called after a list was opened and its caches are loaded (also after an import and after deleting the
    /// open list); `AppState` restores the selection of that list.
    @ObservationIgnored var onOpen: (() -> Void)?
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var importWork: Task<Result<GPXImportResult, Error>, Never>?

    init() {
        let defaults = UserDefaults.standard
        sortOrder = (defaults.data(forKey: "cacheList.sort").flatMap { try? JSONDecoder().decode(CacheSortOrder.self, from: $0) })
            ?? .distance
        filter = (defaults.data(forKey: "cacheList.filter").flatMap { try? JSONDecoder().decode(CacheFilter.self, from: $0) })
            ?? .all
        currentName = defaults.string(forKey: "cacheList.current")
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        reloadLists()
        if let name = currentName, !lists.contains(where: { $0.name == name }) { currentName = lists.first?.name }
        if currentName == nil { currentName = lists.first?.name }
    }

    var current: CacheListInfo? { lists.first { $0.name == currentName } }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }

    // MARK: - Lists

    func reloadLists() {
        lists = store.lists()
    }

    /// Opens a list and loads its caches.
    func open(_ name: String?) async {
        currentName = name
        UserDefaults.standard.set(name, forKey: "cacheList.current")
        await loadCaches()
        if currentName == name { onOpen?() }   // not if another list was opened meanwhile
    }

    func loadCaches() async {
        guard let name = currentName else {
            caches = []
            refreshRows()
            return
        }
        isLoading = true
        let url = store.url(of: name)
        let loaded = await Task.detached(priority: .userInitiated) { () -> [CacheSummary] in
            (try? CacheDatabase(url: url).summaries()) ?? []
        }.value
        guard name == currentName else { return }   // another list was opened meanwhile
        caches = loaded
        isLoading = false
        refreshRows()
    }

    func create(_ name: String) throws -> String {
        let created = try store.create(name)
        reloadLists()
        return created
    }

    func rename(_ name: String, to newName: String) throws {
        let renamed = try store.rename(name, to: newName)
        if currentName == name {
            currentName = renamed
            UserDefaults.standard.set(renamed, forKey: "cacheList.current")
        }
        reloadLists()
    }

    func delete(_ name: String) async throws {
        try store.delete(name)
        reloadLists()
        if currentName == name { await open(lists.first?.name) }
    }

    /// The cache last selected in a list, to select it again when the list is opened.
    func lastSelectedCode() -> String? {
        guard let name = currentName else { return nil }
        return try? CacheDatabase(url: store.url(of: name)).info("selectedCache")
    }

    func rememberSelection(_ code: String?) {
        guard let name = currentName, let code else { return }
        try? CacheDatabase(url: store.url(of: name)).setInfo("selectedCache", code)
    }

    // MARK: - Caches

    /// Opens a connection to the current list for reading details or changing flags.
    func database() -> CacheDatabase? {
        currentName.flatMap { try? CacheDatabase(url: store.url(of: $0)) }
    }

    func setFound(_ found: Bool, code: String) { update(code) { try $0.setFound(found, code: code) } mutate: { $0.isFound = found } }
    func setFavorite(_ favorite: Bool, code: String) {
        update(code) { try $0.setFavorite(favorite, code: code) } mutate: { $0.isFavorite = favorite }
    }

    private func update(_ code: String, _ write: (CacheDatabase) throws -> Void, mutate: (inout CacheSummary) -> Void) {
        guard let database = database(), (try? write(database)) != nil,
              let index = caches.firstIndex(where: { $0.code == code }) else { return }
        mutate(&caches[index])
        refreshRows()
    }

    func deleteCaches(_ codes: [String]) {
        guard !codes.isEmpty, let database = database() else { return }
        try? database.deleteCaches(codes: codes)
        let removed = Set(codes)
        caches.removeAll { removed.contains($0.code) }
        refreshRows()
        reloadLists()
    }

    // MARK: - Distances, sorting, filtering

    /// Sets the reference point; rows are recomputed when it moved noticeably (Cachebox resorts on GPS updates).
    func updateReference(device: Coordinate?, selected: Coordinate?) {
        let newReference = device ?? selected
        let isDevice = device != nil
        if let old = reference, let new = newReference, isDevice == referenceIsDevice, old.distance(to: new) < 15 { return }
        if reference == nil && newReference == nil { return }
        reference = newReference
        referenceIsDevice = isDevice
        refreshRows()
    }

    func refreshRows() {
        let reference = reference
        var rows = caches.filter(filter.matches).map { cache in
            // to the target like Cachebox `CacheList.resortList` (a final with coordinates counts)
            CacheRow(cache: cache, distance: reference.map { $0.distance(to: cache.target) },
                     bearing: reference.map { $0.bearing(to: cache.target) })
        }
        let byName: (CacheRow, CacheRow) -> Bool = {
            $0.cache.name.localizedStandardCompare($1.cache.name) == .orderedAscending
        }
        switch sortOrder {
        case .distance where reference != nil: rows.sort { ($0.distance ?? 0) < ($1.distance ?? 0) }
        case .distance, .name: rows.sort(by: byName)
        case .code: rows.sort { $0.cache.code.localizedStandardCompare($1.cache.code) == .orderedAscending }
        case .difficulty: rows.sort { $0.cache.difficulty == $1.cache.difficulty ? byName($0, $1) : $0.cache.difficulty < $1.cache.difficulty }
        case .terrain: rows.sort { $0.cache.terrain == $1.cache.terrain ? byName($0, $1) : $0.cache.terrain < $1.cache.terrain }
        case .hidden: rows.sort { ($0.cache.hidden ?? .distantPast) > ($1.cache.hidden ?? .distantPast) }
        case .favoritePoints: rows.sort { ($0.cache.favoritePoints ?? -1) > ($1.cache.favoritePoints ?? -1) }
        }
        self.rows = rows
    }

    // MARK: - Import

    /// Imports GPX/ZIP files into a list (created if needed) and opens it afterwards.
    func importFiles(_ urls: [URL], into listName: String?, removeAfterImport: Bool = false) {
        guard importTask == nil else { return }
        let name: String
        do {
            if let listName, lists.contains(where: { $0.name == listName }) {
                name = listName
            } else {
                name = try create(listName ?? Self.defaultListName)
            }
        } catch {
            importStatus = ImportStatus(listName: listName ?? "", error: error.localizedDescription)
            return
        }
        importStatus = ImportStatus(listName: name)
        let url = store.url(of: name)
        let work = Task.detached(priority: .userInitiated) { [weak self] () -> Result<GPXImportResult, Error> in
            Result {
                let importer = GPXImporter(database: try CacheDatabase(url: url))
                importer.shouldCancel = { Task.isCancelled }
                return try importer.importFiles(urls) { progress in
                    Task { @MainActor in self?.importStatus?.progress = progress }
                }
            }
        }
        importWork = work
        importTask = Task {
            let outcome = await work.value
            importWork = nil
            if removeAfterImport { for url in urls { try? FileManager.default.removeItem(at: url) } }
            switch outcome {
            case .success(let result): importStatus?.result = result
            case .failure(let error): importStatus?.error = error.localizedDescription
            }
            importTask = nil
            reloadLists()
            await open(name)
        }
    }

    /// Stops the import after the current cache; what was read so far stays in the list.
    func cancelImport() {
        importWork?.cancel()
    }
}
