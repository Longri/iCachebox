import Foundation
import Observation
import UIKit

/// Downloaded maps and themes plus their downloads (Cachebox: `FZKDownload`).
///
/// Maps go to `Documents/Maps`, themes to `Documents/Themes/<folder>`; both are excluded from backups because
/// they can be downloaded again. Downloads run in a background `URLSession`, so multi-GB maps continue while
/// the app is suspended; a stopped download keeps its resume data. Archives are checked against the catalog's
/// MD5 checksum and unpacked afterwards; an unpack interrupted by the system is repeated on the next start.
@MainActor
@Observable
final class MapLibrary {
    static let shared = MapLibrary()

    enum EntryState: Equatable {
        case available
        case downloading(Double)
        case paused(Double)
        case installing
        case failed(String)
        case installed
        case updateAvailable
    }

    /// An installed catalog entry with the files it created (paths relative to `Documents`).
    struct Installation: Codable, Sendable {
        let entry: MapCatalogEntry
        let files: [String]
        let date: Date
    }

    private struct Transfer: Equatable {
        enum Phase: Equatable { case downloading, paused, installing, failed(String) }
        var phase: Phase
        var fraction: Double
    }

    private(set) var catalog: MapCatalog?
    private(set) var catalogError: String?
    private(set) var loadingCatalog = false
    private(set) var installations: [String: Installation] = [:]
    private var transfers: [String: Transfer] = [:]

    nonisolated static var documents: URL { URL.documentsDirectory }
    nonisolated static var mapsFolder: URL { documents.appending(path: "Maps", directoryHint: .isDirectory) }
    nonisolated static var themesFolder: URL { documents.appending(path: "Themes", directoryHint: .isDirectory) }
    /// Downloaded archives, resume data, pending entries, installation list and the cached catalog.
    nonisolated static var workFolder: URL {
        URL.applicationSupportDirectory.appending(path: "MapDownloads", directoryHint: .isDirectory)
    }

    /// Called by the app delegate when the system relaunched the app for finished background downloads.
    @ObservationIgnored var backgroundEventsCompletion: (() -> Void)?

    @ObservationIgnored private var session: URLSession!
    @ObservationIgnored private var tasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var backgroundTasks: [String: UIBackgroundTaskIdentifier] = [:]
    private static let sessionIdentifier = (Bundle.main.bundleIdentifier ?? "iCacheBox") + ".mapdownloads"

    private init() {
        let fm = FileManager.default
        for var folder in [Self.mapsFolder, Self.themesFolder, Self.workFolder] {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? folder.setResourceValues(values)
        }
        // leftovers of an interrupted unpack
        for folder in [Self.mapsFolder, Self.themesFolder] {
            for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
            where name.hasPrefix(".staging-") || name.hasSuffix(".part") {
                try? fm.removeItem(at: folder.appending(path: name))
            }
        }
        if let data = try? Data(contentsOf: Self.workFolder.appending(path: "installed.json")) {
            installations = (try? JSONDecoder().decode([String: Installation].self, from: data)) ?? [:]
        }
        if let data = try? Data(contentsOf: Self.workFolder.appending(path: "catalog.xml")) {
            catalog = try? FreizeitkarteCatalog.parse(data)
        }

        let delegate = DownloadDelegate(folder: Self.workFolder) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        restore()
    }

    // MARK: - Catalog

