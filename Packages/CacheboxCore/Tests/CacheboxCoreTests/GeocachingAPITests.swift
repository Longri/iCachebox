import Foundation
import Testing
@testable import CacheboxCore

private let credentials = GeocachingCredentials(clientID: "12345",
                                                clientSecret: "s3cr3t",
                                                redirectURI: "icachebox://oauth",
                                                environment: .production)

/// The answer of `GET /v1/users/me` as the documentation describes the fields.
private let userJSON = """
{"referenceCode":"PR1ZE","username":"Longri","findCount":4711,"hideCount":42,"favoritePoints":17,
 "membershipLevelId":3,"joinedDateUtc":"2010-11-21T00:00:00"}
"""

@Suite("Geocaching-API")
struct GeocachingAPITests {
    private func api(clock: TestClock, http: StubHTTPClient, expiresIn: TimeInterval = 3600)
        -> (GeocachingAPI, GeocachingMemoryTokenStore) {
        let store = GeocachingMemoryTokenStore(
            tokens: GeocachingTokens(accessToken: "access-1", refreshToken: "refresh-1",
                                     expiresAt: clock.now.addingTimeInterval(expiresIn)))
        let authenticator = GeocachingAuthenticator(credentials: credentials, store: store, http: http,
                                                    clock: { clock.now })
        return (GeocachingAPI(authenticator: authenticator, http: http), store)
    }

    /// The user, with URL, fields and token the way the API wants them.
    @Test func readsTheSignedInUser() async throws {
        let clock = TestClock()
        let http = StubHTTPClient([.init(json: userJSON)])
        let (api, _) = api(clock: clock, http: http)

        let user = try await api.me()
        #expect(user.username == "Longri")
        #expect(user.referenceCode == "PR1ZE")
        #expect(user.findCount == 4711)
        #expect(user.hideCount == 42)
        #expect(user.favoritePoints == 17)
        #expect(user.membership == .premium)
        #expect(user.membership.isPremium)

        let request = try #require(await http.requests().first)
        #expect(request.url?.host() == "api.groundspeak.com")
        #expect(request.url?.path() == "/v1/users/me")
        let fields = try #require(request.url?.queryFields["fields"])
        #expect(fields.contains("username"))
        #expect(fields.contains("membershipLevelId"))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "bearer access-1")
    }

