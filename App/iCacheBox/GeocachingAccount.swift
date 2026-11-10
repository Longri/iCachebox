import Foundation
import Observation

/// Geocaching.com account (Cachebox: login state in `GroundspeakAPI`, token in `Config.AccessToken`).
///
/// Placeholder: there is no Geocaching API key for iOS yet (see UI-KONZEPT.md, "Login, API und Lizenzen").
/// The real login will use `ASWebAuthenticationSession` with OAuth 2 + PKCE; Cachebox's WebView with
/// token scraping is not ported.
@MainActor
@Observable
final class GeocachingAccount {
    enum Status: Equatable {
        case signedOut
        case signedIn(username: String, premium: Bool)
    }

    private(set) var status: Status = .signedOut

    var isSignedIn: Bool {
        if case .signedIn = status { true } else { false }
    }

    /// Starts the sign-in flow. Always fails until API access is available.
    func signIn() async throws {
        throw AccountError.signInUnavailable
    }

    func signOut() {
        status = .signedOut
    }
}

enum AccountError: LocalizedError {
    case signInUnavailable

    var errorDescription: String? {
        switch self {
        case .signInUnavailable: "Anmeldung noch nicht verfügbar"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .signInUnavailable:
            "Die Anmeldung bei Geocaching.com ist in dieser Testversion noch nicht eingebaut. "
                + "Du kannst die App ohne Konto nutzen."
        }
    }
}
