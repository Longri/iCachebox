import CacheboxCore
import SwiftUI

/// Search text and dialogs of the cache list. Kept in `AppState`, because the menu of the list button opens them,
/// too, and the search decides which caches "Alle angezeigten" deletes.
@MainActor
@Observable
final class CacheListUI {
    var search = ""
    var showImport = false
    var showLists = false
    var showFilter = false
    var pendingDelete: CacheListView.DeleteChoice?

    /// Rows matching the search text (name, GC code or owner, like Cachebox's quick search).
    func shown(in lists: CacheListModel) -> [CacheRow] {
        let text = search.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return lists.rows }
        return lists.rows.filter {
            $0.cache.name.localizedCaseInsensitiveContains(text) || $0.cache.code.localizedCaseInsensitiveContains(text)
                || $0.cache.owner.localizedCaseInsensitiveContains(text)
        }
    }

    /// Codes of the caches a delete choice removes.
    func codes(for choice: CacheListView.DeleteChoice, in lists: CacheListModel) -> [String] {
        switch choice {
        case .found: lists.caches.filter(\.isFound).map(\.code)
        case .archived: lists.caches.filter(\.isArchived).map(\.code)
        case .shown: shown(in: lists).map(\.cache.code)
        }
    }
}

/// Main button 1: the caches of the open list, sorted and filtered (Cachebox: `GeoCachesView`).
///
/// The title menu switches between lists; the toolbar menu holds sort order, filter, import, list management and
/// deleting caches, like the menu of the list button (Cachebox: list menu). Tapping a row selects the cache and
/// shows its details.
struct CacheListView: View {
    @Environment(AppState.self) private var state

    private var lists: CacheListModel { state.lists }
    private var ui: CacheListUI { state.listUI }
    private var search: String { ui.search }
    private var shown: [CacheRow] { ui.shown(in: lists) }

    var body: some View {
        @Bindable var ui = state.listUI
        NavigationStack {
            content
                .navigationTitle(lists.currentName ?? "Caches")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarTitleMenu { listMenu }
                .searchable(text: $ui.search, placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "Name, GC-Code oder Owner")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Filter", systemImage: lists.filter.isActive
                               ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle") {
                            ui.showFilter = true
                        }
                        .disabled(lists.current == nil)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("Mehr", systemImage: "ellipsis.circle") {
                            MenuEntriesContent(entries: state.cacheListEntries)
                        }
                    }
                }
                .sheet(isPresented: $ui.showImport) { NavigationStack { ImportView(isSheet: true) } }
                .sheet(isPresented: $ui.showLists) { NavigationStack { CacheListsView() } }
                .sheet(isPresented: $ui.showFilter) { NavigationStack { CacheFilterView() } }
                .alert(ui.pendingDelete?.title ?? "", isPresented: Binding(get: { ui.pendingDelete != nil },
                                                                           set: { if !$0 { ui.pendingDelete = nil } }),
                       presenting: ui.pendingDelete) { choice in
                    Button("Löschen", role: .destructive) { delete(choice) }
                    Button("Abbrechen", role: .cancel) {}
                } message: { choice in
                    let count = ui.codes(for: choice, in: lists).count
                    Text((count == 1 ? "1 Cache wird" : "\(count) Caches werden")
                         + " mit Wegpunkten und Logs aus der Liste „\(lists.currentName ?? "")“ entfernt. "
                         + "Ein erneuter Import holt \(count == 1 ? "ihn" : "sie") zurück.")
                }
                .selectedCacheBar()
        }
        .task(id: lists.caches.isEmpty) {
            if !lists.caches.isEmpty { state.location.start() }
        }
        .onChange(of: state.location.coordinate) { updateReference() }
        .onChange(of: state.selectedCache?.code) { updateReference() }
        .onChange(of: lists.caches.count) { updateReference() }
    }

    private func updateReference() {
        lists.updateReference(device: state.location.coordinate, selected: state.selectedCache?.target)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if lists.current == nil {
            ContentUnavailableView {
                Label("Noch keine Caches", systemImage: "list.bullet")
            } description: {
                Text("Importiere eine GPX-Datei oder Pocket Query, um deine erste Cacheliste anzulegen.")
            } actions: {
                Button("GPX importieren") { ui.showImport = true }
                    .buttonStyle(.borderedProminent)
            }
        } else if lists.caches.isEmpty && !lists.isLoading {
            ContentUnavailableView {
                Label("Liste ist leer", systemImage: "tray")
            } description: {
                Text("„\(lists.currentName ?? "")“ enthält noch keine Caches.")
            } actions: {
                Button("GPX importieren") { ui.showImport = true }
                    .buttonStyle(.borderedProminent)
            }
        } else if shown.isEmpty && !lists.isLoading {
            if !search.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                ContentUnavailableView {
                    Label("Kein Cache passt zum Filter", systemImage: "line.3.horizontal.decrease.circle")
                } actions: {
                    Button("Filter zurücksetzen") { lists.filter = .all }
                }
            }
        } else {
            List {
                Section {
                    ForEach(shown) { row in
                        CacheRowView(row: row, isSelected: row.cache.code == state.selectedCache?.code,
                                     heading: state.location.heading, isDevice: lists.referenceIsDevice)
                            .contentShape(Rectangle())
                            .onTapGesture { state.select(row.cache) }
                            .accessibilityAddTraits(.isButton)
                            .swipeActions(edge: .leading) {
                                Button("Karte", systemImage: "map") { state.select(row.cache, show: .map) }
                                    .tint(.blue)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(row.cache.isFavorite ? "Kein Favorit" : "Favorit",
                                       systemImage: row.cache.isFavorite ? "star.slash" : "star") {
                                    toggleFavorite(row.cache)
                                }
                                .tint(.yellow)
                            }
                            .contextMenu { contextMenu(row.cache) }
                    }
                } header: {
                    Text(countText)
                }
            }
            .listStyle(.plain)
            .overlay { if lists.isLoading { ProgressView() } }
        }
    }

    /// "12 von 30 Caches · nach Entfernung" (Cachebox: count in the title).
    private var countText: String {
        let total = lists.caches.count
        let count = shown.count
        let caches = count == total ? Format.count(total, "Cache", "Caches") : "\(count) von \(total) Caches"
        let order = lists.sortOrder == .distance && lists.reference == nil ? "nach Name" : "nach \(lists.sortOrder.title)"
        let reference = lists.sortOrder == .distance && lists.reference != nil && !lists.referenceIsDevice
            ? " (vom gewählten Cache)" : ""
        return "\(caches) · \(order)\(reference)"
    }

    // MARK: - Menus

    @ViewBuilder
    private var listMenu: some View {
        ForEach(lists.lists) { list in
            Button {
                Task { await state.openList(list.name) }
            } label: {
                if list.name == lists.currentName {
                    Label("\(list.name) (\(list.cacheCount))", systemImage: "checkmark")
                } else {
                    Text("\(list.name) (\(list.cacheCount))")
                }
            }
        }
        Divider()
        Button("Listen verwalten …", systemImage: "folder") { ui.showLists = true }
    }

    @ViewBuilder
    private func contextMenu(_ cache: CacheSummary) -> some View {
        Button("Details", systemImage: "doc.text") { state.select(cache) }
        Button("Auf der Karte", systemImage: "map") { state.select(cache, show: .map) }
        Button(cache.isFavorite ? "Kein Favorit" : "Favorit", systemImage: cache.isFavorite ? "star.slash" : "star") {
            toggleFavorite(cache)
        }
        Button(cache.isFound ? "Als nicht gefunden markieren" : "Als gefunden markieren",
               systemImage: cache.isFound ? "xmark.circle" : "checkmark.circle") {
            lists.setFound(!cache.isFound, code: cache.code)
            state.refreshSelection()
        }
    }

    private func toggleFavorite(_ cache: CacheSummary) {
        lists.setFavorite(!cache.isFavorite, code: cache.code)
        state.refreshSelection()
    }

    // MARK: - Deleting caches (Cachebox: "Delete caches": filtered / archived / found)

    enum DeleteChoice: String, CaseIterable, Identifiable {
        case found, archived, shown
        var id: Self { self }

        var menuTitle: String {
            switch self {
            case .found: "Gefundene"
            case .archived: "Archivierte"
            case .shown: "Alle angezeigten"
            }
        }

        var title: String {
            switch self {
            case .found: "Gefundene Caches löschen?"
            case .archived: "Archivierte Caches löschen?"
            case .shown: "Angezeigte Caches löschen?"
            }
        }
    }

    private func delete(_ choice: DeleteChoice) {
        lists.deleteCaches(ui.codes(for: choice, in: lists))
        state.refreshSelection()
    }
}

