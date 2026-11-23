import CacheboxCore
import Foundation

/// "Mein Parkplatz": where the car stands (Cachebox `ParkingMenu` with the global settings `ParkingLatitude` and
/// `ParkingLongitude`, 0/0 = none).
///
/// Deviation: Cachebox builds a pseudo cache `CBPark` of the type `MyParking` from those two settings, puts it at the
/// top of the cache list (`CacheListChangedListeners`) and selects it like any other cache. Here a cache always comes
/// from the list database, so the parking place is a navigation target of its own (`AppState.targetsParking`) with
/// its own marker on the map; the GC code and the icon of the Cachebox pseudo cache are kept.
@MainActor
@Observable
final class ParkingPlace {
    /// GC code of the Cachebox pseudo cache; it also tells the target apart for the approach notification.
    nonisolated static let code = "CBPark"
    /// Cachebox names it "My Parking area".
    nonisolated static let name = "Mein Parkplatz"
    /// Cachebox sprite `bigMyParking` of the `GeoCacheType.MyParking`.
    nonisolated static let iconName = "bigMyParking"

    private enum Keys {
        static let latitude = "parking.latitude"
        static let longitude = "parking.longitude"
    }

    /// Where the car stands, or nil while no parking place is set (Cachebox: 0/0).
    private(set) var coordinate: Coordinate?

    var isSet: Bool { coordinate != nil }

    init() {
        let defaults = UserDefaults.standard
        let saved = Coordinate(latitude: defaults.double(forKey: Keys.latitude),
                               longitude: defaults.double(forKey: Keys.longitude))
        coordinate = saved.isValid ? saved : nil
    }

    /// Cachebox `ParkingMenu.btnSetGPS`: the parking place is where the device stands.
    func set(_ coordinate: Coordinate) {
        guard coordinate.isValid else { return }
        self.coordinate = coordinate
        save()
    }

    /// Cachebox `ParkingMenu.btnDeleteP`: forgets the parking place (back to 0/0).
    func clear() {
        coordinate = nil
        save()
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(coordinate?.latitude ?? 0, forKey: Keys.latitude)
        defaults.set(coordinate?.longitude ?? 0, forKey: Keys.longitude)
    }
}
