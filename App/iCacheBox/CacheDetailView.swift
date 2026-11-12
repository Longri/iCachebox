import CacheboxCore
import SwiftUI

/// Details of the selected cache, read from its list for the cache views and the compass (Cachebox
/// `CachesDAO.loadDetail`), and the dialogs about it, which the cache button also opens from other views.
@MainActor
@Observable
final class SelectedCacheDetails {
    /// Everything of one cache read from its list.
    struct Details {
        var cache: Geocache
        var waypoints: [Waypoint]
        var logs: [CacheLog]
        var trackables: [Trackable]
    }

    private(set) var value: Details?
    /// Code whose details could not be read (e.g. deleted meanwhile).
    private(set) var missingCode: String?
    /// Main button 2 › Hinweis (Cachebox `ShowHint`).
    var showHint = false
    /// Main button 2 › Notizen (Cachebox `ShowNotes`).
    var editingNote = false
    /// "Aus der Liste löschen" in the cache menu.
    var confirmDelete = false

    func load(code: String?, list: URL?) async {
        guard let code, let list else {
            value = nil
            return
        }
        let loaded = await Task.detached(priority: .userInitiated) { () -> Details? in
            guard let database = try? CacheDatabase(url: list), let cache = try? database.cache(code: code) else { return nil }
            return Details(cache: cache, waypoints: (try? database.waypoints(cacheCode: code)) ?? [],
                           logs: (try? database.logs(cacheCode: code)) ?? [],
                           trackables: (try? database.trackables(cacheCode: code)) ?? [])
        }.value
        guard !Task.isCancelled else { return }
        value = loaded
        missingCode = loaded == nil ? code : nil
    }

    func noteChanged(_ note: String, code: String) {
        if value?.cache.code == code { value?.cache.note = note }
    }
}

/// Main button 2: description, waypoints, logs and spoiler of the selected cache (Cachebox: the views behind the
/// cache button). The segmented control switches like the button's menu and swipes.
struct CacheDetailView: View {
    /// The views of the cache button, in the order of the segmented control.
    private static let parts: [MainView] = [.description, .waypoints, .logs, .spoiler]

    @Environment(AppState.self) private var state
    @State private var descriptionHeight: CGFloat = 200

    private var details: SelectedCacheDetails.Details? { state.selectedDetails }

