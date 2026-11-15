import Foundation

/// The bit of networking the sign-in needs. A protocol so the tests can answer without a server.
public protocol GeocachingHTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The real client: `URLSession.shared`.
public struct GeocachingURLSessionClient: GeocachingHTTPClient {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

/// Holds the tokens of the signed-in user and keeps them fresh.
///
/// An actor, because the access token is asked for from several places at once (list, map, compass) and a
/// refresh must happen only once - a second refresh with an already used refresh token would fail.
///
/// The browser part is not in here: the app shows `authorization().url` in an `ASWebAuthenticationSession`
/// and hands the callback URL back to `completeSignIn`. That keeps this type free of UIKit and testable.
public actor GeocachingAuthenticator {
    /// `nonisolated`, because key and redirect URI never change and other modules read them without awaiting.
    public nonisolated let credentials: GeocachingCredentials
    private let store: any GeocachingTokenStoring
    private let http: any GeocachingHTTPClient
    /// Injectable clock, so the tests do not have to wait for a token to expire.
    private let clock: @Sendable () -> Date

    private var cached: GeocachingTokens?
    private var didLoad = false
    private var refreshTask: Task<GeocachingTokens, any Error>?

    public init(credentials: GeocachingCredentials,
                store: any GeocachingTokenStoring = GeocachingKeychainStore(),
                http: any GeocachingHTTPClient = GeocachingURLSessionClient(),
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.credentials = credentials
        self.store = store
        self.http = http
        self.clock = clock
    }

    // MARK: - State

    /// The stored tokens, read from the keychain on first use.
    public func tokens() throws -> GeocachingTokens? {
        if !didLoad {
            cached = try store.load()
            didLoad = true
        }
        return cached
    }

    /// Whether a sign-in is stored at all - it may still need a refresh.
    public func isSignedIn() -> Bool {
        ((try? tokens()) ?? nil) != nil
    }

    // MARK: - Signing in

    /// Step 1: the page to show the user, plus `state` and PKCE verifier for step 2.
    public func authorization() throws -> GeocachingAuthorization {
        try GeocachingOAuth.authorization(with: credentials)
    }

    /// Step 2: the callback URL of `ASWebAuthenticationSession` becomes a token pair.
    @discardableResult
    public func completeSignIn(callback: URL,
                               authorization: GeocachingAuthorization) async throws -> GeocachingTokens {
        let code = try GeocachingOAuth.authorizationCode(from: callback, expecting: authorization.state)
        let request = GeocachingOAuth.tokenRequest(with: credentials,
                                                   code: code,
                                                   verifier: authorization.pkce.verifier)
        let (data, response) = try await http.send(request)
        let tokens = try GeocachingOAuth.tokens(fromResponse: data, status: response.statusCode, now: clock())
        try remember(tokens)
        return tokens
    }

    /// Forgets the tokens. geocaching.com itself is not told - the API has no revoke endpoint.
    public func signOut() throws {
        refreshTask?.cancel()
        refreshTask = nil
        cached = nil
        didLoad = true
        try store.clear()
    }

    // MARK: - Using the tokens

    /// A token that is good for the next minute, refreshing it if need be.
    public func accessToken() async throws -> String {
        if let tokens = try tokens(), tokens.isValid(at: clock()) {
            return tokens.accessToken
        }
        return try await refresh().accessToken
    }

    /// Puts the `Authorization` header on a request (documentation: `Authorization: bearer {token}`).
    public func authorized(_ request: URLRequest) async throws -> URLRequest {
        guard let tokens = try tokens() else { throw GeocachingAuthError.notSignedIn }
        var request = request
        let header = tokens.isValid(at: clock())
            ? tokens.authorizationHeader
            : try await refresh().authorizationHeader
        request.setValue(header, forHTTPHeaderField: "Authorization")
        return request
    }

    /// Fetches a new access token. Several callers at once share one request.
    @discardableResult
    public func refresh() async throws -> GeocachingTokens {
        if let refreshTask {
            return try await refreshTask.value
        }
        guard let current = try tokens() else { throw GeocachingAuthError.notSignedIn }
        guard let refreshToken = current.refreshToken, !refreshToken.isEmpty else {
            // Without a refresh token the sign-in is over once the access token has expired.
            throw GeocachingAuthError.notSignedIn
        }
        // Everything happens inside the task, so that whoever only waits for it gets exactly the same,
        // already stored tokens. The task inherits the isolation of this actor, so it may touch `cached` and
        // the store directly; the network call inside it suspends and lets other work through as usual.
        let task = Task { [credentials, http, clock] () throws -> GeocachingTokens in
            let request = GeocachingOAuth.refreshRequest(with: credentials, refreshToken: refreshToken)
            let (data, response) = try await http.send(request)
            do {
                var fresh = try GeocachingOAuth.tokens(fromResponse: data, status: response.statusCode,
                                                       now: clock())
                // Should the answer carry no new refresh token, the old one stays - it is good for a year.
                if fresh.refreshToken == nil { fresh.refreshToken = refreshToken }
                try self.remember(fresh)
                return fresh
            } catch let error as GeocachingAuthError {
                // A refresh token that geocaching.com no longer accepts is worthless: throw it away, so the
                // app shows "not signed in" instead of running into the same error at every request.
                if case .tokenEndpoint(let status, _, _) = error, status == 400 || status == 401 {
                    self.dropTokens()
                }
                throw error
            }
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    // MARK: - Private

    private func remember(_ tokens: GeocachingTokens) throws {
        cached = tokens
        didLoad = true
        try store.save(tokens)
    }

    /// `signOut` without touching `refreshTask` - called from inside the refresh itself.
    private func dropTokens() {
        cached = nil
        didLoad = true
        try? store.clear()
    }
}
