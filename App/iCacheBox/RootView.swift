import CacheboxCore
import SwiftUI

/// Shows the welcome page on first launch, afterwards the views with the five main buttons below them.
struct RootView: View {
    @State private var state = AppState()
    @AppStorage(StorageKey.onboardingCompleted) private var onboardingCompleted = false

    var body: some View {
        Group {
            if onboardingCompleted {
                MainScreen()
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
            state.show(.cacheList)
        }
    }
}

/// The shown view above the row of main buttons (Cachebox `CB_TabView`). Each button's views are created when first
/// shown and then kept, like the tabs of a tab bar, so that the map keeps its place and the list its scroll position.
private struct MainScreen: View {
    @Environment(AppState.self) private var state
    @Environment(\.scenePhase) private var scenePhase
    /// Buttons whose views exist.
    @State private var created: Set<MainButton> = []
    /// The keyboard is up: the buttons hide behind it, as a tab bar does.
    @State private var keyboardShown = false

    var body: some View {
        @Bindable var details = state.details
        @Bindable var app = state
        VStack(spacing: 0) {
            // the selected cache and the quick buttons over every view (Cachebox `Slider`)
            CacheboxSlider {
                ZStack {
                    ForEach(MainButton.allCases) { button in
                        if created.contains(button) || state.view.button == button {
                            let isShown = state.view.button == button
                            page(button)
                                .opacity(isShown ? 1 : 0)
                                .allowsHitTesting(isShown)
                                .accessibilityHidden(!isShown)
                        }
                    }
                }
                .overlay(alignment: .top) {
                    ImportStatusCard()
                        .animation(.default, value: state.lists.importStatus)
                }
            }
            if !keyboardShown {
                MainButtonBar()
                    .transition(.move(edge: .bottom))
            }
        }
        .onChange(of: state.view.button, initial: true) { created.insert(state.view.button) }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            // a hardware keyboard only shows its small bar
            let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            if (frame?.height ?? 0) > 120 { withAnimation(.easeOut(duration: 0.2)) { keyboardShown = true } }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { keyboardShown = false }
        }
        .task {
            await state.openList(state.lists.currentName)
        }
        // details of the selected cache for the cache views, the compass and the menus; again after a change of the
        // selection or its flags and after an import
        .task(id: DetailsKey(cache: state.selectedCache, list: state.lists.currentName,
                             imported: state.lists.current?.lastImport, waypoints: state.waypointRevision)) {
            let list = state.lists.currentName.map { state.lists.store.url(of: $0) }
            await state.details.load(code: state.selectedCache?.code, list: list)
        }
        // dialogs of the cache button, which can be opened from every view
        .alert("Hinweis", isPresented: $details.showHint) {
            Button("Schließen", role: .cancel) {}
        } message: {
            Text(state.selectedDetails?.cache.hint ?? "")
        }
        .sheet(isPresented: $details.editingNote) {
            if let cache = state.selectedDetails?.cache {
                NoteEditor(code: cache.code, text: cache.note) { note in
                    state.details.noteChanged(note, code: cache.code)
                }
            }
        }
        // waypoint editor of the waypoint view and the map (Cachebox `EditWaypoint`)
        .sheet(item: $app.waypointEditor) { request in
            WaypointEditor(request: request) { state.saveWaypoint($0) }
        }
        .alert("Wegpunkt löschen", isPresented: Binding(get: { state.waypointToDelete != nil },
                                                        set: { if !$0 { state.waypointToDelete = nil } }),
               presenting: state.waypointToDelete) { waypoint in
            Button("Löschen", role: .destructive) { state.deleteWaypoint(waypoint) }
            Button("Abbrechen", role: .cancel) {}
        } message: { waypoint in
            Text("Willst du diesen Wegpunkt wirklich löschen?\n\n\(waypoint.title.isEmpty ? waypoint.code : waypoint.title)")
        }
        .alert("Wegpunkt", isPresented: Binding(get: { state.waypointError != nil },
                                                set: { if !$0 { state.waypointError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.waypointError ?? "")
        }
        .sheet(isPresented: $app.showMapDownload) {
            NavigationStack {
                MapDownloadView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Fertig") { state.showMapDownload = false }
                        }
                    }
            }
            .environment(\.colorScheme, .light)   // the page is in the Cachebox day skin
        }
        .onChange(of: scenePhase) {
            // iOS switches the torch off in the background
            if scenePhase == .active { state.isTorchOn = Torch.isOn }
        }
    }

    @ViewBuilder
    private func page(_ button: MainButton) -> some View {
        switch button {
        case .caches: CacheListView()
        case .cache: CacheDetailView()
        case .navigation: NavigationPage()
        case .tools: LogDraftsView()
        case .misc: MoreView()
        }
    }

    private struct DetailsKey: Equatable {
        let cache: CacheSummary?
        let list: String?
        let imported: Date?
        let waypoints: Int
    }
}

/// Map and compass, the views of the navigation button. The map stays under the compass, so that it does not load
/// again when it comes back.
private struct NavigationPage: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let compass = state.view == .compass
        ZStack {
            ContentView()
                .opacity(compass ? 0 : 1)
                .allowsHitTesting(!compass)
                .accessibilityHidden(compass)
            if compass {
                CompassView()
            }
        }
    }
}

#Preview { RootView() }