/// One cache in the list: type icon with status marks, name, code and rating, distance and direction.
struct CacheRowView: View {
    let row: CacheRow
    var isSelected = false
    var heading: Double?
    /// The distance is measured from the device (otherwise from the selected cache; the arrow is grey then).
    var isDevice = true

    private var cache: CacheSummary { row.cache }

    var body: some View {
        HStack(spacing: 12) {
            CacheTypeIcon(type: cache.type, isFound: cache.isFound, isFavorite: cache.isFavorite,
                          isArchived: cache.isArchived, isUnavailable: !cache.isAvailable,
                          isSolved: cache.isSolved)
            VStack(alignment: .leading, spacing: 2) {
                Text(cache.name)
                    .strikethrough(cache.isArchived)
                    .foregroundStyle(cache.isArchived || !cache.isAvailable ? Color.red : Color.primary)
                    .lineLimit(2)
                Text("\(cache.code) · \(cache.ratingText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !extras.isEmpty {
                    Text(extras)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if let distance = row.distance, let bearing = row.bearing {
                VStack(spacing: 2) {
                    Image(systemName: "location.north.fill")
                        .rotationEffect(.degrees(bearing - (isDevice ? heading ?? 0 : 0)))
                        .foregroundStyle(isDevice ? Color.accentColor : Color.secondary)
                        .accessibilityHidden(true)
                    Text(Format.distance(distance))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 56)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Entfernung \(Format.distance(distance))")
            }
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Gewählt")
            }
        }
        .padding(.vertical, 2)
    }

    /// Trackables, favourite points and waypoints, like the bottom line of a Cachebox list row.
    private var extras: String {
        var parts: [String] = []
        if cache.trackableCount > 0 { parts.append("\(cache.trackableCount) Trackable" + (cache.trackableCount > 1 ? "s" : "")) }
        if let points = cache.favoritePoints, points > 0 { parts.append("♥ \(points)") }
        if cache.waypointCount > 0 { parts.append("\(cache.waypointCount) Wegpunkt" + (cache.waypointCount > 1 ? "e" : "")) }
        if !cache.isAvailable && !cache.isArchived { parts.append("deaktiviert") }
        if cache.isArchived { parts.append("archiviert") }
        return parts.joined(separator: " · ")
    }
}
