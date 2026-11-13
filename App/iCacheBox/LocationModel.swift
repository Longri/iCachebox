import CacheboxCore
import CoreLocation
import Observation
import UIKit

/// Current position, speed and heading for the map, the info panel and the distances and direction arrows in the
/// cache list (Cachebox `Locator`).
///
/// Asks for "when in use" permission on first start; without permission the list shows no distances and
/// sorts relative to the selected cache instead (as Cachebox does without GPS fix).
@MainActor
@Observable
final class LocationModel: NSObject, CLLocationManagerDelegate {
    private(set) var coordinate: Coordinate?
    /// Accuracy of `coordinate` in metres.
    private(set) var accuracy: Double?
    /// Speed over ground in metres per second, if the last fix had one.
    private(set) var speed: Double?
    /// Height above mean sea level in metres, if the last fix had one (Cachebox `Locator.getAltString`).
    private(set) var altitude: Double?
    /// Heading in degrees (0 = north, clockwise) in which the user looks or moves: the direction of travel from GPS
    /// when moving faster than `compassSpeedLimit` or without a compass, otherwise the compass (Cachebox
    /// `Locator.setHeading`/`getHeading`). The compass heading refers to the top of the screen in its current
    /// orientation.
    private(set) var heading: Double?
    /// `heading` comes from the compass (Cachebox `UseMagneticCompass`: red arrows), not from GPS (cyan arrows).
    private(set) var isCompassHeading = CLLocationManager.headingAvailable()
    private(set) var authorization: CLAuthorizationStatus

    /// Below this speed the compass gives the heading (Cachebox setting `HardwareCompassLevel`, 5 km/h).
    static let compassSpeedLimit = 5.0 / 3.6

    /// Called after every new fix (Cachebox `PositionChangedListeners`), for the approach notification.
    @ObservationIgnored var onPositionChanged: (() -> Void)?

    @ObservationIgnored private let manager = CLLocationManager()
    /// Last heading of each source; −1/nil = none yet.
    @ObservationIgnored private var compassHeading: Double?
    @ObservationIgnored private var course: Double?
    @ObservationIgnored private var isUpdating = false
    /// The approach notification asked for background updates; applied as soon as there is permission.
    @ObservationIgnored private var wantsBackgroundUpdates = false
    @ObservationIgnored private let hasCompass = CLLocationManager.headingAvailable()

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // every fix: the map follows the position in GPS mode and shows the speed (the list ignores moves < 15 m)
        manager.distanceFilter = kCLDistanceFilterNone
        manager.headingFilter = 2
        NotificationCenter.default.addObserver(self, selector: #selector(deviceOrientationChanged),
                                               name: UIDevice.orientationDidChangeNotification, object: nil)
    }

    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            guard !isUpdating else { return }
            isUpdating = true
            manager.startUpdatingLocation()
            if hasCompass {
                UIDevice.current.beginGeneratingDeviceOrientationNotifications()
                deviceOrientationChanged()
                manager.startUpdatingHeading()
            }
        default:
            break
        }
    }

    /// Keeps the position updates running while the app is in the background, so that the approach notification
    /// also comes with the screen locked (`ApproachOptions.worksInBackground`). Needs the background mode
    /// `location` in `iCacheBox-Info.plist`; iOS shows its blue location indicator while this is on and stops the
    /// updates again as soon as the user quits the app.
    func setBackgroundUpdates(_ enabled: Bool) {
        wantsBackgroundUpdates = enabled
        let authorized = manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways
        let value = enabled && authorized
        guard manager.allowsBackgroundLocationUpdates != value else { return }
        manager.allowsBackgroundLocationUpdates = value
        // iOS may pause the updates for good when it thinks the user stopped moving
        manager.pausesLocationUpdatesAutomatically = !value
    }

    /// The compass measures relative to the top of the device; in landscape the top of the screen is a side of
    /// the device. Face up/down and the unsupported upside-down portrait on iPhone keep the last orientation.
    @objc private func deviceOrientationChanged() {
        let device = UIDevice.current
        let orientation: CLDeviceOrientation? = switch device.orientation {
        case .portrait: .portrait
        case .landscapeLeft: .landscapeLeft
        case .landscapeRight: .landscapeRight
        case .portraitUpsideDown where device.userInterfaceIdiom == .pad: .portraitUpsideDown
        default: nil
        }
        if let orientation, manager.headingOrientation != orientation { manager.headingOrientation = orientation }
    }

    /// Cachebox `Locator.setHeading`: GPS direction when it is known and the speed is above the compass limit, or
    /// when there is no compass; else the compass.
    private func updateHeading() {
        let moving = (speed ?? 0) > Self.compassSpeedLimit
        let (value, fromCompass) = if let course, moving || compassHeading == nil {
            (Optional(course), false)
        } else {
            (compassHeading, hasCompass)
        }
        // observers (map, list arrows) only hear about real changes
        if heading != value { heading = value }
        if isCompassHeading != fromCompass { isCompassHeading = fromCompass }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if self.isDenied {
                // access taken away in the settings: the last position is no longer the own position
                self.manager.stopUpdatingLocation()
                self.manager.stopUpdatingHeading()
                self.isUpdating = false
                self.coordinate = nil
                self.accuracy = nil
                self.speed = nil
                self.altitude = nil
                self.course = nil
                self.updateHeading()
            }
            self.start()
            self.setBackgroundUpdates(self.wantsBackgroundUpdates)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        let coordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let accuracy = location.horizontalAccuracy
        let speed = location.speed >= 0 ? location.speed : nil
        let course = location.course >= 0 ? location.course : nil
        let altitude = location.verticalAccuracy > 0 ? location.altitude : nil
        Task { @MainActor in
            if self.coordinate != coordinate { self.coordinate = coordinate }
            if self.accuracy != accuracy { self.accuracy = accuracy }
            if self.speed != speed { self.speed = speed }
            if self.altitude != altitude { self.altitude = altitude }
            self.course = course
            self.updateHeading()
            self.onPositionChanged?()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in
            self.compassHeading = value
            self.updateHeading()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}
}
