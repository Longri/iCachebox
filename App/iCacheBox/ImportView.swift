import CacheboxCore
import SwiftUI
import UniformTypeIdentifiers

/// GPX import: choose the target list, then one or more GPX files or pocket query ZIPs
/// (Cachebox: Import dialog, "Pocket Query, Spoiler, …"). Progress and result appear in `ImportStatusCard`.
struct ImportView: View {
    /// Shown as a sheet from the cache list (closes itself after choosing files).
    var isSheet = false

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var target = Target.current
    @State private var newName = ""
    @State private var showPicker = false

    enum Target: Hashable {
        case current, existing(String), new
    }

    static let gpxType = UTType(importedAs: "com.topografix.gpx", conformingTo: .xml)

    private var lists: CacheListModel { state.lists }

    var body: some View {
        Form {
            Section {
                Picker("Importieren in", selection: $target) {
                    if let current = lists.currentName {
                        Text("\(current) (geöffnet)").tag(Target.current)
                    }
                    ForEach(lists.lists.filter { $0.name != lists.currentName }) { list in
                        Text(list.name).tag(Target.existing(list.name))
                    }
                    Text("Neue Liste").tag(Target.new)
                }
                if target == .new || lists.currentName == nil {
                    TextField("Name der neuen Liste", text: $newName, prompt: Text(CacheListModel.defaultListName))
                }
            } header: {
                Text("Ziel")
            } footer: {
                Text("Vorhandene Caches werden aktualisiert. Deine Notizen, Favoriten, Fund-Markierungen und "
                     + "korrigierten Koordinaten bleiben erhalten.")
            }
            Section {
                Button {
                    showPicker = true
                } label: {
                    Label("Dateien wählen …", systemImage: "doc.badge.plus")
                }
                .disabled(lists.importStatus?.isRunning == true)
            } footer: {
                Text("GPX-Dateien (GPX 1.0 und 1.1 mit Groundspeak-Erweiterung, z. B. von geocaching.com, GSAK oder "
                     + "c:geo) und Pocket-Query-ZIPs. Mehrere Dateien auf einmal sind möglich; Wegpunktdateien "
                     + "(„-wpts.gpx“) werden ihren Caches zugeordnet.")
            }
            Section("Tipp") {
                Text("Eine GPX- oder ZIP-Datei lässt sich auch aus Dateien, Mail oder Safari mit "
                     + "„Teilen › iCacheBox“ öffnen. Sie landet dann in der geöffneten Liste.")
                    .font(.footnote)
            }
        }
        .navigationTitle("GPX importieren")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
        }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [Self.gpxType, .zip, .xml],
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            start(urls)
        }
        .onAppear { if lists.currentName == nil { target = .new } }
    }

    private func start(_ urls: [URL]) {
        let name: String?
        switch target {
        case .current where lists.currentName != nil: name = lists.currentName
        case .existing(let existing): name = existing
        default:
            let typed = newName.trimmingCharacters(in: .whitespaces)
            name = typed.isEmpty ? uniqueNewName() : typed
        }
        lists.importFiles(urls, into: name)
        state.show(.cacheList)
        if isSheet { dismiss() }
    }

    /// "Meine Caches", or "Meine Caches 2" if that exists.
    private func uniqueNewName() -> String {
        let base = CacheListModel.defaultListName
        let names = Set(lists.lists.map { $0.name.lowercased() })
        guard names.contains(base.lowercased()) else { return base }
        var number = 2
        while names.contains("\(base) \(number)".lowercased()) { number += 1 }
        return "\(base) \(number)"
    }
}

/// Progress and result of the running import, floating above the tabs.
struct ImportStatusCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let status = state.lists.importStatus {
            VStack(alignment: .leading, spacing: 8) {
                if let error = status.error {
                    Label("Import fehlgeschlagen", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text(error).font(.subheadline)
                } else if let result = status.result {
                    Label("Import in „\(status.listName)“ fertig", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text(summary(result)).font(.subheadline)
                } else {
                    Label("Importiere in „\(status.listName)“ …", systemImage: "square.and.arrow.down")
                        .font(.headline)
                    if let progress = status.progress, progress.total > 0 {
                        ProgressView(value: Double(min(progress.done, progress.total)), total: Double(progress.total))
                        Text("\(progress.file): \(progress.done) von \(progress.total) · "
                             + Format.count(progress.caches, "Cache", "Caches"))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
                HStack {
                    Spacer()
                    if status.isRunning {
                        Button("Abbrechen", role: .cancel) { state.lists.cancelImport() }
                    } else {
                        Button("OK") { state.lists.importStatus = nil }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 8, y: 2)
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// "3 neue Caches, 2 aktualisiert, 5 Wegpunkte, 40 Logs" (Cachebox: toast "N Caches / M Logs").
    private func summary(_ result: GPXImportResult) -> String {
        var parts = [Format.count(result.newCaches, "neuer Cache", "neue Caches")]
        if result.updatedCaches > 0 { parts.append("\(result.updatedCaches) aktualisiert") }
        if result.waypoints > 0 { parts.append(Format.count(result.waypoints, "Wegpunkt", "Wegpunkte")) }
        if result.logs > 0 { parts.append(Format.count(result.logs, "Log", "Logs")) }
        var text = parts.joined(separator: ", ")
        if result.orphanWaypoints > 0 {
            text += result.orphanWaypoints == 1
                ? ". 1 Wegpunkt ohne passenden Cache wurde übersprungen."
                : ". \(result.orphanWaypoints) Wegpunkte ohne passenden Cache wurden übersprungen."
        }
        if result.caches == 0 && result.waypoints == 0 {
            text = "Die Datei enthielt keine Geocaches."
        }
        return text
    }
}