    /// Fields that were not asked for are simply missing - that must not break the answer.
    @Test func survivesAThinAnswer() async throws {
        let clock = TestClock()
        let http = StubHTTPClient([.init(json: #"{"username":"Longri"}"#)])
        let (api, _) = api(clock: clock, http: http)
        let user = try await api.me(fields: ["username"])
        #expect(user.username == "Longri")
        #expect(user.findCount == 0)
        #expect(user.membership == .unknown)
        #expect(user.membership.isPremium == false)
    }

    /// A 401 despite a valid-looking token: refresh once and try again (the server may have dropped it early).
    @Test func repeatsOnceAfterA401() async throws {
        let clock = TestClock()
        let http = StubHTTPClient([
            .init(status: 401, json: #"{"errorMessage":"Token expired"}"#),
            .init(json: #"{"access_token":"access-2","expires_in":3600,"refresh_token":"refresh-2"}"#),
            .init(json: userJSON),
        ])
        let (api, store) = api(clock: clock, http: http)

        let user = try await api.me()
        #expect(user.username == "Longri")
        #expect(try store.load()?.accessToken == "access-2")

        let requests = await http.requests()
        #expect(requests.count == 3)
        #expect(requests[1].url?.absoluteString == "https://oauth.geocaching.com/token")
        #expect(requests[1].formFields["grant_type"] == "refresh_token")
        // The repeat carries the fresh token.
        #expect(requests[2].value(forHTTPHeaderField: "Authorization") == "bearer access-2")
    }

    /// A second 401 is not tried a third time.
    @Test func givesUpAfterTheSecond401() async throws {
        let clock = TestClock()
        let http = StubHTTPClient([
            .init(status: 401, json: ""),
            .init(json: #"{"access_token":"access-2","expires_in":3600,"refresh_token":"r2"}"#),
            .init(status: 401, json: #"{"errorMessage":"nope"}"#),
        ])
        let (api, _) = api(clock: clock, http: http)
        await #expect(throws: GeocachingAPIError.http(status: 401, message: "nope")) {
            try await api.me()
        }
        #expect(await http.requestCount() == 3)
    }

    /// 429: the API allows 60 calls a minute per method.
    @Test func reportsTheRateLimit() async throws {
        let clock = TestClock()
        let http = StubHTTPClient([.init(status: 429, json: "", headers: ["x-rate-limit-reset": "42"])])
        let (api, _) = api(clock: clock, http: http)
        await #expect(throws: GeocachingAPIError.rateLimited(retryAfter: 42)) { try await api.me() }
    }

    /// Any other error keeps the message of the server.
    @Test func keepsTheServerMessage() async throws {
        let clock = TestClock()
        let http = StubHTTPClient([.init(status: 403, json: #"{"statusMessage":"Premium only"}"#)])
        let (api, _) = api(clock: clock, http: http)
        await #expect(throws: GeocachingAPIError.http(status: 403, message: "Premium only")) {
            try await api.me()
        }
    }

    /// An expired token is refreshed before the call, without a wasted 401.
    @Test func refreshesBeforeTheCall() async throws {
        let clock = TestClock()
        let http = StubHTTPClient([
            .init(json: #"{"access_token":"access-2","expires_in":3600,"refresh_token":"r2"}"#),
            .init(json: userJSON),
        ])
        let (api, _) = api(clock: clock, http: http, expiresIn: -1)
        _ = try await api.me()
        let requests = await http.requests()
        #expect(requests.count == 2)
        #expect(requests[0].formFields["grant_type"] == "refresh_token")
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "bearer access-2")
    }

    /// Staging talks to the other host.
    @Test func usesTheStagingHost() async throws {
        let clock = TestClock()
        var staging = credentials
        staging.environment = .staging
        let http = StubHTTPClient([.init(json: userJSON)])
        let store = GeocachingMemoryTokenStore(
            tokens: GeocachingTokens(accessToken: "a", refreshToken: "b",
                                     expiresAt: clock.now.addingTimeInterval(3600)))
        let api = GeocachingAPI(authenticator: GeocachingAuthenticator(credentials: staging, store: store,
                                                                       http: http, clock: { clock.now }),
                                http: http)
        _ = try await api.me()
        #expect(await http.requests().first?.url?.host() == "staging.api.groundspeak.com")
    }

    @Test func mapsTheMembershipLevels() {
        #expect(GeocachingMembership(id: 0) == .unknown)
        #expect(GeocachingMembership(id: 1) == .basic)
        #expect(GeocachingMembership(id: 2) == .charter)
        #expect(GeocachingMembership(id: 3) == .premium)
        #expect(GeocachingMembership(id: 99) == .unknown)
        #expect(GeocachingMembership(id: nil) == .unknown)
        #expect(GeocachingMembership.basic.isPremium == false)
        #expect(GeocachingMembership.charter.isPremium)
        #expect(GeocachingMembership.premium.name == "Premium")
    }

    /// The API writes UTC without a zone.
    @Test func readsTheJoinDate() {
        let user = GeocachingUser(joinedDateUtc: "2010-11-21T00:00:00")
        let date = try! #require(user.joinedDate)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        #expect(calendar.component(.year, from: date) == 2010)
        #expect(calendar.component(.month, from: date) == 11)
        #expect(calendar.component(.day, from: date) == 21)
        #expect(GeocachingUser(joinedDateUtc: "2010-11-21T00:00:00.1234567Z").joinedDate != nil)
        #expect(GeocachingUser(joinedDateUtc: "2010-11-21").joinedDate != nil)
        #expect(GeocachingUser(joinedDateUtc: "unsinn").joinedDate == nil)
        #expect(GeocachingUser().joinedDate == nil)
    }
}
