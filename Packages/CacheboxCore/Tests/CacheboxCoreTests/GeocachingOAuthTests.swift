import Foundation
import Testing
@testable import CacheboxCore

// MARK: - Helpers

/// Answers prepared requests without a server and remembers what was asked.
actor StubHTTPClient: GeocachingHTTPClient {
    struct Answer: Sendable {
        var status: Int = 200
        var json: String = "{}"
        var headers: [String: String] = [:]
        /// Lets the answer linger, so two callers really overlap.
        var delay: Duration = .zero
    }

    private var answers: [Answer]
    private var sent: [URLRequest] = []

    init(_ answers: [Answer]) {
        self.answers = answers
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        sent.append(request)
        guard !answers.isEmpty else {
            throw URLError(.unsupportedURL)  // one request too many
        }
        let answer = answers.removeFirst()
        if answer.delay > .zero { try await Task.sleep(for: answer.delay) }
        let response = HTTPURLResponse(url: request.url!, statusCode: answer.status,
                                       httpVersion: "HTTP/1.1", headerFields: answer.headers)!
        return (Data(answer.json.utf8), response)
    }

    func requests() -> [URLRequest] { sent }
    func requestCount() -> Int { sent.count }
}

extension URLRequest {
    /// The fields of an `application/x-www-form-urlencoded` body.
    var formFields: [String: String] {
        guard let body = httpBody, let text = String(data: body, encoding: .utf8) else { return [:] }
        var fields: [String: String] = [:]
        for pair in text.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            fields[String(parts[0]).removingPercentEncoding ?? String(parts[0])] =
                String(parts[1]).removingPercentEncoding ?? String(parts[1])
        }
        return fields
    }

    /// The raw body, to check the encoding itself.
    var formBody: String { String(decoding: httpBody ?? Data(), as: UTF8.self) }
}

extension URL {
    var queryFields: [String: String] {
        let items = URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }
}

private let testCredentials = GeocachingCredentials(
    clientID: "12345",
    clientSecret: "s3cr3t",
    redirectURI: "icachebox://oauth",
    environment: .production)

// MARK: - PKCE

@Suite("PKCE")
struct PKCETests {
    /// The example of RFC 7636 appendix B - the same verifier has to give the same challenge, otherwise
    /// geocaching.com rejects the code exchange.
    @Test func matchesTheRFCExample() {
        let pkce = PKCECode(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(PKCECode.method == "S256")
    }

    /// A fresh verifier keeps to length and character set of RFC 7636 §4.1 (43 to 128 unreserved characters).
    @Test func generatesAWellFormedVerifier() {
        for _ in 0..<50 {
            let pkce = PKCECode()
            #expect(pkce.verifier.count == 43)
            #expect(pkce.isWellFormed)
            // base64url: no padding and no characters that would have to be escaped in a URL.
            #expect(!pkce.challenge.contains("="))
            #expect(!pkce.challenge.contains("+"))
            #expect(!pkce.challenge.contains("/"))
        }
    }

    /// Two sign-ins never share a verifier.
    @Test func generatesADifferentVerifierEveryTime() {
        let verifiers = Set((0..<200).map { _ in PKCECode().verifier })
        #expect(verifiers.count == 200)
    }

    @Test func recognisesAMalformedVerifier() {
        #expect(!PKCECode(verifier: "zu kurz").isWellFormed)
        #expect(!PKCECode(verifier: String(repeating: "a", count: 129)).isWellFormed)
        #expect(!PKCECode(verifier: String(repeating: "a", count: 42) + "/").isWellFormed)
        #expect(PKCECode(verifier: String(repeating: "a", count: 43)).isWellFormed)
    }
}

// MARK: - Step 1: the authorization URL

@Suite("Autorisierungs-URL")
struct AuthorizationURLTests {
    /// Every parameter of the API documentation, with the values it asks for.
    @Test func carriesEveryParameter() throws {
        let pkce = PKCECode(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let authorization = try GeocachingOAuth.authorization(with: testCredentials,
                                                              state: "1234abcd",
                                                              pkce: pkce)
        #expect(authorization.url.scheme == "https")
        #expect(authorization.url.host() == "www.geocaching.com")
        #expect(authorization.url.path() == "/oauth/authorize.aspx")
        let query = authorization.url.queryFields
        #expect(query["client_id"] == "12345")
        #expect(query["response_type"] == "code")
        #expect(query["scope"] == "*")
        #expect(query["redirect_uri"] == "icachebox://oauth")
        #expect(query["state"] == "1234abcd")
        #expect(query["code_challenge"] == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(query["code_challenge_method"] == "S256")
        #expect(authorization.state == "1234abcd")
        #expect(authorization.pkce == pkce)
        // The custom scheme must survive as a whole, otherwise the redirect does not match the registered one.
        #expect(authorization.url.absoluteString.contains("redirect_uri=icachebox://oauth"))
    }

    /// The consumer secret never shows up in the browser.
    @Test func keepsTheSecretOutOfTheURL() throws {
        let authorization = try GeocachingOAuth.authorization(with: testCredentials)
        #expect(!authorization.url.absoluteString.contains("s3cr3t"))
        #expect(!authorization.url.absoluteString.contains("client_secret"))
    }

    /// Every call gets its own state and its own verifier.
    @Test func usesAFreshStateEveryTime() throws {
        let first = try GeocachingOAuth.authorization(with: testCredentials)
        let second = try GeocachingOAuth.authorization(with: testCredentials)
        #expect(first.state != second.state)
        #expect(first.pkce != second.pkce)
        #expect(first.state.count >= 20)
    }

    /// Staging uses the other hosts.
    @Test func usesTheStagingHosts() throws {
        var credentials = testCredentials
        credentials.environment = .staging
        let authorization = try GeocachingOAuth.authorization(with: credentials)
        #expect(authorization.url.host() == "staging.geocaching.com")
        #expect(GeocachingEnvironment.staging.tokenURL.absoluteString == "https://oauth-staging.geocaching.com/token")
        #expect(GeocachingEnvironment.staging.apiBaseURL.absoluteString == "https://staging.api.groundspeak.com")
        #expect(GeocachingEnvironment.named("Staging") == .staging)
        #expect(GeocachingEnvironment.named("production") == .production)
        #expect(GeocachingEnvironment.named("irgendwas") == nil)
    }

    /// Without a consumer key there is no sign-in - that is the state until HQ hands one out for iOS.
    @Test func refusesWithoutAKey() {
        var credentials = testCredentials
        credentials.clientID = ""
        #expect(throws: GeocachingAuthError.notConfigured) {
            _ = try GeocachingOAuth.authorization(with: credentials)
        }
    }

