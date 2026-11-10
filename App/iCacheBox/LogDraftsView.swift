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
