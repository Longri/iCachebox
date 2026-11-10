import SwiftUI

/// Tab 2: details of the selected cache (Cachebox: description, waypoints, logs, spoiler views
/// behind main button 2). The segmented control replaces the swipe gestures on that button.
struct CacheDetailView: View {
    enum Section: String, CaseIterable, Identifiable {
        case description = "Beschr.",waypoints = "Wegpunkte", logs = "Logs", spoiler = "Spoiler"
        var id: Self { self }
    }

    @Environment(AppState.self) private var state
    @State private var section = Section.description
    @State private var showHint = false

    var body: some View {
        NavigationStack {
            Group {
                if let cache = state.selectedCache {
                    content(cache)
                } else {
                    ContentUnavailableView {
                        Label("Kein Cache gewählt", systemImage: "doc.text")
                    } description: {
                        Text("Wähle einen Cache in der Liste oder auf der Karte.")
                    } actions: {
                        Button("Zur Cacheliste") { state.tab = .caches }
                    }
                }
            }
            .navigationTitle(state.selectedCache?.name ?? "Cache")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func content(_ cache: Cache) -> some View {
        VStack(spacing: 0) {
            Picker("Ansicht", selection: $section) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()

            switch section {
            case .description:
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(cache.id) · \(cache.ratingText)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(cache.description)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }
            case .waypoints:
                placeholder("Wegpunkte", "mappin.and.ellipse")
            case .logs:
                placeholder("Logs", "text.bubble")
            case .spoiler:
                placeholder("Spoiler", "photo")
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Hinweis", systemImage: "lightbulb") { showHint = true }
                    .disabled(cache.hint.isEmpty)
                Menu("Aktionen", systemImage: "ellipsis.circle") {
                    Button("Auf Karte zeigen", systemImage: "map") { state.tab = .map }
                    // TODO: Aktualisieren, Favorit, Beobachtungsliste, Notizen, Solver, Bearbeiten, Löschen
                    Button("Aktualisieren", systemImage: "arrow.clockwise") {}.disabled(true)
                    Button("Notizen", systemImage: "note.text") {}.disabled(true)
                    Button("Solver", systemImage: "function") {}.disabled(true)
                }
            }
        }
        .alert("Hinweis", isPresented: $showHint) {
            Button("Schließen", role: .cancel) {}
        } message: {
            Text(cache.hint)
        }
    }

    private func placeholder(_ title: String, _ symbol: String) -> some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text("Noch nicht umgesetzt."))
    }
}
