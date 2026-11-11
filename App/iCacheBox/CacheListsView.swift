import CacheboxCore
import SwiftUI

/// List management: open, create, rename and delete cache lists (Cachebox: "select database").
struct CacheListsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Editing?
    @State private var name = ""
    @State private var errorMessage: String?
    @State private var pendingDelete: CacheListInfo?

    private var lists: CacheListModel { state.lists }

    enum Editing: Identifiable, Equatable {
        case create
        case rename(String)
        var id: String {
            switch self {
            case .create: "create"
            case .rename(let name): "rename-" + name
            }
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(lists.lists) { list in
                    Button {
                        Task {
                            await state.openList(list.name)
                            dismiss()
                        }
                    } label: {
                        row(list)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Löschen", systemImage: "trash") { pendingDelete = list }
                            .tint(.red)
                        Button("Umbenennen", systemImage: "pencil") {
                            name = list.name
                            editing = .rename(list.name)
                        }
                        .tint(.orange)
                    }
                    .contextMenu {
                        Button("Umbenennen", systemImage: "pencil") {
                            name = list.name
                            editing = .rename(list.name)
                        }
                        Button("Löschen", systemImage: "trash", role: .destructive) { pendingDelete = list }
                    }
                }
            } footer: {
                Text("Jede Liste ist eine eigene Datenbank wie in Cachebox. Antippen öffnet sie; zum Umbenennen "
                     + "oder Löschen nach links wischen oder lange drücken.")
            }
        }
        .overlay {
            if lists.lists.isEmpty {
                ContentUnavailableView("Keine Listen", systemImage: "folder",
                                       description: Text("Lege eine Liste an oder importiere eine GPX-Datei."))
            }
        }
        .navigationTitle("Listen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            ToolbarItem(placement: .topBarLeading) {
                Button("Neue Liste", systemImage: "plus") {
                    name = ""
                    editing = .create
                }
            }
        }
        .alert(editing == .create ? "Neue Liste" : "Liste umbenennen",
               isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } }),
               presenting: editing) { mode in
            TextField("Name", text: $name)
            Button(mode == .create ? "Anlegen" : "Umbenennen") { save(mode) }
            Button("Abbrechen", role: .cancel) {}
        }
        .alert("„\(pendingDelete?.name ?? "")“ löschen?",
               isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
               presenting: pendingDelete) { list in
            Button("Löschen", role: .destructive) {
                Task {
                    do {
                        try await lists.delete(list.name)   // opens another list if it was the open one
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { list in
            Text(list.cacheCount == 0 ? "Die Liste ist leer."
                 : "Die Liste enthält \(Format.count(list.cacheCount, "Cache", "Caches")) mit Notizen und Markierungen. "
                   + "Das lässt sich nicht rückgängig machen.")
        }
        .alert("Fehler", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func row(_ list: CacheListInfo) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                Text(details(list))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if list.name == lists.currentName {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Geöffnet")
            }
        }
        .contentShape(Rectangle())
    }

    /// "123 Caches · 4,5 MB · Import 10.11.2026" (Cachebox: "N Caches X MB last use").
    private func details(_ list: CacheListInfo) -> String {
        var parts = [Format.count(list.cacheCount, "Cache", "Caches"), Format.bytes(list.fileSize)]
        if let date = list.lastImport {
            parts.append("Import " + date.formatted(date: .numeric, time: .omitted))
        }
        return parts.joined(separator: " · ")
    }

    private func save(_ mode: Editing) {
        do {
            switch mode {
            case .create:
                let created = try lists.create(name)
                Task { await state.openList(created) }
            case .rename(let old):
                try lists.rename(old, to: name)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