    /// `ASWebAuthenticationSession` needs the scheme of the redirect; an https redirect has none.
    @Test func findsTheCallbackScheme() {
        #expect(testCredentials.callbackScheme == "icachebox")
        var https = testCredentials
        https.redirectURI = "https://www.geocaching.com"
        #expect(https.callbackScheme == nil)
    }

    /// With a registered https redirect that only hands the code on (Cachebox's `gc-oauth.longri.de`), the
    /// app waits for its own scheme while `redirect_uri` stays that page in both requests.
    @Test func keepsTheRegisteredRedirectWithItsOwnScheme() throws {
        let credentials = GeocachingCredentials(clientID: "12345",
                                                clientSecret: "s3cr3t",
                                                redirectURI: "https://gc-oauth.longri.de/index.php?Version=ACB",
                                                callbackSchemeOverride: "icachebox")
        #expect(credentials.callbackScheme == "icachebox")

        let authorization = try GeocachingOAuth.authorization(with: credentials, state: "s", pkce: PKCECode())
        #expect(authorization.url.queryFields["redirect_uri"] == "https://gc-oauth.longri.de/index.php?Version=ACB")
        // The query of the redirect has to survive the escaping, otherwise HQ sees another URI.
        #expect(authorization.url.absoluteString.contains("Version%3DACB"))

        let token = GeocachingOAuth.tokenRequest(with: credentials, code: "c", verifier: "v")
        #expect(token.formFields["redirect_uri"] == "https://gc-oauth.longri.de/index.php?Version=ACB")
        let refresh = GeocachingOAuth.refreshRequest(with: credentials, refreshToken: "r")
        #expect(refresh.formFields["redirect_uri"] == "https://gc-oauth.longri.de/index.php?Version=ACB")

        // The callback itself arrives under the app's own scheme.
        let callback = URL(string: "icachebox://oauth?code=abc&state=s")!
        #expect(try GeocachingOAuth.authorizationCode(from: callback, expecting: "s") == "abc")
    }

