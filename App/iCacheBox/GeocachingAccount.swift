import AuthenticationServices
import CacheboxCore
import Foundation
import Observation
import UIKit

/// The Geocaching.com account (Cachebox: login state in `GroundspeakAPI`, token in `Config.AccessToken`).
///
/// The whole OAuth 2.0 flow with PKCE runs in the app; Cachebox's detour over `gc-oauth.longri.de` with its
/// WebView and token scraping is not ported. The protocol itself lives in `CacheboxCore`
/// (`GeocachingAuthenticator`), this class only adds the browser sheet and the state the views show.
///
/// Without a key from Geocaching HQ (`GeocachingKeys.plist`) everything here answers
/// `AccountError.signInUnavailable` - the rest of the app does not care.
@MainActor
@Observable
final class GeocachingAccount {
    enum Status: Equatable {
        case signedOut
        case signedIn(username: String, premium: Bool)
    }

    private(set) var status: Status = .signedOut
    /// Finds, hides, favourite points … of the signed-in user; nil until `GET /v1/users/me` has answered.
    private(set) var user: GeocachingUser?
    /// A sign-in or a refresh is running.
    private(set) var isWorking = false

    private let authenticator: GeocachingAuthenticator?
    private let api: GeocachingAPI?
    /// Kept alive while the browser sheet is up.
    private var session: ASWebAuthenticationSession?
    private let anchor = WebAuthenticationAnchor()

    /// Is there a consumer key at all? False until HQ hands one out for iOS.
    var isConfigured: Bool { authenticator != nil }

    var isSignedIn: Bool {
        if case .signedIn = status { true } else { false }
    }

    /// Which environment the key belongs to - shown in the account view, because a staging token only ever
    /// sees test data.
    var isStaging: Bool {
        authenticator?.credentials.environment == .staging
    }

    init(credentials: GeocachingCredentials? = GeocachingKeys.credentials()) {
        if let credentials {
            let authenticator = GeocachingAuthenticator(credentials: credentials)
            self.authenticator = authenticator
            api = GeocachingAPI(authenticator: authenticator)
        } else {
            authenticator = nil
            api = nil
        }
    }

    // MARK: - Launch

    /// Brings back the sign-in of the last launch: the name is shown at once from `UserDefaults`, the numbers
    /// come from the API afterwards. A network error leaves the user signed in - only a token geocaching.com
    /// refuses signs them out.
    func restore() async {
        guard let authenticator, status == .signedOut else { return }
        guard await authenticator.isSignedIn() else { return }
        if let name = Self.storedUsername {
            status = .signedIn(username: name, premium: Self.storedPremium)
        }
        await refreshUser()
    }

    /// Fetches the user again (name, membership, finds). Called after the sign-in and on every launch.
    func refreshUser() async {
        guard let api else { return }
        do {
            let user = try await api.me()
            apply(user)
        } catch let error as GeocachingAuthError where error == .notSignedIn {
            forget()
        } catch {
            // No network, rate limit, server trouble: the stored sign-in stays as it is.
        }
    }

    // MARK: - Signing in

    /// Shows geocaching.com in an `ASWebAuthenticationSession`, trades the code for tokens and reads the user.
    ///
    /// `ASWebAuthenticationSession` instead of a WebView of our own: Cachebox's WebView would be blocked by
    /// the social logins of the page (Google refuses OAuth in embedded WebViews), and the session keeps the
    /// password out of the app for good.
    func signIn() async throws {
        guard let authenticator else { throw AccountError.signInUnavailable }
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        guard let scheme = authenticator.credentials.callbackScheme else {
            throw AccountError.failed("Die Redirect-URI ist kein App-Schema", recovery:
                "Trage in GeocachingKeys.plist die bei Geocaching HQ registrierte URI ein, z. B. icachebox://oauth.")
        }
        do {
            let authorization = try await authenticator.authorization()
            let callback = try await present(authorization.url, callbackScheme: scheme)
            try await authenticator.completeSignIn(callback: callback, authorization: authorization)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            throw AccountError.cancelled
        } catch let error as GeocachingAuthError {
            throw AccountError(error)
        } catch let error as AccountError {
            throw error
        } catch {
            throw AccountError.failed(error.localizedDescription, recovery: nil)
        }
        await refreshUser()
        // The sign-in worked, but `/v1/users/me` did not answer: still signed in, name follows later.
        if case .signedOut = status {
            status = .signedIn(username: Self.storedUsername ?? "Angemeldet", premium: Self.storedPremium)
        }
    }

