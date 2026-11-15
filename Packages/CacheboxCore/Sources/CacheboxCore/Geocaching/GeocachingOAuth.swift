import CryptoKit
import Foundation

// Sign-in at geocaching.com for the Geocaching API (api.groundspeak.com).
//
// Cachebox for Android never did this itself: it opened a WebView on the PHP page
// `gc-oauth.longri.de/index.php?Version=ACB`, which ran the whole OAuth dance on the server and printed the
// tokens into the HTML, which `GcApiLogin.MyJavaScriptInterface` then scraped out again. That detour exists
// here no more - the flow runs in the app.
//
// The old PHP page used OAuth 1.0a (`OAuth/mobileoauth.ashx`, HMAC-SHA1 signatures). Groundspeak switched the
// API off on 1 April 2024; the current API uses the OAuth 2.0 authorization code flow with PKCE (RFC 7636),
// which is what this file implements. The Android app's newer PHP page does the same server side - its WebView
// waits for `code=` and `state=`.

/// The hosts of one Geocaching API environment (api.groundspeak.com documentation, "Authorization").
public struct GeocachingEnvironment: Sendable, Equatable, Codable {
    /// Where the user is sent to log in and grant access (`response_type=code`).
    public var authorizationURL: URL
    /// Where the authorization code is exchanged for tokens and where tokens are refreshed.
    public var tokenURL: URL
    /// Base of the REST API, e.g. `https://api.groundspeak.com/v1/users/me`.
    public var apiBaseURL: URL

    public init(authorizationURL: URL, tokenURL: URL, apiBaseURL: URL) {
        self.authorizationURL = authorizationURL
        self.tokenURL = tokenURL
        self.apiBaseURL = apiBaseURL
    }

    /// Live data. A live token is only handed out after Geocaching HQ has reviewed the app.
    public static let production = GeocachingEnvironment(
        authorizationURL: URL(string: "https://www.geocaching.com/oauth/authorize.aspx")!,
        tokenURL: URL(string: "https://oauth.geocaching.com/token")!,
        apiBaseURL: URL(string: "https://api.groundspeak.com")!)

    /// Test data, reachable with the test token every partner gets first.
    public static let staging = GeocachingEnvironment(
        authorizationURL: URL(string: "https://staging.geocaching.com/oauth/authorize.aspx")!,
        tokenURL: URL(string: "https://oauth-staging.geocaching.com/token")!,
        apiBaseURL: URL(string: "https://staging.api.groundspeak.com")!)

    /// `production` or `staging` by name, as written in `GeocachingKeys.plist`.
    public static func named(_ name: String) -> GeocachingEnvironment? {
        switch name.lowercased() {
        case "production", "produktion", "live", "prod": production
        case "staging", "test", "qa": staging
        default: nil
        }
    }
}

/// Consumer key, consumer secret and redirect URI of this app, as registered with Geocaching HQ.
///
/// The redirect URI has to match the registered one exactly; HQ allows an `https` URL or "a valid native app
/// custom protocol", so `icachebox://oauth` is fine once it is registered. The keys do not belong into the
/// repository - the app reads them from `GeocachingKeys.plist` (see `GeocachingKeys.swift`).
public struct GeocachingCredentials: Sendable, Equatable {
    public var clientID: String
    /// The API documentation marks the secret as required even for the code exchange. An empty secret is left
    /// out of the request, which is what a public client without a secret would send.
    public var clientSecret: String
    public var redirectURI: String
    public var environment: GeocachingEnvironment
    /// The API knows one scope only: `*`.
    public var scope: String

    public init(clientID: String,
                clientSecret: String = "",
                redirectURI: String,
                environment: GeocachingEnvironment = .production,
                scope: String = "*") {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        self.environment = environment
        self.scope = scope
    }

    /// The URL scheme of `redirectURI`, needed by `ASWebAuthenticationSession`; nil for an `https` redirect.
    public var callbackScheme: String? {
        guard let scheme = URLComponents(string: redirectURI)?.scheme?.lowercased(),
              scheme != "http", scheme != "https" else { return nil }
        return scheme
    }
}

/// Proof Key for Code Exchange (RFC 7636): a secret the app keeps until the code is redeemed, so that an
/// intercepted authorization code is useless to anybody else. The Geocaching API requires it.
public struct PKCECode: Sendable, Equatable {
    /// 43 to 128 characters of `[A-Z] [a-z] [0-9] - . _ ~` (RFC 7636 §4.1).
    public let verifier: String
    /// The only transformation this app offers. `plain` would be allowed as well, but there is no reason for it.
    public static let method = "S256"

    /// A fresh verifier from 32 random bytes (43 characters once base64url-encoded).
    public init() {
        self.init(verifier: GeocachingOAuth.randomURLSafeString(byteCount: 32))
    }

    public init(verifier: String) {
        self.verifier = verifier
    }

