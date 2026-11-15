import Foundation

/// What the REST API answers with when it is unhappy.
public enum GeocachingAPIError: Error, LocalizedError, Equatable {
    /// Any other status code; `message` is what the server wrote.
    case http(status: Int, message: String)
    /// 429: 60 calls per minute and method, 1200 per consumer key, 6000 per IP.
    case rateLimited(retryAfter: TimeInterval?)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .http(let status, let message):
            message.isEmpty ? "Geocaching.com antwortet mit Fehler \(status)" : "Geocaching.com: \(message)"
        case .rateLimited(let retryAfter):
            if let retryAfter {
                "Zu viele Anfragen an Geocaching.com – in \(Int(retryAfter.rounded())) s wieder versuchen"
            } else {
                "Zu viele Anfragen an Geocaching.com – später wieder versuchen"
            }
        case .decoding(let detail):
            "Antwort von Geocaching.com nicht lesbar (\(detail))"
        }
    }
}

/// Membership level of a user (`membershipLevelId` of the API).
public enum GeocachingMembership: Int, Sendable, Equatable {
    case unknown = 0
    case basic = 1
    case charter = 2
    case premium = 3

    public init(id: Int?) {
        self = GeocachingMembership(rawValue: id ?? 0) ?? .unknown
    }

    /// Charter members have the same rights as premium members (Cachebox: `isPremiumMember`).
    public var isPremium: Bool { self == .premium || self == .charter }

    public var name: String {
        switch self {
        case .unknown: "Unbekannt"
        case .basic: "Basic"
        case .charter: "Charter"
        case .premium: "Premium"
        }
    }
}

/// The signed-in user, from `GET /v1/users/me`.
public struct GeocachingUser: Decodable, Equatable, Sendable {
    public var referenceCode: String
    public var username: String
    public var findCount: Int
    public var hideCount: Int
    public var favoritePoints: Int
    public var membershipLevelId: Int
    /// As the API writes it, e.g. `2010-11-21T00:00:00`.
    public var joinedDateUtc: String?

    public var membership: GeocachingMembership { GeocachingMembership(id: membershipLevelId) }

    public var joinedDate: Date? {
        guard let joinedDateUtc else { return nil }
        return GeocachingUser.parseDate(joinedDateUtc)
    }

    /// The fields the app asks for - the API only sends what is listed in `fields`.
    public static let defaultFields = ["referenceCode", "username", "findCount", "hideCount",
                                       "favoritePoints", "membershipLevelId", "joinedDateUtc"]

    public init(referenceCode: String = "", username: String = "", findCount: Int = 0, hideCount: Int = 0,
                favoritePoints: Int = 0, membershipLevelId: Int = 0, joinedDateUtc: String? = nil) {
        self.referenceCode = referenceCode
        self.username = username
        self.findCount = findCount
        self.hideCount = hideCount
        self.favoritePoints = favoritePoints
        self.membershipLevelId = membershipLevelId
        self.joinedDateUtc = joinedDateUtc
    }

    enum CodingKeys: String, CodingKey {
        case referenceCode, username, findCount, hideCount, favoritePoints, membershipLevelId, joinedDateUtc
    }

    /// Lenient on purpose: the API only sends the fields that were asked for, and a missing one must not
    /// make the whole answer unreadable.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        referenceCode = try container.decodeIfPresent(String.self, forKey: .referenceCode) ?? ""
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        findCount = try container.decodeIfPresent(Int.self, forKey: .findCount) ?? 0
        hideCount = try container.decodeIfPresent(Int.self, forKey: .hideCount) ?? 0
        favoritePoints = try container.decodeIfPresent(Int.self, forKey: .favoritePoints) ?? 0
        membershipLevelId = try container.decodeIfPresent(Int.self, forKey: .membershipLevelId) ?? 0
        joinedDateUtc = try container.decodeIfPresent(String.self, forKey: .joinedDateUtc)
    }

    /// The API writes UTC without a zone (`2010-11-21T00:00:00`) and sometimes with fractions.
    static func parseDate(_ text: String) -> Date? {
        let formats = ["yyyy-MM-dd'T'HH:mm:ss.SSSSSSS", "yyyy-MM-dd'T'HH:mm:ss.SSS",
                       "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let trimmed = text.hasSuffix("Z") ? String(text.dropLast()) : text
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }
}

/// Minimal client for the Geocaching API: puts the token on a request, repeats it once after a 401 and turns
/// the JSON into Swift types. Cachebox does the same in `GroundspeakAPI`.
public struct GeocachingAPI: Sendable {
    public let authenticator: GeocachingAuthenticator
    private let http: any GeocachingHTTPClient

    public init(authenticator: GeocachingAuthenticator,
                http: any GeocachingHTTPClient = GeocachingURLSessionClient()) {
        self.authenticator = authenticator
        self.http = http
    }

    /// The signed-in user. Also the cheapest way to see whether a token still works.
    public func me(fields: [String] = GeocachingUser.defaultFields) async throws -> GeocachingUser {
        let data = try await get("/v1/users/me",
                                 query: [URLQueryItem(name: "fields", value: fields.joined(separator: ","))])
        do {
            return try JSONDecoder().decode(GeocachingUser.self, from: data)
        } catch {
            throw GeocachingAPIError.decoding(GeocachingOAuth.snippet(of: data))
        }
    }

    /// `GET` on the API. An expired token is refreshed beforehand; a 401 is tried once more with a fresh one,
    /// because the server may have thrown the token away early.
    public func get(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        let url = try requestURL(path: path, query: query)
        return try await send(URLRequest(url: url), retryAfterUnauthorized: true)
    }

    private func requestURL(path: String, query: [URLQueryItem]) throws -> URL {
        let base = authenticatorEnvironment.apiBaseURL
        guard var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw GeocachingAPIError.http(status: 0, message: "Ungültige URL")
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else {
            throw GeocachingAPIError.http(status: 0, message: "Ungültige URL")
        }
        return url
    }

    private var authenticatorEnvironment: GeocachingEnvironment {
        // `credentials` is a `let` of the actor and may be read without awaiting.
        authenticator.credentials.environment
    }

    private func send(_ request: URLRequest, retryAfterUnauthorized: Bool) async throws -> Data {
        let signed = try await authenticator.authorized(request)
        let (data, response) = try await http.send(signed)
        switch response.statusCode {
        case 200...299:
            return data
        case 401 where retryAfterUnauthorized:
            _ = try await authenticator.refresh()
            return try await send(request, retryAfterUnauthorized: false)
        case 429:
            throw GeocachingAPIError.rateLimited(retryAfter: Self.retryAfter(from: response))
        default:
            throw GeocachingAPIError.http(status: response.statusCode,
                                          message: Self.message(from: data, status: response.statusCode))
        }
    }

    /// Seconds until the next try, out of `Retry-After` or `x-rate-limit-reset`.
    static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        for header in ["Retry-After", "x-rate-limit-reset"] {
            if let value = response.value(forHTTPHeaderField: header), let seconds = TimeInterval(value) {
                return seconds
            }
        }
        return nil
    }

    /// `errorMessage` of the API, else the beginning of the answer.
    static func message(from data: Data, status: Int) -> String {
        struct Body: Decodable {
            var errorMessage: String?
            var message: String?
            var statusMessage: String?
        }
        if let body = try? JSONDecoder().decode(Body.self, from: data),
           let message = body.errorMessage ?? body.message ?? body.statusMessage, !message.isEmpty {
            return message
        }
        return GeocachingOAuth.snippet(of: data)
    }
}