    func loadCatalog() async {
        guard !loadingCatalog else { return }
        loadingCatalog = true
        defer { loadingCatalog = false }
        do {
            let request = URLRequest(url: FreizeitkarteCatalog.url, cachePolicy: .reloadIgnoringLocalCacheData,
                                     timeoutInterval: 30)
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw CatalogError("Katalog nicht erreichbar (HTTP \(http.statusCode))")
            }
            catalog = try FreizeitkarteCatalog.parse(data)
            catalogError = nil
            try? data.write(to: Self.workFolder.appending(path: "catalog.xml"))
        } catch {
            catalogError = error.localizedDescription
        }
    }

    // MARK: - State

    func state(of entry: MapCatalogEntry) -> EntryState {
        if let transfer = transfers[entry.id] {
            switch transfer.phase {
            case .downloading: return .downloading(transfer.fraction)
            case .paused: return .paused(transfer.fraction)
            case .installing: return .installing
            case .failed(let message): return .failed(message)
            }
        }
        guard let installation = installations[entry.id] else { return .available }
        return installation.entry.release == entry.release ? .installed : .updateAvailable
    }

    var isBusy: Bool { transfers.values.contains { $0.phase == .downloading || $0.phase == .installing } }

    /// Free space on the data volume for downloads the user started.
    var availableSpace: Int64? {
        let values = try? URL.documentsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// Space a download needs: the archive plus the unpacked files.
    func requiredSpace(for entry: MapCatalogEntry) -> Int64 {
        entry.size + (entry.unpackedSize ?? entry.size * 3)
    }

    /// The catalog's default design, loaded together with the first map so that it renders as intended.
    private var missingDefaultTheme: MapCatalogEntry? {
        guard !installations.values.contains(where: { $0.entry.kind == .theme }),
              !transfers.keys.contains(where: { catalog?.entry($0)?.kind == .theme }) else { return nil }
        return catalog?.entries.first { $0.kind == .theme && $0.id == "freizeitkarte-v5" }
            ?? catalog?.entries.first { $0.kind == .theme }
    }

    // MARK: - Actions

    func download(_ entry: MapCatalogEntry) {
        if let phase = transfers[entry.id]?.phase, phase == .downloading || phase == .installing { return }
        let fm = FileManager.default
        let resumeURL = file(entry.id, "resume")
        if let pending = pendingEntry(entry.id), pending.url != entry.url {
            try? fm.removeItem(at: resumeURL)   // catalog moved on to a new release
        }
        savePending(entry)

        let task: URLSessionDownloadTask
        if let resumeData = try? Data(contentsOf: resumeURL) {
            task = session.downloadTask(withResumeData: resumeData)
            try? fm.removeItem(at: resumeURL)
        } else {
            task = session.downloadTask(with: entry.url)
        }
        task.taskDescription = entry.id
        task.countOfBytesClientExpectsToReceive = entry.size
        tasks[entry.id] = task
        transfers[entry.id] = Transfer(phase: .downloading, fraction: transfers[entry.id]?.fraction ?? 0)
        task.resume()

        if entry.kind == .map, let theme = missingDefaultTheme { download(theme) }
    }

    /// Stops a download and keeps what was loaded so far.
    func pause(_ id: String) {
        guard let task = tasks.removeValue(forKey: id) else { return }
        transfers[id]?.phase = .paused
        let resumeURL = file(id, "resume")
        task.cancel(byProducingResumeData: { data in
            try? data?.write(to: resumeURL)
        })
    }

    /// Stops a download and throws away everything loaded so far.
    func discard(_ id: String) {
        tasks.removeValue(forKey: id)?.cancel()
        transfers[id] = nil
        for ext in ["resume", "zip", "json"] { try? FileManager.default.removeItem(at: file(id, ext)) }
    }

    /// Bytes on disk taken by an installed entry (theme folders included).
    func installedSize(_ id: String) -> Int64 {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        func size(_ url: URL) -> Int64 {
            guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
            return values.isRegularFile == true ? Int64(values.totalFileAllocatedSize ?? 0) : 0
        }
        return (installations[id]?.files ?? []).reduce(0) { total, path in
            let url = Self.documents.appending(path: path)
            let nested = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys))?.allObjects as? [URL] ?? []
            return total + size(url) + nested.reduce(0) { $0 + size($1) }
        }
    }

    /// Deletes the files of an installed entry. A map shown on the map tab switches to another one there
    /// (`MapModel.refreshSources`).
    func delete(_ id: String) {
        guard let installation = installations.removeValue(forKey: id) else { return }
        for path in installation.files {
            try? FileManager.default.removeItem(at: Self.documents.appending(path: path))
        }
        saveInstallations()
    }

    // MARK: - Download events

    private func handle(_ event: DownloadDelegate.Event) {
        switch event {
        case .progress(let id, let written, let expected):
            guard transfers[id]?.phase == .downloading else { return }
            let total = expected > 0 ? expected : (pendingEntry(id)?.size ?? 0)
            guard total > 0 else { return }
            let fraction = min(1, Double(written) / Double(total))
            // avoid flooding SwiftUI with updates for every received packet
            if fraction - (transfers[id]?.fraction ?? 0) >= 0.002 || fraction == 1 {
                transfers[id]?.fraction = fraction
            }
        case .downloaded(let id, let error):
            tasks[id] = nil
            if let error {
                transfers[id] = Transfer(phase: .failed(error), fraction: 0)
                try? FileManager.default.removeItem(at: file(id, "zip"))
            } else {
                install(id)
            }
        case .failed(let id, let error, let resumeData):
            tasks[id] = nil
            if let resumeData { try? resumeData.write(to: file(id, "resume")) }
            transfers[id] = Transfer(phase: .failed(error), fraction: transfers[id]?.fraction ?? 0)
        case .finishedBackgroundEvents:
            backgroundEventsCompletion?()
            backgroundEventsCompletion = nil
        }
    }

    /// Checks and unpacks a downloaded archive off the main thread.
    private func install(_ id: String) {
        guard let entry = pendingEntry(id) else {
            transfers[id] = Transfer(phase: .failed("Download ohne Katalogeintrag"), fraction: 0)
            return
        }
        transfers[id] = Transfer(phase: .installing, fraction: 1)
        backgroundTasks[id] = UIApplication.shared.beginBackgroundTask(withName: "Karte entpacken") { [weak self] in
            MainActor.assumeIsolated { self?.endBackgroundTask(id) }
        }
        let zip = file(id, "zip")
        let previous = installations[id]
        Task {
            let result = await Task.detached(priority: .utility) {
                Result { try Self.unpack(entry, zip: zip) }
            }.value
            switch result {
            case .success(let files):
                // a new release may use other file names than the old one
                for path in Set(previous?.files ?? []).subtracting(files) {
                    try? FileManager.default.removeItem(at: Self.documents.appending(path: path))
                }
                installations[id] = Installation(entry: entry, files: files, date: .now)
                saveInstallations()
                transfers[id] = nil
                for ext in ["zip", "json", "resume"] { try? FileManager.default.removeItem(at: file(id, ext)) }
            case .failure(let error):
                transfers[id] = Transfer(phase: .failed(error.localizedDescription), fraction: 0)
                for ext in ["zip", "resume"] { try? FileManager.default.removeItem(at: file(id, ext)) }
            }
            endBackgroundTask(id)
        }
    }

    private func endBackgroundTask(_ id: String) {
        guard let task = backgroundTasks.removeValue(forKey: id) else { return }
        UIApplication.shared.endBackgroundTask(task)
    }

    /// Verifies the archive and moves its contents into `Maps` or `Themes`. Returns the installed paths
    /// relative to `Documents`.
    private nonisolated static func unpack(_ entry: MapCatalogEntry, zip: URL) throws -> [String] {
        if let md5 = entry.md5, !md5.isEmpty, try ZipArchive.md5(of: zip) != md5 {
            throw ZipError("Prüfsumme falsch, bitte erneut laden")
        }
        let archive = try ZipArchive(url: zip)
        let fm = FileManager.default
        var files: [String] = []
        switch entry.kind {
        case .map:
            let maps = archive.entries.filter { !$0.isDirectory && $0.path.lowercased().hasSuffix(".map") }
            guard !maps.isEmpty else { throw ZipError("Keine .map-Datei im Archiv") }
            for item in maps {
                let name = URL(filePath: item.path).lastPathComponent
                let part = mapsFolder.appending(path: ".\(name).part")
                try archive.extract(item, to: part)
                let target = mapsFolder.appending(path: name)
                try? fm.removeItem(at: target)
                try fm.moveItem(at: part, to: target)
                files.append("Maps/\(name)")
            }
        case .theme:
            let staging = themesFolder.appending(path: ".staging-\(UUID().uuidString)", directoryHint: .isDirectory)
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: staging) }
            for item in archive.entries {
                let components = item.path.split(separator: "/").map(String.init)
                guard !components.isEmpty, !item.path.hasPrefix("/"), !components.contains("..") else {
                    throw ZipError("Ungültiger Pfad im Archiv: \(item.path)")
                }
                let target = components.reduce(staging) { $0.appending(path: $1) }
                if item.isDirectory {
                    try fm.createDirectory(at: target, withIntermediateDirectories: true)
                } else {
                    try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try archive.extract(item, to: target)
                }
            }
            // keep each theme in a folder of its own, so that its symbols stay next to the XML
            var top = try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: [.isDirectoryKey])
            if top.contains(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }) {
                let wrapper = staging.appending(path: entry.id, directoryHint: .isDirectory)
                try fm.createDirectory(at: wrapper, withIntermediateDirectories: true)
                for url in top { try fm.moveItem(at: url, to: wrapper.appending(path: url.lastPathComponent)) }
                top = [wrapper]
            }
            for url in top {
                let target = themesFolder.appending(path: url.lastPathComponent)
                try? fm.removeItem(at: target)
                try fm.moveItem(at: url, to: target)
                files.append("Themes/\(url.lastPathComponent)")
            }
        }
        return files
    }

    // MARK: - Persistence

    /// Picks up downloads that ran while the app was not active and unpacks archives left behind.
    private func restore() {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: Self.workFolder.path)) ?? []
        for name in names where name.hasSuffix(".resume") {
            let id = String(name.dropLast(".resume".count))
            transfers[id] = Transfer(phase: .paused, fraction: 0)
        }
        session.getAllTasks { tasks in
            let running = tasks.compactMap { task -> (String, Double)? in
                guard let task = task as? URLSessionDownloadTask, let id = task.taskDescription,
                      task.state == .running || task.state == .suspended else { return nil }
                let expected = task.countOfBytesExpectedToReceive
                return (id, expected > 0 ? Double(task.countOfBytesReceived) / Double(expected) : 0)
            }
            let downloadTasks = tasks.compactMap { $0 as? URLSessionDownloadTask }
            Task { @MainActor in
                for (id, fraction) in running {
                    self.tasks[id] = downloadTasks.first { $0.taskDescription == id }
                    self.transfers[id] = Transfer(phase: .downloading, fraction: fraction)
                }
                for name in names where name.hasSuffix(".zip") {
                    let id = String(name.dropLast(".zip".count))
                    if self.tasks[id] == nil, self.transfers[id]?.phase != .installing { self.install(id) }
                }
            }
        }
    }

    private func file(_ id: String, _ ext: String) -> URL { Self.workFolder.appending(path: "\(id).\(ext)") }

    private func savePending(_ entry: MapCatalogEntry) {
        try? JSONEncoder().encode(entry).write(to: file(entry.id, "json"))
    }

    private func pendingEntry(_ id: String) -> MapCatalogEntry? {
        (try? Data(contentsOf: file(id, "json"))).flatMap { try? JSONDecoder().decode(MapCatalogEntry.self, from: $0) }
    }

    private func saveInstallations() {
        try? JSONEncoder().encode(installations).write(to: Self.workFolder.appending(path: "installed.json"))
    }
}

