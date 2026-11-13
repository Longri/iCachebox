import CacheboxCore
import SwiftUI
import UIKit
import UserNotifications

// Notification when the selected cache comes closer than a set distance, like Cachebox
// (`GlobalLocationReceiver.positionChanged` plays `Approach.ogg` once per selected cache, setting
// `SoundApproachDistance`, default 50 m; `switchViewApproach` additionally shows the compass).
//
// On iOS this is a local notification (banner, sound, vibration) instead of a sound played by the app, so that it
// also reaches the user while the screen is off. iOS stops position updates of a backgrounded app, so watching with
// the screen locked needs the background mode `location` (`UIBackgroundModes` in `iCacheBox-Info.plist`) — that is
// off by default here and is switched on with the setting "Auch bei gesperrtem Bildschirm"; while it is on, iOS
// shows its blue location indicator.
//
// Not taken over: the sound files of Cachebox (GPL assets) and the volume settings — the notification uses the
// system sound. The target is the chosen waypoint of the selected cache, else the cache itself
// (`AppState.target`, Cachebox `GlobalCore.getSelectedCoordinate`).

/// Settings of the approach notification, kept in `UserDefaults` (Cachebox `SoundApproachDistance`,
/// `switchViewApproach`).
@MainActor
@Observable
final class ApproachOptions {
    /// The distances to choose from (Cachebox `approachDistanceArray`); 0 switches the notification off.
    static let distances = [0, 2, 10, 25, 50, 100, 200, 500, 1000]

    /// Notify below this distance in metres, 0 = off (Cachebox default 50 m).
    var distance: Int {
        didSet { UserDefaults.standard.set(distance, forKey: "approach.distance") }
    }
    /// Keep watching the position while the app is in the background or the screen is locked. Not in Cachebox,
    /// which runs as an Android service; here it costs the blue location indicator and battery, so it is off.
    var worksInBackground: Bool {
        didSet { UserDefaults.standard.set(worksInBackground, forKey: "approach.background") }
    }
    /// Cachebox `switchViewApproach` (default off): show the compass when the cache is near.
    var switchesToCompass: Bool {
        didSet { UserDefaults.standard.set(switchesToCompass, forKey: "approach.switchToCompass") }
    }

    var isOn: Bool { distance > 0 }

    init() {
        let defaults = UserDefaults.standard
        distance = defaults.object(forKey: "approach.distance") as? Int ?? 50
        worksInBackground = defaults.bool(forKey: "approach.background")
        switchesToCompass = defaults.bool(forKey: "approach.switchToCompass")
    }
}

/// Watches the distance to the selected cache and notifies once per approach (Cachebox `approachSoundCompleted`).
@MainActor
@Observable
final class ApproachNotifier: NSObject, UNUserNotificationCenterDelegate {
    let options = ApproachOptions()
    /// Permission for the local notification; without it the app can only vibrate while it runs.
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    /// Metres one has to move out of the circle again before the next approach notifies. Cachebox only resets on a
    /// new selection (`resetApproach`); here walking away and coming back notifies again.
    private static let hysteresis = 20.0

    /// Cachebox `approachSoundCompleted`: true while nothing more is to be announced for the selected cache.
    @ObservationIgnored private var hasNotified = true
    @ObservationIgnored private var lastCode: String?
    /// The permission is asked for when a cache is really being watched, not at the first launch.
    @ObservationIgnored private var hasAsked = false

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshAuthorization() }
    }

    /// Asks for the notification permission when the user switches the notification on.
    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        await refreshAuthorization()
    }

    func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Notifications are switched off for the app in the system settings: only vibration is left.
    var isDenied: Bool { authorization == .denied }

    /// Called after every fix and after a change of the selection. Returns true when it has just notified, so that
    /// the caller can switch to the compass (Cachebox `switchViewApproach`).
    @discardableResult
    func update(target: NavigationTarget?, here: Coordinate?) -> Bool {
        guard options.isOn, let target, let here else {
            // without a target, a position or the notification there is nothing to announce (Cachebox `resetApproach`)
            lastCode = target?.id
            hasNotified = true
            return false
        }
        if !hasAsked {
            hasAsked = true
            Task { await requestAuthorization() }
        }
        let distance = here.distance(to: target.coordinate)
        let threshold = Double(options.distance)
        if target.id != lastCode {
            lastCode = target.id
            // Cachebox `resetApproach`: choosing a target one is already standing at stays quiet
            hasNotified = distance < threshold
            return false
        }
        guard !hasNotified else {
            if distance > threshold + Self.hysteresis { hasNotified = false }
            return false
        }
        guard distance < threshold else { return false }
        hasNotified = true
        notify(target, distance: distance)
        return true
    }

    /// Forgets what was announced, e.g. after the coordinates of the cache changed.
    func reset() {
        lastCode = nil
        hasNotified = true
    }

    private func notify(_ target: NavigationTarget, distance: Double) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        guard !isDenied else { return }
        let content = UNMutableNotificationContent()
        content.title = target.isWaypoint ? "Wegpunkt in der Nähe" : "Cache in der Nähe"
        content.body = "\(target.name) (\(target.code)) – noch \(MapFormat.distance(distance))"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "approach." + target.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Show the banner and play the sound while the app itself is in front, too.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