    /// base64url(SHA256(verifier)), without padding (RFC 7636 §4.2).
    public var challenge: String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return GeocachingOAuth.base64URL(Data(digest))
    }

    /// Whether the verifier keeps to length and character set of RFC 7636 §4.1.
    public var isWellFormed: Bool {
        guard (43...128).contains(verifier.count) else { return false }
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return verifier.allSatisfy { allowed.contains($0) }
    }
}

/// One started sign-in: the page to show plus the two secrets needed to finish it.
public struct GeocachingAuthorization: Sendable, Equatable {
    /// The page to open in `ASWebAuthenticationSession`.
    public let url: URL
    /// Carried through the redirect unchanged; guards against a foisted callback (XSRF).
    public let state: String
    public let pkce: PKCECode
}

/// Everything that can go wrong while signing in. The texts are shown to the user, so they are German.
public enum GeocachingAuthError: Error, LocalizedError, Equatable {
    /// No consumer key in the app - see `GeocachingKeys.plist`.
    case notConfigured
    /// The redirect URI or the authorization URL cannot be turned into a URL.
    case invalidConfiguration(String)
    /// The callback carried no code and no error.
    case invalidCallback(String)
    /// The `state` of the callback is not ours.
    case stateMismatch
    /// The user said no, or geocaching.com refused (`error=...` in the callback).
    case authorizationDenied(String)
    /// The token endpoint answered with an error.
    case tokenEndpoint(status: Int, error: String, description: String)
    /// The answer of the token endpoint is not the expected JSON.
    case invalidTokenResponse(String)
    /// There is no token and none can be refreshed - the user has to sign in again.
    case notSignedIn

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Kein Geocaching-API-Schlüssel hinterlegt"
        case .invalidConfiguration(let detail):
            "Die Anmeldedaten sind unbrauchbar (\(detail))"
        case .invalidCallback:
            "Die Antwort von geocaching.com war unvollständig"
        case .stateMismatch:
            "Die Antwort von geocaching.com gehört nicht zu dieser Anmeldung"
        case .authorizationDenied(let reason):
            "geocaching.com hat die Anmeldung abgelehnt (\(reason))"
        case .tokenEndpoint(let status, let error, let description):
            "geocaching.com hat den Schlüssel nicht ausgegeben (\(status) \(error)\(description.isEmpty ? "" : ": \(description)"))"
        case .invalidTokenResponse:
            "Die Antwort von geocaching.com war nicht lesbar"
        case .notSignedIn:
            "Nicht bei Geocaching.com angemeldet"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .notConfigured:
            "Für iOS gibt es noch keinen Schlüssel von Geocaching HQ. Lege ihn als GeocachingKeys.plist ab, "
                + "sobald er da ist – die Anmeldung selbst ist fertig eingebaut."
        case .notSignedIn:
            "Melde dich unter „Mehr › Geocaching-Konto“ an."
        case .stateMismatch, .invalidCallback:
            "Versuche die Anmeldung noch einmal."
        default:
            nil
        }
    }
}

/// Builds and reads the requests of the OAuth 2.0 authorization code flow with PKCE.
///
/// Pure functions without network, so the whole protocol can be tested; the network lives in
/// `GeocachingAuthenticator`.
public enum GeocachingOAuth {
    // MARK: - Step 1: send the user to geocaching.com

