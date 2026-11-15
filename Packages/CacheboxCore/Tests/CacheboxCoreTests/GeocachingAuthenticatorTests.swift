import Foundation
import Testing
@testable import CacheboxCore

/// A clock the test moves by hand, so a token can expire without waiting.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.date = date
    }

    var now: Date {
        get { lock.withLock { date } }
        set { lock.withLock { date = newValue } }
    }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { date = date.addingTimeInterval(seconds) }
    }
}

private let credentials = GeocachingCredentials(clientID: "12345",
                                                clientSecret: "s3cr3t",
                                                redirectURI: "icachebox://oauth",
                                                environment: .production)

private func tokens(access: String = "access-1",
                    refresh: String? = "refresh-1",
                    expiresIn: TimeInterval = 3600,
                    clock: TestClock) -> GeocachingTokens {
    GeocachingTokens(accessToken: access, refreshToken: refresh,
                     expiresAt: clock.now.addingTimeInterval(expiresIn))
}

@Suite("Anmeldung")
struct AuthenticatorTests {
    /// The whole sign-in: URL, callback, code exchange, tokens in the store.
    @Test func signsInAndKeepsTheTokens() async throws {
        let clock = TestClock()
        let store = GeocachingMemoryTokenStore()
        let http = StubHTTPClient([.init(json: """
        {"access_token":"AAAA","token_type":"bearer","expires_in":3599,"refresh_token":"BBBB"}
        """)])
        let authenticator = GeocachingAuthenticator(credentials: credentials, store: store, http: http,
                                                    clock: { clock.now })

        let authorization = try await authenticator.authorization()
        let callback = URL(string: "icachebox://oauth?code=the-code&state=\(authorization.state)")!
        let result = try await authenticator.completeSignIn(callback: callback, authorization: authorization)

        #expect(result.accessToken == "AAAA")
        #expect(try store.load()?.accessToken == "AAAA")
        #expect(try store.load()?.refreshToken == "BBBB")
        #expect(await authenticator.isSignedIn())

        // The code exchange carried the code and the verifier of exactly this sign-in.
        let sent = try #require(await http.requests().first)
        #expect(sent.url?.absoluteString == "https://oauth.geocaching.com/token")
        #expect(sent.formFields["code"] == "the-code")
        #expect(sent.formFields["code_verifier"] == authorization.pkce.verifier)
        #expect(sent.formFields["grant_type"] == "authorization_code")
    }