    /// An empty override is as good as none.
    @Test func ignoresAnEmptyOverride() {
        var credentials = testCredentials
        credentials.callbackSchemeOverride = ""
        #expect(credentials.callbackScheme == "icachebox")
        credentials.callbackSchemeOverride = "ICacheBox"
        #expect(credentials.callbackScheme == "icachebox")
    }
}

// MARK: - Step 2: the callback

@Suite("Callback")
struct CallbackTests {
    @Test func readsTheCode() throws {
        let url = URL(string: "icachebox://oauth?code=abc123&state=1234abcd")!
        #expect(try GeocachingOAuth.authorizationCode(from: url, expecting: "1234abcd") == "abc123")
    }

    /// A callback with somebody else's state is thrown away (XSRF).
    @Test func refusesAForeignState() {
        let url = URL(string: "icachebox://oauth?code=abc123&state=fremd")!
        #expect(throws: GeocachingAuthError.stateMismatch) {
            _ = try GeocachingOAuth.authorizationCode(from: url, expecting: "1234abcd")
        }
    }

    /// The user pressed "no".
    @Test func reportsADenial() {
        let url = URL(string: "icachebox://oauth?error=access_denied&error_description=User%20said%20no&state=1234abcd")!
        #expect(throws: GeocachingAuthError.authorizationDenied("access_denied: User said no")) {
            _ = try GeocachingOAuth.authorizationCode(from: url, expecting: "1234abcd")
        }
    }

    /// An error is reported even when the state is missing - geocaching.com may leave it out then.
    @Test func reportsAnErrorWithoutState() {
        let url = URL(string: "icachebox://oauth?error=invalid_request")!
        #expect(throws: GeocachingAuthError.authorizationDenied("invalid_request")) {
            _ = try GeocachingOAuth.authorizationCode(from: url, expecting: "1234abcd")
        }
    }

    @Test func refusesACallbackWithoutCode() {
        let url = URL(string: "icachebox://oauth?state=1234abcd")!
        #expect(throws: GeocachingAuthError.invalidCallback("icachebox://oauth?state=1234abcd")) {
            _ = try GeocachingOAuth.authorizationCode(from: url, expecting: "1234abcd")
        }
    }

    /// Should the parameters arrive in the fragment, they are read as well.
    @Test func alsoReadsTheFragment() throws {
        let url = URL(string: "icachebox://oauth#code=abc123&state=1234abcd")!
        #expect(try GeocachingOAuth.authorizationCode(from: url, expecting: "1234abcd") == "abc123")
    }

    /// A code with characters that have to be escaped arrives unescaped.
    @Test func unescapesTheCode() throws {
        let url = URL(string: "icachebox://oauth?code=a%2Bb%2Fc%3D&state=s")!
        #expect(try GeocachingOAuth.authorizationCode(from: url, expecting: "s") == "a+b/c=")
    }
}

// MARK: - Step 3: the token requests

@Suite("Token-Anfragen")
struct TokenRequestTests {
    /// Body of the code exchange, as the documentation lists it.
    @Test func buildsTheCodeExchange() {
        let request = GeocachingOAuth.tokenRequest(with: testCredentials, code: "abc123", verifier: "v".padded)
        #expect(request.url?.absoluteString == "https://oauth.geocaching.com/token")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("application/x-www-form-urlencoded") == true)
        let fields = request.formFields
        #expect(fields["client_id"] == "12345")
        #expect(fields["client_secret"] == "s3cr3t")
        #expect(fields["grant_type"] == "authorization_code")
        #expect(fields["redirect_uri"] == "icachebox://oauth")
        #expect(fields["code"] == "abc123")
        #expect(fields["code_verifier"] == "v".padded)
        #expect(fields.count == 6)
    }

    @Test func buildsTheRefresh() {
        let request = GeocachingOAuth.refreshRequest(with: testCredentials, refreshToken: "r3fr3sh")
        let fields = request.formFields
        #expect(fields["client_id"] == "12345")
        #expect(fields["client_secret"] == "s3cr3t")
        #expect(fields["grant_type"] == "refresh_token")
        #expect(fields["redirect_uri"] == "icachebox://oauth")
        #expect(fields["refresh_token"] == "r3fr3sh")
        #expect(fields.count == 5)
    }

    /// A public client without a secret simply leaves the field out.
    @Test func leavesOutAnEmptySecret() {
        var credentials = testCredentials
        credentials.clientSecret = ""
        let request = GeocachingOAuth.tokenRequest(with: credentials, code: "abc", verifier: "v")
        #expect(request.formFields["client_secret"] == nil)
        #expect(!request.formBody.contains("client_secret"))
    }

