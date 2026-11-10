import SwiftUI

/// Tab 4: log drafts (Cachebox: `DraftsView` behind main button 4, plus photo, voice note, solver).
struct LogDraftsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Keine Entwürfe", systemImage: "square.and.pencil")
            } description: {
                Text("Log-Entwürfe erscheinen hier, bis sie hochgeladen sind.")
            }
            .navigationTitle("Entwürfe")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // TODO: Entwurf anlegen / hochladen (Geocaching-API: logdrafts)
                    Button("Hochladen", systemImage: "square.and.arrow.up") {}.disabled(true)
                    Button("Neuer Entwurf", systemImage: "plus") {}.disabled(state.selectedCache == nil)
                }
            }
            .selectedCacheBar()
        }
    }
}

/// Tab 5: account, import, maps, settings (Cachebox: main button 5).
struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("Geocaching-Konto", "person.crop.circle")
                }
                Section {
                    row("Import", "square.and.arrow.down")
                    row("Karten und Themes", "map")
                    row("Schnellzugriffe", "rectangle.grid.1x2")
                    row("Einstellungen", "gearshape")
                }
                Section {
                    row("Hilfe", "questionmark.circle")
                    row("Über", "info.circle")
                }
            }
            .navigationTitle("Mehr")
        }
    }

    private func row(_ title: String, _ symbol: String) -> some View {
        NavigationLink {
            ContentUnavailableView(title, systemImage: symbol, description: Text("Noch nicht umgesetzt."))
                .navigationTitle(title)
        } label: {
            Label(title, systemImage: symbol)
        }
    }
}