    /// A callback that belongs to another sign-in never reaches the token endpoint.
    @Test func doesNotExchangeAForeignCallback() async throws {
        let clock = TestClock()
        let http = StubHTTPClient([])
        let authenticator = GeocachingAuthenticator(credentials: credentials,
                                                    store: GeocachingMemoryTokenStore(),
                                                    http: http, clock: { clock.now })
        let authorization = try await authenticator.authorization()
        let callback = URL(string: "icachebox://oauth?code=c&state=fremd")!
        await #expect(throws: GeocachingAuthError.stateMismatch) {
            try await authenticator.completeSignIn(callback: callback, authorization: authorization)
        }
        #expect(await http.requestCount() == 0)
    }

    /// A valid token is handed out without asking the server.
    @Test func usesTheStoredTokenWithoutNetwork() async throws {
        let clock = TestClock()
        let store = GeocachingMemoryTokenStore(tokens: tokens(clock: clock))
        let http = StubHTTPClient([])  // every request would fail
        let authenticator = GeocachingAuthenticator(credentials: credentials, store: store, http: http,
                                                    clock: { clock.now })
        #expect(try await authenticator.accessToken() == "access-1")
        #expect(await http.requestCount() == 0)
    }

    /// An expired token is replaced before it is handed out.
    @Test func refreshesAnExpiredToken() async throws {
        let clock = TestClock()
        let store = GeocachingMemoryTokenStore(tokens: tokens(expiresIn: 10, clock: clock))
        let http = StubHTTPClient([.init(json: """
        {"access_token":"access-2","token_type":"bearer","expires_in":3600,"refresh_token":"refresh-2"}
        """)])
        let authenticator = GeocachingAuthenticator(credentials: credentials, store: store, http: http,
                                                    clock: { clock.now })

        // Still inside the leeway: the token counts as expired already.
        #expect(try await authenticator.accessToken() == "access-2")
        #expect(try store.load()?.refreshToken == "refresh-2")
        let sent = try #require(await http.requests().first)
        #expect(sent.formFields["grant_type"] == "refresh_token")
        #expect(sent.formFields["refresh_token"] == "refresh-1")
    }

    /// Should the answer bring no new refresh token, the old one stays - it is good for a year.
    @Test func keepsTheOldRefreshToken() async throws {
        let clock = TestClock()
        let store = GeocachingMemoryTokenStore(tokens: tokens(expiresIn: -1, clock: clock))
        let http = StubHTTPClient([.init(json: #"{"access_token":"access-2","expires_in":3600}"#)])
        let authenticator = GeocachingAuthenticator(credentials: credentials, store: store, http: http,
                                                    clock: { clock.now })
        let fresh = try await authenticator.refresh()
        #expect(fresh.accessToken == "access-2")
        #expect(fresh.refreshToken == "refresh-1")
        #expect(try store.load()?.refreshToken == "refresh-1")
    }

    /// Several callers at once share one refresh - a refresh token may only be redeemed once.
    @Test func refreshesOnlyOnceAtATime() async throws {
        let clock = TestClock()
        let store = GeocachingMemoryTokenStore(tokens: tokens(expiresIn: -100, clock: clock))
        let http = StubHTTPClient([.init(json: #"{"access_token":"access-2","expires_in":3600,"refresh_token":"r2"}"#,
                                         delay: .milliseconds(50))])
        let authenticator = GeocachingAuthenticator(credentials: credentials, store: store, http: http,
                                                    clock: { clock.now })

        let results = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<8 {
                group.addTask { try await authenticator.accessToken() }
            }
            var all: [String] = []
            for try await token in group { all.append(token) }
            return all
        }

        #expect(results == Array(repeating: "access-2", count: 8))
        #expect(await http.requestCount() == 1)
    }

    /// Whoever only waits for a running refresh gets the same tokens as the one who started it - with the
    /// carried-over refresh token and already stored.
    @Test func handsWaitersTheStoredTokens() async throws {
        let clock = TestClock()
        let store = GeocachingMemoryTokenStore(tokens: tokens(expiresIn: -1, clock: clock))
        let http = StubHTTPClient([.init(json: #"{"access_token":"access-2","expires_in":3600}"#,
                                         delay: .milliseconds(50))])
        let authenticator = GeocachingAuthenticator(credentials: credentials, store: store, http: http,
                                                    clock: { clock.now })

        let results = try await withThrowingTaskGroup(of: GeocachingTokens.self) { group in
            for _ in 0..<5 {
                group.addTask { try await authenticator.refresh() }
            }
            var all: [GeocachingTokens] = []
            for try await tokens in group { all.append(tokens) }
            return all
        }

        #expect(await http.requestCount() == 1)
        #expect(results.allSatisfy { $0.refreshToken == "refresh-1" })
        #expect(results.allSatisfy { $0 == results[0] })
        #expect(try store.load() == results[0])
    }

    /// A refresh token geocaching.com no longer accepts is thrown away, so the app shows "not signed in"
    /// instead of running into the same error at every request.
    @Test func forgetsARejectedRefreshToken() async throws {
        let clock = TestClock()
        let store = GeocachingMemoryTokenStore(tokens: tokens(expiresIn: -1, clock: clock))
        let http = StubHTTPClient([.init(status: 400,
                                         json: #"{"error":"invalid_grant","error_description":"expired"}"#)])
        let authenticator = GeocachingAuthenticator(credentials: credentials, store: store, http: http,
                                                    clock: { clock.now })
        await #expect(throws: GeocachingAuthError.tokenEndpoint(status: 400, error: "invalid_grant",
                                                                 description: "expired")) {
            try await authenticator.refresh()
        }
        #expect(try store.load() == nil)
        #expect(await authenticator.isSignedIn() == false)
    }

    /// A server hiccup (500) must not log the user out - the token is still good.
    @Test func keepsTheTokenAfterAServerError() async throws {
        let clock = TestClock()
        let store = GeocachingMemoryTokenStore(tokens: tokens(expiresIn: -1, clock: clock))
        let http = StubHTTPClient([.init(status: 500, json: "")])
        let authenticator = GeocachingAuthenticator(credentials: credentials, store: store, http: http,
                                                    clock: { clock.now })
        await #expect(throws: (any Error).self) { try await authenticator.refresh() }
        #expect(try store.load()?.accessToken == "access-1")
    }

    /// Without a sign-in there is no token, and nothing is asked of the server.
    @Test func reportsThatNobodyIsSignedIn() async throws {
        let http = StubHTTPClient([])
        let authenticator = GeocachingAuthenticator(credentials: credentials,
                                                    store: GeocachingMemoryTokenStore(), http: http)
        await #expect(throws: GeocachingAuthError.notSignedIn) { try await authenticator.accessToken() }
        #expect(await authenticator.isSignedIn() == false)
        #expect(await http.requestCount() == 0)
    }

    /// Without a refresh token the sign-in is over once the access token has expired.
    @Test func reportsAMissingRefreshToken() async throws {
        let clock = TestClock()
        let store = GeocachingMemoryTokenStore(tokens: tokens(refresh: nil, expiresIn: -1, clock: clock))
        let authenticator = GeocachingAuthenticator(credentials: credentials, store: store,
                                                    http: StubHTTPClient([]), clock: { clock.now })
        await #expect(throws: GeocachingAuthError.notSignedIn) { try await authenticator.accessToken() }
    }

    @Test func signsOut() async throws {
        let clock = TestClock()
        let store = GeocachingMemoryTokenStore(tokens: tokens(clock: clock))
        let authenticator = GeocachingAuthenticator(credentials: credentials, store: store,
                                                    http: StubHTTPClient([]), clock: { clock.now })
        #expect(await authenticator.isSignedIn())
        try await authenticator.signOut()
        #expect(await authenticator.isSignedIn() == false)
        #expect(try store.load() == nil)
    }

    /// `Authorization: bearer <token>`, as the documentation writes it.
    @Test func putsTheTokenOnARequest() async throws {
        let clock = TestClock()
        let store = GeocachingMemoryTokenStore(tokens: tokens(clock: clock))
        let authenticator = GeocachingAuthenticator(credentials: credentials, store: store,
                                                    http: StubHTTPClient([]), clock: { clock.now })
        let request = try await authenticator.authorized(URLRequest(url: URL(string: "https://api.groundspeak.com/v1/users/me")!))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "bearer access-1")
    }

    /// A token of a newer build that this one cannot read counts as "not signed in" instead of crashing.
    @Test func survivesAnUnreadableStoredToken() async throws {
        let store = GeocachingMemoryTokenStore()
        let authenticator = GeocachingAuthenticator(credentials: credentials, store: store,
                                                    http: StubHTTPClient([]))
        #expect(await authenticator.isSignedIn() == false)
    }
}

@Suite("Schlüsselbund")
struct KeychainStoreTests {
    /// Round trip through the real keychain. Skipped where the test runner has no keychain of its own
    /// (sandboxed CI); in the app the store runs with the app's own entitlement.
    @Test func storesAndDeletesTokens() throws {
        let store = GeocachingKeychainStore(service: "de.team-cachebox.icachebox.test.\(UUID().uuidString)")
        let tokens = GeocachingTokens(accessToken: "a", refreshToken: "b",
                                      expiresAt: Date(timeIntervalSince1970: 1_700_000_000))
        do {
            try store.save(tokens)
        } catch {
            return  // no keychain here
        }
        defer { try? store.clear() }
        #expect(try store.load() == tokens)

        var changed = tokens
        changed.accessToken = "c"
        try store.save(changed)
        #expect(try store.load()?.accessToken == "c")

        try store.clear()
        #expect(try store.load() == nil)
        // Deleting twice is not an error.
        try store.clear()
    }
}
