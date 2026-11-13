import Foundation

/// How much the app offers (Mehr › Einstellungen › Funktionsumfang). Cachebox knows two of these as hidden
/// switches (`SettingsShowExpert`, `SettingsShowAll`), which decide what its settings dialog lists
/// (`ManageSettings`: `SettingModus.NORMAL` always, `EXPERT` only for experts). Here the setting is visible and
/// decides what the menus offer, so that a beginner is not met with everything at once.
///
/// Deviation from Cachebox: there it hides settings, here it hides functions; "Entwickler" (`SettingModus.DEVELOPER`)
/// has no counterpart.
enum FeatureLevel: Int, CaseIterable, Identifiable, Comparable, Codable {
    /// Everything needed to find a cache.
    case standard
    /// … and what helps with a multi or a mystery: projection, measuring, themes, map rotation.
    case advanced
    /// Everything, including what is rarely needed or still being built.
    case expert

    var id: Self { self }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .advanced: "Erweitert"
        case .expert: "Expert"
        }
    }

    var summary: String {
        switch self {
        case .standard: "Nur die Funktionen, die man zum Suchen braucht."
        case .advanced: "Dazu Projektion, Messen vom GPS, Themes und das Drehen der Karte."
        case .expert: "Alles, auch selten Gebrauchtes und noch nicht Gebautes."
        }
    }

    private static let key = "settings.featureLevel"

    /// The chosen level, Standard on the first launch.
    static var saved: FeatureLevel {
        FeatureLevel(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .standard
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.key)
    }

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}
