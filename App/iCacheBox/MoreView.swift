import SwiftUI

/// Tab 5: account, import, maps, settings (Cachebox: main button 5).
struct MoreView: View {
    @Environment(AppState.self) private var state
    @AppStorage(StorageKey.onboardingCompleted) private var onboardingCompleted = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        AccountView()
                    } label: {
                        LabeledContent {
                            Text(accountStatus)
                        } label: {
                            Label("Geocaching-Konto", systemImage: "person.crop.circle")
                        }
                    }
                }
                Section {
                    row("Import", "square.and.arrow.down")
                    NavigationLink {
                        MapDownloadView()
                    } label: {
                        Label("Karten und Themes", systemImage: "map")
                    }
                    row("Schnellzugriffe", "rectangle.grid.1x2")
                    row("Einstellungen", "gearshape")
                }
                Section {
                    row("Hilfe", "questionmark.circle")
                    Button {
                        withAnimation { onboardingCompleted = false }
                    } label: {
                        Label("Willkommensseite zeigen", systemImage: "hand.wave")
                    }
                    row("Über", "info.circle")
                }
            }
            .navigationTitle("Mehr")
        }
    }

    private var accountStatus: String {
        switch state.account.status {
        case .signedOut: "Nicht angemeldet"
        case .signedIn(let username, _): username
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