/// Receives the background session's callbacks and forwards them to the main actor.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    enum Event: Sendable {
        case progress(id: String, written: Int64, expected: Int64)
        /// The archive is at `<workFolder>/<id>.zip`, unless `error` is set.
        case downloaded(id: String, error: String?)
        case failed(id: String, error: String, resumeData: Data?)
        case finishedBackgroundEvents
    }

    private let folder: URL
    private let send: @Sendable (Event) -> Void

    init(folder: URL, send: @escaping @Sendable (Event) -> Void) {
        self.folder = folder
        self.send = send
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription else { return }
        send(.progress(id: id, written: totalBytesWritten, expected: totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            send(.downloaded(id: id, error: "Server antwortet mit HTTP \(http.statusCode)"))
            return
        }
        // the temporary file is deleted when this method returns
        let target = folder.appending(path: "\(id).zip")
        do {
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: location, to: target)
            send(.downloaded(id: id, error: nil))
        } catch {
            send(.downloaded(id: id, error: error.localizedDescription))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error, let id = task.taskDescription else { return }
        let nsError = error as NSError
        // pause/discard set the state themselves
        guard nsError.code != NSURLErrorCancelled else { return }
        send(.failed(id: id, error: error.localizedDescription,
                     resumeData: nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        send(.finishedBackgroundEvents)
    }
}
