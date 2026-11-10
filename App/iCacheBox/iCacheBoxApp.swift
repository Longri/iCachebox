import SwiftUI
import UIKit

@main
struct iCacheBoxApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// The system relaunched the app because map downloads of the background session finished.
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        MapLibrary.shared.backgroundEventsCompletion = completionHandler
    }
}
