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

/// Bar above the tab bar showing the selected cache (Cachebox: cache info line below the quick buttons).
struct SelectedCacheBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let cache = state.selectedCache {
            Button {
                state.tab = .cache
            } label: {
                HStack {
                    Image(systemName: cache.type.symbol)
                        .foregroundStyle(cache.type.color)
                    Text(cache.name).lineLimit(1)
                    Spacer()
                    Text(cache.code).foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.bottom, 6)
            .accessibilityLabel("Gewählter Cache: \(cache.name)")
        }
    }
}

extension View {
    func selectedCacheBar() -> some View {
        safeAreaInset(edge: .bottom) { SelectedCacheBar() }
    }
}

#Preview { RootView() }
