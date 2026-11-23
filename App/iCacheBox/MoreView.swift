import SwiftUI

/// Main button 5: account, import, maps, settings (Cachebox: main button 5). Drawn like the cache list in the
/// Cachebox day skin, also in dark mode: green background, the entries as boxes in white and light grey in turn,
/// green lines between the groups.
struct MoreView: View {
    @Environment(AppState.self) private var state
    @AppStorage(StorageKey.onboardingCompleted) private var onboardingCompleted = true

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    AccountView()
                } label: {
                    LabeledContent {
                        Text(accountStatus)
                    } label: {
                        Label("Geocaching-Konto", systemImage: "person.crop.circle")
                    }
                }
                .cacheboxListRow(index: 0)
                CacheboxDivider().cacheboxListDivider()
                NavigationLink {
                    ImportView()
                } label: {
                    Label("GPX importieren", systemImage: "square.and.arrow.down")
                }
                .cacheboxListRow(index: 1)
                NavigationLink {
                    MapDownloadView()
                } label: {
                    Label("Karten und Themes", systemImage: "map")
                }
                .cacheboxListRow(index: 2)
                row("Schnellzugriffe", "rectangle.grid.1x2", index: 3)
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Einstellungen", systemImage: "gearshape")
                }
                .cacheboxListRow(index: 4)
                CacheboxDivider().cacheboxListDivider()
                row("Hilfe", "questionmark.circle", index: 5)
                Button {
                    withAnimation { onboardingCompleted = false }
                } label: {
                    Label("Willkommensseite zeigen", systemImage: "hand.wave")
                }
                .cacheboxListRow(index: 6)
                NavigationLink {
                    AboutView()
                } label: {
                    LabeledContent {
                        Text(AppVersion.version)
                            .monospacedDigit()
                    } label: {
                        Label("Über", systemImage: "info.circle")
                    }
                }
                .cacheboxListRow(index: 7)
            }
            .cacheboxPage()
            .navigationTitle("Mehr")
        }
        .environment(\.colorScheme, .light)   // also the navigation bar and the pages behind the entries
    }

    private var accountStatus: String {
        switch state.account.status {
        case .signedOut: "Nicht angemeldet"
        case .signedIn(let username, _): username
        }
    }

    private func row(_ title: String, _ symbol: String, index: Int) -> some View {
        NavigationLink {
            ContentUnavailableView(title, systemImage: symbol, description: Text("Noch nicht umgesetzt."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.cacheboxBackground)
                .navigationTitle(title)
        } label: {
            Label(title, systemImage: symbol)
        }
        .cacheboxListRow(index: index)
    }
}
