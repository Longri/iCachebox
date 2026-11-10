import SwiftUI

/// Tab 1: cache list (Cachebox: `CacheListView`).
struct CacheListView: View {
    @Environment(AppState.self) private var state
    @State private var search = ""

    private var caches: [Cache] {
        guard !search.isEmpty else { return state.caches }
        return state.caches.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List(caches) { cache in
                Button { state.select(cache) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: cache.kind.symbol)
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 28)
                        VStack(alignment: .leading) {
                            Text(cache.name).foregroundStyle(Color.primary)
                            Text("\(cache.id) · \(cache.ratingText)")
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                        }
                        Spacer()
                        if cache == state.selectedCache {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                .swipeActions(edge: .leading) {
                    Button("Karte", systemImage: "map") { state.select(cache, show: .map) }
                }
            }
            .overlay {
                if caches.isEmpty { ContentUnavailableView.search(text: search) }
            }
            .navigationTitle("Caches")
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "GC-Code oder Name")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Mehr", systemImage: "ellipsis.circle") {
                        // TODO: Filter, Import, Trackables, Parken, Teilen (Cachebox: Kontextmenü Button 1)
                        Button("Filter", systemImage: "line.3.horizontal.decrease.circle") {}.disabled(true)
                        Button("Import", systemImage: "square.and.arrow.down") {}.disabled(true)
                        Button("Trackables", systemImage: "tag") {}.disabled(true)
                    }
                }
            }
            .selectedCacheBar()
        }
    }
}