    /// The authorization URL plus the secrets needed for step 3.
    ///
    /// Parameters as in the API documentation: `client_id`, `response_type=code`, `scope=*`, `redirect_uri`,
    /// `state`, `code_challenge`, `code_challenge_method`.
    public static func authorization(with credentials: GeocachingCredentials,
                                     state: String = randomURLSafeString(byteCount: 16),
                                     pkce: PKCECode = PKCECode()) throws -> GeocachingAuthorization {
        guard !credentials.clientID.isEmpty else { throw GeocachingAuthError.notConfigured }
        guard !credentials.redirectURI.isEmpty else {
            throw GeocachingAuthError.invalidConfiguration("keine Redirect-URI")
        }
        guard var components = URLComponents(url: credentials.environment.authorizationURL,
                                             resolvingAgainstBaseURL: false) else {
            throw GeocachingAuthError.invalidConfiguration("Autorisierungs-URL")
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: credentials.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: credentials.scope),
            URLQueryItem(name: "redirect_uri", value: credentials.redirectURI),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: PKCECode.method),
        ]
        guard let url = components.url else {
            throw GeocachingAuthError.invalidConfiguration("Autorisierungs-URL")
        }
        return GeocachingAuthorization(url: url, state: state, pkce: pkce)
    }

    // MARK: - Step 2: read the callback

    /// The authorization code out of the redirect, after checking `state`.
    ///
    /// `error=access_denied` (the user pressed "no") and every other `error` become
    /// `GeocachingAuthError.authorizationDenied`.
    public static func authorizationCode(from callback: URL, expecting state: String) throws -> String {
        guard let components = URLComponents(url: callback, resolvingAgainstBaseURL: false) else {
            throw GeocachingAuthError.invalidCallback(callback.absoluteString)
        }
        // Parameters normally sit in the query; a fragment is read as well, just in case.
        var items = components.queryItems ?? []
        if let fragment = components.fragment, fragment.contains("=") {
            items += URLComponents(string: "?" + fragment)?.queryItems ?? []
        }
        func value(_ name: String) -> String? {
            items.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
        if let error = value("error"), !error.isEmpty {
            let description = value("error_description") ?? ""
            throw GeocachingAuthError.authorizationDenied(description.isEmpty ? error : "\(error): \(description)")
        }
        guard let returnedState = value("state"), returnedState == state else {
            throw GeocachingAuthError.stateMismatch
        }
        guard let code = value("code"), !code.isEmpty else {
            throw GeocachingAuthError.invalidCallback(callback.absoluteString)
        }
        return code
    }

    // MARK: - Step 3: trade the code for tokens

    /// `POST /token` with `grant_type=authorization_code` (documentation: "Requesting a Token").
    public static func tokenRequest(with credentials: GeocachingCredentials,
                                    code: String,
                                    verifier: String) -> URLRequest {
        var fields = [
            ("client_id", credentials.clientID),
            ("grant_type", "authorization_code"),
            ("redirect_uri", credentials.redirectURI),
            ("code", code),
            ("code_verifier", verifier),
        ]
        if !credentials.clientSecret.isEmpty {
            fields.insert(("client_secret", credentials.clientSecret), at: 1)
        }
        return formRequest(url: credentials.environment.tokenURL, fields: fields)
    }

    /// `POST /token` with `grant_type=refresh_token` (documentation: "Refreshing a Token").
    public static func refreshRequest(with credentials: GeocachingCredentials,
                                      refreshToken: String) -> URLRequest {
        var fields = [
            ("client_id", credentials.clientID),
            ("grant_type", "refresh_token"),
            ("redirect_uri", credentials.redirectURI),
            ("refresh_token", refreshToken),
        ]
        if !credentials.clientSecret.isEmpty {
            fields.insert(("client_secret", credentials.clientSecret), at: 1)
        }
        return formRequest(url: credentials.environment.tokenURL, fields: fields)
    }

    /// Reads the answer of the token endpoint. `expires_in` is counted from `now`.
    public static func tokens(fromResponse data: Data,
                              status: Int,
                              now: Date = Date()) throws -> GeocachingTokens {
        guard (200...299).contains(status) else {
            let error = errorFields(in: data)
            throw GeocachingAuthError.tokenEndpoint(status: status, error: error.0, description: error.1)
        }
        guard let body = try? JSONDecoder().decode(TokenResponseBody.self, from: data),
              !body.accessToken.isEmpty else {
            throw GeocachingAuthError.invalidTokenResponse(snippet(of: data))
        }
        // The documentation shows 3599 s; without the field one hour is assumed, like the PHP demo of the
        // League provider does.
        let lifetime = TimeInterval(body.expiresIn ?? 3600)
        return GeocachingTokens(accessToken: body.accessToken,
                                refreshToken: body.refreshToken,
                                tokenType: body.tokenType ?? "bearer",
                                expiresAt: now.addingTimeInterval(lifetime))
    }

    // MARK: - Helpers

    /// `application/x-www-form-urlencoded` POST. Every value is percent-encoded itself, so that a `+` in a
    /// token stays a `+` (`URLComponents` would leave it alone and the server would read it as a space).
    static func formRequest(url: URL, fields: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(formEncoded(fields).utf8)
        return request
    }

    static func formEncoded(_ fields: [(String, String)]) -> String {
        fields.map { "\(percentEncoded($0.0))=\(percentEncoded($0.1))" }.joined(separator: "&")
    }

    /// Percent-encoding with the unreserved set of RFC 3986 - everything else is escaped, a space as `%20`.
    static func percentEncoded(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    /// base64url without padding (RFC 4648 §5), as PKCE and `state` want it.
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Cryptographically random bytes as base64url - 32 bytes give the 43 characters of a PKCE verifier.
    public static func randomURLSafeString(byteCount: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        var bytes = Data(count: byteCount)
        for index in 0..<byteCount {
            bytes[index] = UInt8.random(in: UInt8.min...UInt8.max, using: &generator)
        }
        return base64URL(bytes)
    }

    /// `error` and `error_description` out of an error answer - JSON, otherwise the plain text.
    static func errorFields(in data: Data) -> (String, String) {
        if let body = try? JSONDecoder().decode(ErrorResponseBody.self, from: data) {
            return (body.error ?? "", body.errorDescription ?? body.message ?? "")
        }
        return ("", snippet(of: data))
    }

    /// The beginning of an unreadable answer, for the error message (never the whole HTML page).
    static func snippet(of data: Data, limit: Int = 200) -> String {
        let text = String(decoding: data.prefix(limit), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.replacingOccurrences(of: "\n", with: " ")
    }

    private struct TokenResponseBody: Decodable {
        var accessToken: String
        var refreshToken: String?
        var tokenType: String?
        var expiresIn: Int?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case tokenType = "token_type"
            case expiresIn = "expires_in"
        }
    }

    private struct ErrorResponseBody: Decodable {
        var error: String?
        var errorDescription: String?
        var message: String?

        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
            case message
        }
    }
}
