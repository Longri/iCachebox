import CoreLocation
import SwiftUI

/// The five main areas, matching the five main buttons of Cachebox (`ViewManager`).
enum MainTab: Hashable {
    case caches, cache, map, log, more
}

/// Placeholder cache record for the UI scaffold. Will be replaced by the database model.
struct Cache: Identifiable, Hashable {
    enum Kind: String {
        case traditional, mystery, multi

        var symbol: String {
            switch self {
            case .traditional: "shippingbox"
            case .mystery: "questionmark.square"
            case .multi: "square.on.square"
            }
        }
    }

    let id: String          // GC code
    let name: String
    let kind: Kind
    let difficulty: Double
    let terrain: Double
    let size: String
    let latitude: Double
    let longitude: Double
    let description: String
    let hint: String

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var ratingText: String { String(format: "D %.1f · T %.1f · %@", difficulty, terrain, size) }

    /// Sample data so that the scaffold shows something; not real geocaches.
    static let samples: [Cache] = [
        Cache(id: "GC0TEST1", name: "Beispiel am Marktplatz", kind: .traditional, difficulty: 1.5, terrain: 1,
              size: "Small", latitude: 53.0758, longitude: 8.8072,
              description: "Platzhalter-Beschreibung. Hier erscheint später die Cachebeschreibung aus der Datenbank.",
              hint: "Unter der Bank"),
        Cache(id: "GC0TEST2", name: "Beispiel-Rätsel", kind: .mystery, difficulty: 2.5, terrain: 2,
              size: "Micro", latitude: 53.0793, longitude: 8.8017,
              description: "Platzhalter-Beschreibung für einen Rätselcache.", hint: "Magnetisch"),
        Cache(id: "GC0TEST3", name: "Beispiel-Runde", kind: .multi, difficulty: 2, terrain: 2.5,
              size: "Regular", latitude: 53.0701, longitude: 8.8150,
              description: "Platzhalter-Beschreibung für einen Multi.", hint: ""),
    ]
}

/// App-wide UI state: active tab and the selected cache (Cachebox: `GlobalCore.getSelectedCache`).
@MainActor
@Observable
final class AppState {
    var tab: MainTab = .caches
    var caches: [Cache] = Cache.samples
    var selectedCache: Cache?
    let account = GeocachingAccount()
    let mapLibrary = MapLibrary.shared

    func select(_ cache: Cache, show tab: MainTab = .cache) {
        selectedCache = cache
        self.tab = tab
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