    /// Throws the tokens away. geocaching.com itself cannot be told - the API has no revoke endpoint, so the
    /// access stays listed in the user's profile until it expires.
    ///
    /// `async`, so that a sign-in right afterwards cannot overtake the deletion in the keychain.
    func signOut() async {
        user = nil
        status = .signedOut
        Self.storedUsername = nil
        Self.storedPremium = false
        try? await authenticator?.signOut()
    }

    // MARK: - Private

    private func apply(_ user: GeocachingUser) {
        self.user = user
        let name = user.username.isEmpty ? (Self.storedUsername ?? "Angemeldet") : user.username
        status = .signedIn(username: name, premium: user.membership.isPremium)
        Self.storedUsername = name
        Self.storedPremium = user.membership.isPremium
    }

    /// Like `signOut`, but from a place that cannot wait (the token was refused anyway).
    private func forget() {
        user = nil
        status = .signedOut
        Self.storedUsername = nil
        Self.storedPremium = false
        guard let authenticator else { return }
        Task { try? await authenticator.signOut() }
    }

    /// The browser sheet, as an `async` call.
    private func present(_ url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            // `start()` may report a failure and call the handler as well; whoever comes first wins, a second
            // `resume` would crash.
            let answered = Answered()
            let handler: @Sendable (URL?, (any Error)?) -> Void = { callback, error in
                guard answered.first() else { return }
                if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: error ?? AccountError.cancelled)
                }
            }
            let session: ASWebAuthenticationSession
            if #available(iOS 17.4, *) {
                session = ASWebAuthenticationSession(url: url,
                                                     callback: .customScheme(callbackScheme),
                                                     completionHandler: handler)
            } else {
                session = ASWebAuthenticationSession(url: url,
                                                     callbackURLScheme: callbackScheme,
                                                     completionHandler: handler)
            }
            session.presentationContextProvider = anchor
            // Not ephemeral: whoever is already signed in at geocaching.com in Safari does not have to type
            // the password again. Cachebox clears its WebView cookies instead, which forces a fresh login.
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start(), answered.first() {
                continuation.resume(throwing: AccountError.failed("Das Anmeldefenster ließ sich nicht öffnen",
                                                                  recovery: nil))
            }
        }
    }

    /// Name and membership of the last sign-in, so the account shows up without a network call.
    /// The tokens themselves are in the keychain, never here.
    private static var storedUsername: String? {
        get { UserDefaults.standard.string(forKey: StorageKey.geocachingUsername) }
        set { UserDefaults.standard.set(newValue, forKey: StorageKey.geocachingUsername) }
    }

    private static var storedPremium: Bool {
        get { UserDefaults.standard.bool(forKey: StorageKey.geocachingPremium) }
        set { UserDefaults.standard.set(newValue, forKey: StorageKey.geocachingPremium) }
    }
}

/// Lets exactly one of two possible answers through to a continuation.
private final class Answered: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func first() -> Bool {
        lock.withLock {
            if done { return false }
            done = true
            return true
        }
    }
}

/// The window the sign-in sheet is put on.
final class WebAuthenticationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first ?? ASPresentationAnchor()
    }
}

/// What the sign-in reports back to the views.
enum AccountError: LocalizedError, Equatable {
    /// No consumer key in the app - the normal state until Geocaching HQ hands one out for iOS.
    case signInUnavailable
    /// The user closed the sign-in window; nothing to report.
    case cancelled
    case failed(String, recovery: String?)

    /// Keeps the text of the protocol error, so that the user sees what geocaching.com said.
    init(_ error: GeocachingAuthError) {
        if case .notConfigured = error {
            self = .signInUnavailable
        } else {
            self = .failed(error.errorDescription ?? "Die Anmeldung ist fehlgeschlagen",
                           recovery: error.recoverySuggestion)
        }
    }

    var errorDescription: String? {
        switch self {
        case .signInUnavailable: "Anmeldung noch nicht verfügbar"
        case .cancelled: "Anmeldung abgebrochen"
        case .failed(let message, _): message
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .signInUnavailable:
            "Für iOS gibt es noch keinen Schlüssel von Geocaching HQ. Sobald er da ist, trägst du ihn in "
                + "GeocachingKeys.plist ein – die Anmeldung selbst ist fertig eingebaut. "
                + "Du kannst die App ohne Konto nutzen."
        case .cancelled:
            nil
        case .failed(_, let recovery):
            recovery
        }
    }
}
