import CacheboxCore
import CoreLocation
import Observation

/// Current position and compass heading for distances and direction arrows in the cache list.
///
/// Asks for "when in use" permission on first start; without permission the list shows no distances and
/// sorts relative to the selected cache instead (as Cachebox does without GPS fix).
@MainActor
@Observable
final class LocationModel: NSObject, CLLocationManagerDelegate {
    private(set) var coordinate: Coordinate?
    /// Accuracy of `coordinate` in metres.
    private(set) var accuracy: Double?
    /// Device heading in degrees (0 = north), if the device has a compass.
    private(set) var heading: Double?
    private(set) var authorization: CLAuthorizationStatus

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
        manager.headingFilter = 5
    }

    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        default:
            break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            self.start()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        let coordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let accuracy = location.horizontalAccuracy
        Task { @MainActor in
            self.coordinate = coordinate
            self.accuracy = accuracy
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in self.heading = value }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}
}