    /// Form encoding: everything outside the unreserved set is escaped, a space becomes `%20` and not `+`.
    /// A token that carries a `+` would otherwise arrive as a space.
    @Test func escapesTheBodyProperly() {
        let encoded = GeocachingOAuth.formEncoded([("a b", "x+y/z=&?"), ("ä", "~-._")])
        #expect(encoded == "a%20b=x%2By%2Fz%3D%26%3F&%C3%A4=~-._")
    }

    /// The redirect URI keeps its colon and slashes, so that the server sees the registered string again.
    @Test func escapesTheRedirectURI() {
        let request = GeocachingOAuth.tokenRequest(with: testCredentials, code: "c", verifier: "v")
        #expect(request.formBody.contains("redirect_uri=icachebox%3A%2F%2Foauth"))
        #expect(request.formFields["redirect_uri"] == "icachebox://oauth")
    }
}

// MARK: - Step 4: the answer

@Suite("Token-Antwort")
struct TokenResponseTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// The example of the documentation.
    @Test func readsTheDocumentedAnswer() throws {
        let json = """
        {"access_token":"AAAA-token","token_type":"bearer","expires_in":3599,"refresh_token":"BBBB-refresh"}
        """
        let tokens = try GeocachingOAuth.tokens(fromResponse: Data(json.utf8), status: 200, now: Self.now)
        #expect(tokens.accessToken == "AAAA-token")
        #expect(tokens.refreshToken == "BBBB-refresh")
        #expect(tokens.tokenType == "bearer")
        #expect(tokens.expiresAt == Self.now.addingTimeInterval(3599))
        #expect(tokens.authorizationHeader == "bearer AAAA-token")
        #expect(tokens.isValid(at: Self.now))
        #expect(!tokens.isValid(at: Self.now.addingTimeInterval(3599)))
        // The last minute does not count any more, so that a running request does not die on the way.
        #expect(!tokens.isValid(at: Self.now.addingTimeInterval(3550)))
    }

    /// Without `expires_in` one hour is assumed.
    @Test func assumesAnHourWithoutExpiry() throws {
        let json = #"{"access_token":"a","refresh_token":"b"}"#
        let tokens = try GeocachingOAuth.tokens(fromResponse: Data(json.utf8), status: 200, now: Self.now)
        #expect(tokens.expiresAt == Self.now.addingTimeInterval(3600))
        #expect(tokens.tokenType == "bearer")
    }

    /// An error answer keeps `error` and `error_description`.
    @Test func readsAnErrorAnswer() {
        let json = #"{"error":"invalid_grant","error_description":"Code already used"}"#
        #expect(throws: GeocachingAuthError.tokenEndpoint(status: 400,
                                                          error: "invalid_grant",
                                                          description: "Code already used")) {
            _ = try GeocachingOAuth.tokens(fromResponse: Data(json.utf8), status: 400, now: Self.now)
        }
    }

    /// An HTML error page does not crash anything and lands in the message, shortened.
    @Test func survivesAnHTMLErrorPage() {
        let html = "<html><body>" + String(repeating: "x", count: 5000) + "</body></html>"
        do {
            _ = try GeocachingOAuth.tokens(fromResponse: Data(html.utf8), status: 500, now: Self.now)
            Issue.record("sollte werfen")
        } catch let error as GeocachingAuthError {
            guard case .tokenEndpoint(let status, _, let description) = error else {
                Issue.record("falscher Fehler: \(error)")
                return
            }
            #expect(status == 500)
            #expect(description.count <= 200)
        } catch {
            Issue.record("falscher Fehler: \(error)")
        }
    }

    /// 200 with rubbish in it is an error too.
    @Test func refusesAnAnswerWithoutToken() {
        #expect(throws: GeocachingAuthError.invalidTokenResponse("{\"foo\":1}")) {
            _ = try GeocachingOAuth.tokens(fromResponse: Data(#"{"foo":1}"#.utf8), status: 200, now: Self.now)
        }
    }

    /// Tokens survive the trip through the keychain unchanged.
    @Test func surviveEncoding() throws {
        let tokens = GeocachingTokens(accessToken: "a", refreshToken: "b", expiresAt: Self.now)
        let data = try JSONEncoder().encode(tokens)
        #expect(try JSONDecoder().decode(GeocachingTokens.self, from: data) == tokens)
    }
}

private extension String {
    /// A verifier of the shortest allowed length.
    var padded: String { self + String(repeating: "a", count: 43 - count) }
}