    var body: some View {
        NavigationStack {
            Group {
                if let summary = state.selectedCache {
                    content(summary)
                } else {
                    ContentUnavailableView {
                        Label("Kein Cache gewählt", systemImage: "doc.text")
                    } description: {
                        Text("Wähle einen Cache in der Cacheliste.")
                    } actions: {
                        Button("Zur Cacheliste") { state.show(.cacheList) }
                    }
                }
            }
            .navigationTitle(state.selectedCache?.name ?? "Cache")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var part: Binding<MainView> {
        Binding(get: { Self.parts.contains(state.view) ? state.view : state.lastViews[.cache] ?? .description },
                set: { state.show($0) })
    }

    @ViewBuilder
    private func content(_ summary: CacheSummary) -> some View {
        VStack(spacing: 0) {
            Picker("Ansicht", selection: part) {
                ForEach(Self.parts, id: \.self) { Text($0 == .description ? "Beschr." : $0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()

            if let details {
                switch part.wrappedValue {
                case .waypoints: waypoints(details)
                case .logs: logs(details)
                case .spoiler:
                    ContentUnavailableView("Spoiler", systemImage: "photo",
                                           description: Text("Spoilerbilder werden noch nicht geladen."))
                default: description(details, summary)
                }
            } else if state.details.missingCode == summary.code {
                ContentUnavailableView("Cache nicht gefunden", systemImage: "exclamationmark.triangle",
                                       description: Text("\(summary.code) ist nicht mehr in der Liste "
                                                         + "„\(state.lists.currentName ?? "")“."))
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Hinweis", systemImage: "lightbulb") { state.perform(.hint) }
                    .disabled(!state.isEnabled(.hint))
                CacheboxMenuButton {
                    ViewContextMenu(title: summary.name, entries: state.cacheEntries(summary))
                } label: {
                    Label("Aktionen", systemImage: "ellipsis.circle")
                }
            }
        }
        .alert("„\(summary.name)“ löschen?", isPresented: Bindable(state.details).confirmDelete) {
            Button("Löschen", role: .destructive) {
                state.lists.deleteCaches([summary.code])
                state.refreshSelection()
                state.show(.cacheList)
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Der Cache wird mit Wegpunkten, Logs und deiner Notiz aus der Liste entfernt.")
        }
    }

    // MARK: - Description

    private func description(_ details: SelectedCacheDetails.Details, _ summary: CacheSummary) -> some View {
        let cache = details.cache
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    CacheTypeIcon(type: cache.type, isFound: summary.isFound, isFavorite: summary.isFavorite,
                                  isArchived: cache.isArchived, isUnavailable: !cache.isAvailable,
                                  isSolved: summary.isSolved)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cache.name).font(.headline)
                        Text("\(cache.code) · \(cache.type.title) · von \(cache.owner)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                status(cache)
                facts(cache, details)
                if !cache.note.isEmpty {
                    GroupBox("Meine Notiz") {
                        Text(cache.note).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onTapGesture { state.details.editingNote = true }
                }
                if !cache.attributes.isEmpty { CacheAttributeIcons(attributes: cache.attributes) }
                if !descriptionHTML(cache).isEmpty {
                    Divider()
                    HTMLView(html: descriptionHTML(cache), height: $descriptionHeight)
                        .frame(height: descriptionHeight)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    @ViewBuilder
    private func status(_ cache: Geocache) -> some View {
        if cache.isArchived {
            Label("Archiviert", systemImage: "archivebox.fill").foregroundStyle(.red)
        } else if !cache.isAvailable {
            Label("Vorübergehend deaktiviert", systemImage: "pause.circle.fill").foregroundStyle(.orange)
        }
    }

    private func facts(_ cache: Geocache, _ details: SelectedCacheDetails.Details) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("Schwierigkeit").foregroundStyle(.secondary)
                Text("\(CacheSummary.rating(cache.difficulty)) · Gelände \(CacheSummary.rating(cache.terrain))")
            }
            GridRow {
                Text("Größe").foregroundStyle(.secondary)
                Text(cache.container.title)
            }
            GridRow {
                Text("Koordinaten").foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                    Text(cache.target.formatted).monospacedDigit().textSelection(.enabled)
                    if cache.correctedCoordinate != nil {
                        Text("korrigiert, Original \(cache.coordinate.formatted)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let hidden = cache.hidden {
                GridRow {
                    Text(cache.type.isEvent ? "Datum" : "Versteckt").foregroundStyle(.secondary)
                    Text(hidden.formatted(date: .abbreviated, time: .omitted))
                }
            }
            if !cache.state.isEmpty || !cache.country.isEmpty {
                GridRow {
                    Text("Region").foregroundStyle(.secondary)
                    Text([cache.state, cache.country].filter { !$0.isEmpty }.joined(separator: ", "))
                }
            }
            if let points = cache.favoritePoints {
                GridRow {
                    Text("Favoriten").foregroundStyle(.secondary)
                    Text("\(points) Punkte")
                }
            }
            if !details.trackables.isEmpty {
                GridRow {
                    Text("Trackables").foregroundStyle(.secondary)
                    Text(details.trackables.map(\.name).joined(separator: ", "))
                }
            }
            if !cache.gpxFile.isEmpty {
                GridRow {
                    Text("Importiert aus").foregroundStyle(.secondary)
                    Text(cache.gpxFile)
                }
            }
        }
        .font(.subheadline)
    }

    /// Short and long description as one HTML text; plain text gets its line breaks kept.
    private func descriptionHTML(_ cache: Geocache) -> String {
        func part(_ text: String, _ isHTML: Bool) -> String {
            text.isEmpty ? "" : (isHTML ? text : text.htmlEscapedParagraphs)
        }
        return [part(cache.shortDescription, cache.shortDescriptionIsHTML),
                part(cache.longDescription, cache.longDescriptionIsHTML)]
            .filter { !$0.isEmpty }
            .joined(separator: "<hr>")
    }

    // MARK: - Waypoints and logs

    private func waypoints(_ details: SelectedCacheDetails.Details) -> some View {
        List {
            Section {
                // "Solved" also with a final that has coordinates, like `CacheSummary.isSolved`
                let hasFinal = details.waypoints.contains {
                    $0.type == .final && $0.coordinate.map { $0.latitude != 0 || $0.longitude != 0 } == true
                }
                waypointRow(icon: details.cache.type.iconName(solved: details.cache.correctedCoordinate != nil || hasFinal),
                            title: "Cache", code: details.cache.code, coordinate: details.cache.target, comment: "")
            }
            Section {
                ForEach(details.waypoints) { waypoint in
                    waypointRow(icon: waypoint.type.iconName,
                                title: waypoint.title.isEmpty ? waypoint.type.title : waypoint.title,
                                code: "\(waypoint.code) · \(waypoint.type.title)",
                                coordinate: waypoint.coordinate, comment: waypoint.comment)
                }
            } footer: {
                if details.waypoints.isEmpty { Text("Keine zusätzlichen Wegpunkte.") }
            }
        }
    }

    private func waypointRow(icon: String, title: String, code: String, coordinate: Coordinate?,
                             comment: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CacheboxIcon(name: icon, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(code).font(.caption).foregroundStyle(.secondary)
                Text(coordinate?.formatted ?? "Koordinaten verborgen")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(coordinate == nil ? .secondary : .primary)
                if !comment.isEmpty {
                    Text(comment).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let coordinate, let here = state.location.coordinate {
                Text(Format.distance(here.distance(to: coordinate)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func logs(_ details: SelectedCacheDetails.Details) -> some View {
        List(details.logs) { log in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: log.type.symbol).foregroundStyle(log.type.color)
                    Text(log.finder).font(.subheadline.weight(.semibold))
                    Spacer()
                    if let date = log.date {
                        Text(date.formatted(date: .numeric, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(log.type.title).font(.caption).foregroundStyle(.secondary)
                Text(log.text).font(.subheadline)
            }
            .accessibilityElement(children: .combine)
        }
        .overlay {
            if details.logs.isEmpty {
                ContentUnavailableView("Keine Logs", systemImage: "text.bubble",
                                       description: Text("Die importierte Datei enthielt keine Logs zu diesem Cache."))
            }
        }
    }
}

/// Edits the user's own note of a cache (kept on re-import).
struct NoteEditor: View {
    let code: String
    @State var text: String
    let onSave: (String) -> Void

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .padding(.horizontal)
                .navigationTitle("Notiz")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Sichern") {
                            try? state.lists.database()?.setNote(text, code: code)
                            onSave(text)
                            dismiss()
                        }
                    }
                }
        }
    }
}
