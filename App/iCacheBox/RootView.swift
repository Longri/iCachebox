import CacheboxCore
import SwiftUI

/// Shows the welcome page on first launch, afterwards the main tab bar.
struct RootView: View {
    @State private var state = AppState()
    @AppStorage(StorageKey.onboardingCompleted) private var onboardingCompleted = false

    var body: some View {
        Group {
            if onboardingCompleted {
                tabs
            } else {
                WelcomeView { withAnimation { onboardingCompleted = true } }
            }
        }
        .tint(.cachebox)
        .environment(state)
        // GPX/ZIP opened with "Share › iCacheBox" from Files, Mail or Safari: import into the open list
        .onOpenURL { url in
            let fromInbox = url.path.contains("/Inbox/")
            state.lists.importFiles([url], into: state.lists.currentName, removeAfterImport: fromInbox)
            state.tab = .caches
        }
    }

    /// Main tab bar. Replaces the five gesture buttons of Cachebox; their swipe/long-press actions
    /// live as visible controls inside each tab.
    private var tabs: some View {
        TabView(selection: $state.tab) {
            CacheListView()
                .tabItem { Label("Caches", systemImage: "list.bullet") }
                .tag(MainTab.caches)
            CacheDetailView()
                .tabItem { Label("Cache", systemImage: "doc.text") }
                .tag(MainTab.cache)
            ContentView()
                .selectedCacheBar()
                .tabItem { Label("Karte", systemImage: "map") }
                .tag(MainTab.map)
            LogDraftsView()
                .tabItem { Label("Loggen", systemImage: "square.and.pencil") }
                .tag(MainTab.log)
            MoreView()
                .tabItem { Label("Mehr", systemImage: "ellipsis") }
                .tag(MainTab.more)
        }
        .overlay(alignment: .top) {
            ImportStatusCard()
                .animation(.default, value: state.lists.importStatus)
        }
        .task {
            await state.openList(state.lists.currentName)
        }
    }
}

/// Bar above the tab bar showing the selected cache (Cachebox: the `Slider` with the cache info line, shown above
/// every view): type with status marks, name, code, D/T/size and, with a position, distance and direction.
/// Tapping opens the details; the context menu also offers the map.
struct SelectedCacheBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let cache = state.selectedCache {
            Button {
                state.tab = .cache
            } label: {
                HStack(spacing: 10) {
                    CacheTypeIcon(type: cache.type, isFound: cache.isFound, isFavorite: cache.isFavorite,
                                  isArchived: cache.isArchived, isUnavailable: !cache.isAvailable,
                                  isSolved: cache.hasCorrectedCoordinate, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(cache.name)
                            .font(.subheadline)
                            .strikethrough(cache.isArchived)
                            .lineLimit(1)
                        Text("\(cache.code) · \(cache.ratingText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if let here = state.location.coordinate {
                        let bearing = here.bearing(to: cache.coordinate) - (state.location.heading ?? 0)
                        HStack(spacing: 4) {
                            Image(systemName: "location.north.fill")
                                .rotationEffect(.degrees(bearing))
                                .foregroundStyle(.tint)
                            Text(Format.distance(here.distance(to: cache.coordinate)))
                                .font(.caption.monospacedDigit())
                        }
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, 14)
                .padding(.vertical, 5)
                .frame(minHeight: 44)
                .background {
                    // floats like the tab bar, also on grouped (grey) backgrounds
                    Capsule().fill(.regularMaterial).shadow(color: .black.opacity(0.15), radius: 5, y: 1)
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityText(cache))
            .accessibilityHint("Öffnet die Details")
            .contextMenu {
                Button("Details", systemImage: "doc.text") { state.tab = .cache }
                Button("Auf der Karte", systemImage: "map") { state.select(cache, show: .map) }
            }
            .padding(.horizontal)
            .padding(.bottom, 6)
        }
    }

    private func accessibilityText(_ cache: CacheSummary) -> String {
        var text = "Gewählter Cache: \(cache.name), \(cache.code)"
        if let here = state.location.coordinate {
            text += ", Entfernung \(Format.distance(here.distance(to: cache.coordinate)))"
        }
        return text
    }
}

extension View {
    func selectedCacheBar() -> some View {
        safeAreaInset(edge: .bottom) { SelectedCacheBar() }
    }
}

#Preview { RootView() }
