import SwiftUI

/// "Mehr → Karten und Themes": Freizeitkarte maps and designs to download, installed ones to delete
/// (Cachebox: map download menu / `FZKDownload`).
struct MapDownloadView: View {
    @Environment(AppState.self) private var state
    @State private var search = ""
    @State private var confirm: MapCatalogEntry?
    @State private var deleting: MapCatalogEntry?

    private var library: MapLibrary { state.mapLibrary }
    private let language = Locale.current.language.languageCode?.identifier ?? "en"

    var body: some View {
        // Cachebox day skin like the FZK download dialog: green, the entries as boxes
        List {
            if let catalog = library.catalog {
                if !installed.isEmpty {
                    CacheboxListText("Auf diesem Gerät", isHeader: true)
                    ForEach(Array(installed.enumerated()), id: \.element.id) { index, entry in
                        row(entry, deletable: true).cacheboxListRow(index: index)
                    }
                    if let free = library.availableSpace {
                        CacheboxListText("Frei: \(Self.bytes(free))")
                    }
                }
                CacheboxListText("Karten", isHeader: true)
                ForEach(Array(filtered(catalog.entries.filter { $0.kind == .map }).enumerated()), id: \.element.id) {
                    index, entry in
                    row(entry).cacheboxListRow(index: index)
                }
                CacheboxListText(catalog.hint(language: language))
                CacheboxListText("Designs", isHeader: true)
                ForEach(Array(filtered(catalog.entries.filter { $0.kind == .theme }).enumerated()), id: \.element.id) {
                    index, entry in
                    row(entry).cacheboxListRow(index: index)
                }
                CacheboxListText("Mit der ersten Karte wird das Standard-Design mitgeladen.")
                CacheboxDivider().cacheboxListDivider()
                Link(destination: FreizeitkarteCatalog.homepage) {
                    Label("Freizeitkarte-OSM", systemImage: "safari")
                }
                .cacheboxListRow(index: 0)
                CacheboxListText(FreizeitkarteCatalog.attribution)
            } else if library.loadingCatalog {
                ProgressView("Lade Kartenliste …")
                    .frame(maxWidth: .infinity)
                    .cacheboxPlainRow()
            } else {
                ContentUnavailableView {
                    Label("Kartenliste nicht verfügbar", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(library.catalogError ?? "")
                } actions: {
                    Button("Erneut versuchen") { Task { await library.loadCatalog() } }
                }
                .cacheboxPlainRow()
            }
        }
        .cacheboxPage()
        .searchable(text: $search, prompt: "Region suchen")
        .navigationTitle("Karten und Themes")
        .refreshable { await library.loadCatalog() }
        .task { await library.loadCatalog() }
        .safeAreaInset(edge: .bottom) {
            if let error = library.catalogError, library.catalog != nil {
                Label(error, systemImage: "wifi.exclamationmark")
                    .font(.footnote)
                    .padding(8)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .alert(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
               presenting: confirm) { entry in
            if hasSpace(for: entry) {
                Button("Laden") { library.download(entry) }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { entry in
            Text(confirmMessage(entry))
        }
        // an alert, not a confirmation dialog: on iOS 26 that is a popover anchored at the list, not at the row
        .alert(deleting.map { "„\($0.title(language: language))“ löschen?" } ?? "",
               isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
               presenting: deleting) { entry in
            Button("Löschen", role: .destructive) { library.delete(entry.id) }
            Button("Abbrechen", role: .cancel) {}
        } message: { entry in
            Text(deleteMessage(entry))
        }
    }

    // MARK: - Rows

    /// `deletable`: rows of the installed section get a visible delete button instead of the check mark.
    private func row(_ entry: MapCatalogEntry, deletable: Bool = false) -> some View {
        let entryState = library.state(of: entry)
        let isInstalled = entryState == .installed || entryState == .updateAvailable
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title(language: language))
                Text(subtitle(entry, entryState))
                    .font(.caption)
                    .foregroundStyle(isFailure(entryState) ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(2)
            }
            Spacer()
            if deletable, isInstalled {
                if entryState == .updateAvailable { control(entry, entryState) }
                iconButton("trash", "Löschen") { deleting = entry }
                    .tint(.red)
            } else {
                control(entry, entryState)
            }
        }
        .swipeActions {
            switch entryState {
            case .installed, .updateAvailable:
                Button { deleting = entry } label: { Label("Löschen", systemImage: "trash") }
                    .tint(.red)
            case .paused, .failed:
                Button("Verwerfen", role: .destructive) { library.discard(entry.id) }
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func control(_ entry: MapCatalogEntry, _ entryState: MapLibrary.EntryState) -> some View {
        switch entryState {
        case .available:
            iconButton("arrow.down.circle", "Laden") { start(entry) }
        case .updateAvailable:
            iconButton("arrow.clockwise.circle", "Aktualisieren") { start(entry) }
        case .downloading(let fraction):
            Button { library.pause(entry.id) } label: {
                ZStack {
                    ProgressView(value: fraction).progressViewStyle(.circular)
                    Image(systemName: "stop.fill").font(.system(size: 9))
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Download anhalten, \(Int(fraction * 100)) Prozent")
        case .paused:
            iconButton("play.circle", "Fortsetzen") { library.download(entry) }
        case .installing:
            ProgressView().accessibilityLabel("Wird entpackt")
        case .failed:
            iconButton("arrow.clockwise.circle", "Erneut versuchen") { library.download(entry) }
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.tint)
                .accessibilityLabel("Installiert")
        }
    }

    private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title2)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }

    private func subtitle(_ entry: MapCatalogEntry, _ entryState: MapLibrary.EntryState) -> String {
        let size = Self.bytes(entry.size)
        switch entryState {
        case .available: return size
        case .updateAvailable: return "\(size) · neue Ausgabe \(entry.release)"
        case .downloading(let fraction): return "\(Self.bytes(Int64(Double(entry.size) * fraction))) von \(size)"
        case .paused(let fraction):
            return fraction > 0 ? "Angehalten bei \(Int(fraction * 100)) %" : "Angehalten"
        case .installing: return "Wird geprüft und entpackt …"
        case .failed(let message): return message
        case .installed:
            return "\(Self.bytes(entry.unpackedSize ?? entry.size)) · Ausgabe \(entry.release)"
        }
    }

    private func deleteMessage(_ entry: MapCatalogEntry) -> String {
        let freed = Self.bytes(library.installedSize(entry.id))
        switch entry.kind {
        case .map:
            return "Gibt \(freed) frei. Die Karte lässt sich jederzeit wieder laden."
        case .theme:
            return "Gibt \(freed) frei. Ohne Freizeitkarte-Design werden diese Karten mit dem Standard-Theme "
                + "gezeichnet. Das Design lässt sich jederzeit wieder laden."
        }
    }

    private func isFailure(_ entryState: MapLibrary.EntryState) -> Bool {
        if case .failed = entryState { return true }
        return false
    }

    // MARK: - Data

    /// Installed entries, with the current catalog data if the catalog still lists them.
    private var installed: [MapCatalogEntry] {
        library.installations.values
            .map { library.catalog?.entry($0.entry.id) ?? $0.entry }
            .sorted { $0.title(language: language) < $1.title(language: language) }
    }

    private func filtered(_ entries: [MapCatalogEntry]) -> [MapCatalogEntry] {
        let sorted = entries.sorted { $0.title(language: language) < $1.title(language: language) }
        guard !search.isEmpty else { return sorted }
        return sorted.filter {
            $0.title(language: language).localizedStandardContains(search) || $0.id.localizedStandardContains(search)
        }
    }

    // MARK: - Starting downloads

    /// Small files start at once; large ones (or too little space) ask first.
    private func start(_ entry: MapCatalogEntry) {
        if entry.size < 100_000_000, hasSpace(for: entry) {
            library.download(entry)
        } else {
            confirm = entry
        }
    }

    private func hasSpace(for entry: MapCatalogEntry) -> Bool {
        guard let free = library.availableSpace else { return true }
        return free > library.requiredSpace(for: entry)
    }

    private var confirmTitle: String {
        guard let entry = confirm else { return "" }
        return hasSpace(for: entry) ? "\(Self.bytes(entry.size)) laden?" : "Zu wenig Speicher"
    }

    private func confirmMessage(_ entry: MapCatalogEntry) -> String {
        let needed = Self.bytes(library.requiredSpace(for: entry))
        let free = library.availableSpace.map(Self.bytes) ?? "unbekannt"
        if hasSpace(for: entry) {
            return "\(entry.title(language: language)) braucht entpackt etwa \(needed) (frei: \(free)). "
                + "Der Download läuft auch weiter, wenn die App im Hintergrund ist. Im Mobilfunknetz können Kosten entstehen."
        }
        return "\(entry.title(language: language)) braucht etwa \(needed), frei sind \(free)."
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
