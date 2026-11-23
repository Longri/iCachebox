import CryptoKit
import Foundation
import Network
import Testing
import os
@testable import CacheboxCore

// The sign-in once through the real network stack: an HTTP server on localhost plays geocaching.com and
// checks what arrives - PKCE, consumer key and secret, redirect URI, the bearer header. The tests with the
// stub above check the single pieces; this one checks that they fit together.

// MARK: - A very small HTTP server

/// Lets exactly one caller through - the state handler may report `.ready` and `.failed` several times.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func fire() -> Bool {
        lock.withLock {
            if fired { return false }
            fired = true
            return true
        }
    }
}

/// Answers HTTP/1.1 requests on 127.0.0.1 and closes the connection afterwards. Enough for a test.
final class TinyHTTPServer: @unchecked Sendable {
    struct Request {
        var method: String
        var path: String
        var query: [String: String]
        var headers: [String: String]
        var body: Data

        /// The fields of an `application/x-www-form-urlencoded` body.
        var form: [String: String] {
            Self.fields(in: String(decoding: body, as: UTF8.self))
        }

        static func fields(in text: String) -> [String: String] {
            var fields: [String: String] = [:]
            for pair in text.split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { continue }
                let name = String(parts[0]).removingPercentEncoding ?? String(parts[0])
                fields[name] = String(parts[1]).removingPercentEncoding ?? String(parts[1])
            }
            return fields
        }
    }

    struct Response {
        var status: Int = 200
        var json: String = "{}"
        /// The GCVote test answers XML; everything else keeps JSON.
        var contentType = "application/json"
    }

    private let listener: NWListener
    private let handler: @Sendable (Request) -> Response
    private let queue = DispatchQueue(label: "TinyHTTPServer")
    private(set) var port: UInt16 = 0

    init(handler: @escaping @Sendable (Request) -> Response) throws {
        self.handler = handler
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters, on: .any)
    }

    /// Starts listening and returns once the port is known.
    func start() async throws {
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let once = Once()
            listener.stateUpdateHandler = { [weak listener] state in
                switch state {
                case .ready:
                    if once.fire() { continuation.resume(returning: listener?.port?.rawValue ?? 0) }
                case .failed(let error):
                    if once.fire() { continuation.resume(throwing: error) }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
        }
        self.port = port
    }

    func stop() {
        listener.cancel()
    }

    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        read(connection, buffer: Data())
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if error != nil {
                connection.cancel()
                return
            }
            if let request = Self.parse(buffer) {
                let response = handler(request)
                send(response, on: connection)
            } else if isComplete {
                connection.cancel()
            } else {
                read(connection, buffer: buffer)
            }
        }
    }

    /// nil while head or body are still incomplete.
    private static func parse(_ buffer: Data) -> Request? {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = buffer.range(of: separator) else { return nil }
        let head = String(decoding: buffer[..<range.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] =
                line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let body = buffer[range.upperBound...]
        let expected = Int(headers["content-length"] ?? "0") ?? 0
        guard body.count >= expected else { return nil }

        let target = String(requestLine[1])
        let components = URLComponents(string: "http://127.0.0.1" + target)
        return Request(method: String(requestLine[0]),
                       path: components?.path ?? target,
                       query: Request.fields(in: components?.percentEncodedQuery ?? ""),
                       headers: headers,
                       body: Data(body.prefix(expected)))
    }

    private func send(_ response: Response, on connection: NWConnection) {
        let body = Data(response.json.utf8)
        let head = """
        HTTP/1.1 \(response.status) \(response.status == 200 ? "OK" : "Error")\r
        Content-Type: \(response.contentType)\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r

        """
        connection.send(content: Data(head.utf8) + body,
                        completion: .contentProcessed { _ in connection.cancel() })
    }
}

// MARK: - The fake geocaching.com

