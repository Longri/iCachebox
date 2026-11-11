import CacheboxCore
import SwiftUI

/// The five main areas, matching the five main buttons of Cachebox (`ViewManager`).
enum MainTab: Hashable {
    case caches, cache, map, log, more
}

/// Request to center the map on a position. Every request has its own `id`, so showing the same cache again
/// re-centers a map the user has moved meanwhile.
struct MapFocus: Equatable {
    let coordinate: Coordinate
    let id = UUID()
}

/// App-wide UI state: active tab and the selected cache (Cachebox: `GlobalCore.getSelectedCache`).
@MainActor
@Observable
final class AppState {
    var tab: MainTab = .caches
    /// The cache selected in the list; kept per cache list and selected again when the list is opened.
    private(set) var selectedCache: CacheSummary?
    /// Where the map should go: set when the selection changes and by "Auf der Karte" (Cachebox `MapView`
    /// centers on a newly selected cache, too).
    private(set) var mapFocus: MapFocus?
    let account = GeocachingAccount()
    let mapLibrary = MapLibrary.shared
    let lists = CacheListModel()
    let location = LocationModel()

    init() {
        // whenever a list is (re)opened, also after an import, its remembered cache becomes the selection
        lists.onOpen = { [weak self] in self?.restoreSelection() }
    }

    /// Selects a cache and switches to `tab`; with `.map` the map centers on the cache.
    func select(_ cache: CacheSummary, show tab: MainTab = .cache) {
        if cache.code != selectedCache?.code || tab == .map { mapFocus = MapFocus(coordinate: cache.coordinate) }
        selectedCache = cache
        lists.rememberSelection(cache.code)
        self.tab = tab
    }

    /// Opens a cache list; its last selected cache is selected again (Cachebox: `ShowSelectDB`).
    func openList(_ name: String?) async {
        await lists.open(name)
    }

    /// Takes the selection from the loaded list: the remembered cache, or none.
    func restoreSelection() {
        let code = lists.lastSelectedCode()
        let cache = lists.caches.first { $0.code == code }
        if let cache, cache.code != selectedCache?.code { mapFocus = MapFocus(coordinate: cache.coordinate) }
        selectedCache = cache
    }

    /// Updates the selected cache after its flags changed in the list.
    func refreshSelection() {
        guard let code = selectedCache?.code else { return }
        selectedCache = lists.caches.first { $0.code == code }
    }
}

/// `UserDefaults` keys used with `@AppStorage`.
enum StorageKey {
    /// The welcome page was finished (signed in or started without an account).
    static let onboardingCompleted = "onboardingCompleted"
}

extension Color {
    /// Cachebox green, used as the app tint. Light: 5.2:1 against white (also white text on green).
    /// Dark: lighter, 4.5:1 on grouped list cells (#1C1C1E) and 5.6:1 on black; white text on it is ~3.8:1,
    /// the same trade-off as the system tint colors in dark mode.
    static let cachebox = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.30, green: 0.58, blue: 0.18, alpha: 1)
            : UIColor(red: 0.24, green: 0.48, blue: 0.13, alpha: 1)
    })
}