/// Plays the three endpoints the sign-in needs and remembers what it was asked.
final class FakeGeocaching: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: State())

    struct State {
        var challengeOfCode: [String: String] = [:]
        var accessToken = ""
        var refreshToken = ""
        var paths: [String] = []
        var complaints: [String] = []
        var refreshes = 0
    }

    let clientID = "12345"
    let clientSecret = "s3cr3t"
    let redirectURI = "icachebox://oauth"

    var requestedPaths: [String] { state.withLock { $0.paths } }
    var complaints: [String] { state.withLock { $0.complaints } }
    var refreshCount: Int { state.withLock { $0.refreshes } }

    private func complain(_ text: String) {
        state.withLock { $0.complaints.append(text) }
    }

    func handle(_ request: TinyHTTPServer.Request) -> TinyHTTPServer.Response {
        state.withLock { $0.paths.append("\(request.method) \(request.path)") }
        switch (request.method, request.path) {
        case ("GET", "/oauth/authorize.aspx"): return authorize(request)
        case ("POST", "/token"): return token(request)
        case ("GET", "/v1/users/me"): return me(request)
        default: return .init(status: 404, json: #"{"error":"unknown"}"#)
        }
    }

    /// The browser step. Instead of a redirect to a custom scheme (which `URLSession` cannot follow) the
    /// callback URL comes back as JSON; the test then hands it to `completeSignIn`, exactly like
    /// `ASWebAuthenticationSession` does.
    private func authorize(_ request: TinyHTTPServer.Request) -> TinyHTTPServer.Response {
        let query = request.query.mapValues { $0.removingPercentEncoding ?? $0 }
        if query["client_id"] != clientID { complain("client_id: \(query["client_id"] ?? "-")") }
        if query["response_type"] != "code" { complain("response_type: \(query["response_type"] ?? "-")") }
        if query["scope"] != "*" { complain("scope: \(query["scope"] ?? "-")") }
        if query["redirect_uri"] != redirectURI { complain("redirect_uri: \(query["redirect_uri"] ?? "-")") }
        if query["code_challenge_method"] != "S256" { complain("code_challenge_method") }
        guard let challenge = query["code_challenge"], !challenge.isEmpty else {
            complain("code_challenge fehlt")
            return .init(status: 400, json: #"{"error":"invalid_request"}"#)
        }
        guard let returnedState = query["state"], !returnedState.isEmpty else {
            complain("state fehlt")
            return .init(status: 400, json: #"{"error":"invalid_request"}"#)
        }
        let code = "code-\(UUID().uuidString.prefix(8))"
        state.withLock { $0.challengeOfCode[code] = challenge }
        let callback = "\(redirectURI)?code=\(code)&state=\(returnedState)"
        return .init(json: #"{"callback":"\#(callback)"}"#)
    }

    private func token(_ request: TinyHTTPServer.Request) -> TinyHTTPServer.Response {
        let form = request.form
        guard request.headers["content-type"]?.hasPrefix("application/x-www-form-urlencoded") == true else {
            complain("Content-Type: \(request.headers["content-type"] ?? "-")")
            return .init(status: 400, json: #"{"error":"invalid_request"}"#)
        }
        if form["client_id"] != clientID { complain("token client_id") }
        if form["client_secret"] != clientSecret { complain("token client_secret") }
        if form["redirect_uri"] != redirectURI { complain("token redirect_uri: \(form["redirect_uri"] ?? "-")") }

        switch form["grant_type"] {
        case "authorization_code":
            guard let code = form["code"], let challenge = state.withLock({ $0.challengeOfCode[code] }) else {
                complain("unbekannter Code")
                return .init(status: 400, json: #"{"error":"invalid_grant"}"#)
            }
            guard let verifier = form["code_verifier"], Self.challenge(for: verifier) == challenge else {
                complain("PKCE passt nicht")
                return .init(status: 400, json: #"{"error":"invalid_grant","error_description":"PKCE"}"#)
            }
            return issue(expiresIn: 3599)
        case "refresh_token":
            guard form["refresh_token"] == state.withLock({ $0.refreshToken }) else {
                complain("falscher Refresh-Token")
                return .init(status: 400, json: #"{"error":"invalid_grant"}"#)
            }
            state.withLock { $0.refreshes += 1 }
            return issue(expiresIn: 3599)
        default:
            complain("grant_type: \(form["grant_type"] ?? "-")")
            return .init(status: 400, json: #"{"error":"unsupported_grant_type"}"#)
        }
    }

    private func issue(expiresIn: Int) -> TinyHTTPServer.Response {
        let access = "access-\(UUID().uuidString.prefix(8))"
        let refresh = "refresh-\(UUID().uuidString.prefix(8))"
        state.withLock {
            $0.accessToken = access
            $0.refreshToken = refresh
        }
        return .init(json: """
        {"access_token":"\(access)","token_type":"bearer","expires_in":\(expiresIn),"refresh_token":"\(refresh)"}
        """)
    }

    private func me(_ request: TinyHTTPServer.Request) -> TinyHTTPServer.Response {
        let expected = "bearer " + state.withLock { $0.accessToken }
        guard request.headers["authorization"] == expected else {
            return .init(status: 401, json: #"{"errorMessage":"Token expired"}"#)
        }
        if request.query["fields"] == nil { complain("fields fehlt") }
        return .init(json: """
        {"referenceCode":"PR1ZE","username":"Longri","findCount":4711,"hideCount":42,
         "favoritePoints":17,"membershipLevelId":3,"joinedDateUtc":"2010-11-21T00:00:00"}
        """)
    }

    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - The test

@Suite("Anmeldung von Anfang bis Ende", .serialized)
struct GeocachingEndToEndTests {
    /// Sign in, read the user, let the token expire, read again - all over real HTTP.
    @Test func signsInReadsTheUserAndRefreshes() async throws {
        let geocaching = FakeGeocaching()
        let server = try TinyHTTPServer { geocaching.handle($0) }
        try await server.start()
        defer { server.stop() }

        let base = server.baseURL
        let credentials = GeocachingCredentials(
            clientID: geocaching.clientID,
            clientSecret: geocaching.clientSecret,
            redirectURI: geocaching.redirectURI,
            environment: GeocachingEnvironment(authorizationURL: base.appending(path: "/oauth/authorize.aspx"),
                                               tokenURL: base.appending(path: "/token"),
                                               apiBaseURL: base))
        let clock = TestClock()
        let store = GeocachingMemoryTokenStore()
        let authenticator = GeocachingAuthenticator(credentials: credentials, store: store,
                                                    clock: { clock.now })
        let api = GeocachingAPI(authenticator: authenticator)

        // 1. The page the browser would show.
        let authorization = try await authenticator.authorization()
        let (data, _) = try await URLSession.shared.data(from: authorization.url)
        struct Page: Decodable { var callback: String }
        let callback = try #require(URL(string: try JSONDecoder().decode(Page.self, from: data).callback))

        // 2. The callback becomes tokens - the server checks key, secret, redirect and PKCE.
        let tokens = try await authenticator.completeSignIn(callback: callback, authorization: authorization)
        #expect(tokens.accessToken.hasPrefix("access-"))
        #expect(try store.load() == tokens)

        // 3. A call with the bearer token.
        let user = try await api.me()
        #expect(user.username == "Longri")
        #expect(user.findCount == 4711)
        #expect(user.membership == .premium)

        // 4. An hour later the token is stale: refresh without anybody asking for it, then the call again.
        clock.advance(3600)
        let again = try await api.me()
        #expect(again.username == "Longri")
        #expect(geocaching.refreshCount == 1)
        #expect(try store.load()?.accessToken != tokens.accessToken)

        #expect(geocaching.complaints.isEmpty, "Server hat etwas zu meckern: \(geocaching.complaints)")
        #expect(geocaching.requestedPaths == ["GET /oauth/authorize.aspx", "POST /token",
                                               "GET /v1/users/me", "POST /token", "GET /v1/users/me"])
    }

    /// A token the server has dropped early: the 401 is answered with a refresh and one repeat.
    @Test func repeatsAfterAnUnexpected401() async throws {
        let geocaching = FakeGeocaching()
        let server = try TinyHTTPServer { geocaching.handle($0) }
        try await server.start()
        defer { server.stop() }

        let base = server.baseURL
        let credentials = GeocachingCredentials(
            clientID: geocaching.clientID,
            clientSecret: geocaching.clientSecret,
            redirectURI: geocaching.redirectURI,
            environment: GeocachingEnvironment(authorizationURL: base.appending(path: "/oauth/authorize.aspx"),
                                               tokenURL: base.appending(path: "/token"),
                                               apiBaseURL: base))
        let clock = TestClock()
        let store = GeocachingMemoryTokenStore()
        let authenticator = GeocachingAuthenticator(credentials: credentials, store: store,
                                                    clock: { clock.now })
        let api = GeocachingAPI(authenticator: authenticator)

        let authorization = try await authenticator.authorization()
        let (data, _) = try await URLSession.shared.data(from: authorization.url)
        struct Page: Decodable { var callback: String }
        let callback = try #require(URL(string: try JSONDecoder().decode(Page.self, from: data).callback))
        try await authenticator.completeSignIn(callback: callback, authorization: authorization)

        // The token in the app is still "valid", but the server no longer knows it.
        var stale = try #require(try store.load())
        stale.accessToken = "veraltet"
        try store.save(stale)
        let fresh = GeocachingAuthenticator(credentials: credentials, store: store, clock: { clock.now })
        let staleAPI = GeocachingAPI(authenticator: fresh)

        let user = try await staleAPI.me()
        #expect(user.username == "Longri")
        #expect(geocaching.refreshCount == 1)
        #expect(geocaching.requestedPaths.suffix(3) == ["GET /v1/users/me", "POST /token", "GET /v1/users/me"])
        #expect(geocaching.complaints.isEmpty, "Server hat etwas zu meckern: \(geocaching.complaints)")
    }
}
