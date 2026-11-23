import Foundation

/// A rating of GCVote for one cache (Cachebox `RatingData`, which keeps only `voteAvg` and `voteUser`).
///
/// GCVote rates from 1 to 5 in half steps; 0 means "not rated yet".
public struct GCVoteRating: Equatable, Sendable {
    /// GC code of the cache (`waypoint` in the answer).
    public var waypoint: String
    /// Average of all votes (`voteAvg`), 0 without any vote.
    public var average: Double
    /// How many have voted (`voteCnt`); GCVote does not always send it.
    public var count: Int
    /// Median of the votes (`voteMedian`), if sent. Not used in the app, kept because the answer has it.
    public var median: Double?
    /// The vote of the signed-in user (`voteUser`), `nil` if they have not voted or no user was sent.
    public var ownVote: Double?

    public init(waypoint: String, average: Double, count: Int = 0, median: Double? = nil, ownVote: Double? = nil) {
        self.waypoint = waypoint
        self.average = average
        self.count = count
        self.median = median
        self.ownVote = ownVote
    }

    /// Somebody has rated this cache.
    public var isRated: Bool { average > 0 }
}

/// User name (the geocaching.com login) and GCVote password. Only needed for the user's own vote - the averages
/// come without a login, as in Cachebox, which also sends empty values when no password is set.
public struct GCVoteCredentials: Equatable, Sendable {
    public var username: String
    public var password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    /// Nothing to send: the request then asks anonymously for the averages.
    public var isEmpty: Bool {
        username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty
    }
}

public enum GCVoteError: Error, LocalizedError, Equatable {
    /// 410: the address is switched off. gcvote.com has answered this way for every path since (at least) 2025.
    case gone(host: String)
    case http(status: Int, message: String)
    /// The answer is no GCVote XML (an error page, HTML, empty …); `detail` is its beginning.
    case unreadable(String)
    case invalidURL(String)

    public var errorDescription: String? {
        switch self {
        case .gone(let host):
            "\(host) gibt es nicht mehr (HTTP 410). Der GCVote-Dienst ist abgeschaltet; "
                + "unter „Server“ lässt sich eine andere Adresse eintragen."
        case .http(let status, let message):
            message.isEmpty ? "GCVote antwortet mit Fehler \(status)" : "GCVote: \(message)"
        case .unreadable(let detail):
            "Antwort von GCVote nicht lesbar (\(detail))"
        case .invalidURL(let text):
            "„\(text)“ ist keine gültige Serveradresse"
        }
    }
}

/// Asks GCVote for the ratings of caches (Cachebox `GCVote.getRating`).
///
/// `GET <server>/getVotes.php?userName=…&password=…&waypoints=GC1,GC2,…` answers with XML:
/// `<votes><vote waypoint="GC1" voteAvg="3.5" voteCnt="12" voteMedian="4" voteUser="4" …/>…</votes>`.
/// Cachebox reads `voteAvg` and `voteUser` from it; `voteCnt` and `voteMedian` are read here as well.
///
/// The server is a setting, because gcvote.com itself is gone (HTTP 410 for every path, its mirror
/// `ssl.webpack.de/gcvote.com` does not answer either). Whoever runs a copy or a compatible successor can enter
/// its address; everything else stays as it was.
///
/// Uploading the user's own vote (Cachebox `GCVote.sendVote`) is not here: the app only reads ratings.
public struct GCVoteService: Sendable {
    public static let defaultServer = "http://gcvote.com"
    /// Cachebox asks for 100 caches per request (`Importer.importGcVote`, `packageSize`).
    public static let waypointsPerRequest = 100

    public let server: String
    private let http: any GeocachingHTTPClient

    public init(server: String = GCVoteService.defaultServer,
                http: any GeocachingHTTPClient = GeocachingURLSessionClient()) {
        self.server = server
        self.http = http
    }

    /// The ratings of up to `waypointsPerRequest` caches. Caches GCVote does not know are missing from the answer.
    public func ratings(waypoints: [String], credentials: GCVoteCredentials? = nil) async throws -> [GCVoteRating] {
        guard !waypoints.isEmpty else { return [] }
        let request = URLRequest(url: try url(waypoints: waypoints, credentials: credentials))
        let (data, response) = try await http.send(request)
        switch response.statusCode {
        case 200...299:
            return try Self.parse(data)
        case 410:
            throw GCVoteError.gone(host: response.url?.host() ?? server)
        default:
            throw GCVoteError.http(status: response.statusCode, message: GeocachingOAuth.snippet(of: data))
        }
    }

    /// The request URL; the values are percent encoded (Cachebox pastes them in unencoded).
    func url(waypoints: [String], credentials: GCVoteCredentials?) throws -> URL {
        let text = server.contains("://") ? server : "http://" + server
        guard var components = URLComponents(string: text.hasSuffix("/") ? String(text.dropLast()) : text),
              components.host?.isEmpty == false else {
            throw GCVoteError.invalidURL(server)
        }
        components.path += "/getVotes.php"
        var query = [URLQueryItem(name: "version", value: "iCacheBox")]
        if let credentials, !credentials.isEmpty {
            query.append(URLQueryItem(name: "userName", value: credentials.username))
            query.append(URLQueryItem(name: "password", value: credentials.password))
        }
        query.append(URLQueryItem(name: "waypoints", value: waypoints.joined(separator: ",")))
        components.queryItems = query
        guard let url = components.url else { throw GCVoteError.invalidURL(server) }
        return url
    }

    /// Reads the `vote` elements of a GCVote answer.
    public static func parse(_ data: Data) throws -> [GCVoteRating] {
        let parser = GCVoteXMLParser()
        guard parser.parse(data) else { throw GCVoteError.unreadable(GeocachingOAuth.snippet(of: data)) }
        return parser.ratings
    }
}

/// Collects the attributes of the `vote` elements; GCVote answers with one flat element per cache.
final class GCVoteXMLParser: NSObject, XMLParserDelegate {
    private(set) var ratings: [GCVoteRating] = []
    private var sawVotes = false

    func parse(_ data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { return false }
        // an XML document without a single GCVote element is not a GCVote answer
        return sawVotes || !ratings.isEmpty
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        switch element.lowercased() {
        case "votes":
            sawVotes = true
        case "vote":
            // keys are case sensitive in the answer, but a copy of the service may differ
            func value(_ name: String) -> String? {
                attributes[name] ?? attributes.first { $0.key.lowercased() == name.lowercased() }?.value
            }
            guard let waypoint = value("waypoint")?.trimmingCharacters(in: .whitespaces), !waypoint.isEmpty else {
                return
            }
            let own = value("voteUser").flatMap { Self.number($0) }
            ratings.append(GCVoteRating(waypoint: waypoint.uppercased(),
                                        average: value("voteAvg").flatMap { Self.number($0) } ?? 0,
                                        count: value("voteCnt").flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 0,
                                        median: value("voteMedian").flatMap { Self.number($0) },
                                        ownVote: (own ?? 0) > 0 ? own : nil))
        default:
            break
        }
    }

    /// GCVote writes "3.5000"; an empty text means "no value" (Cachebox: `userVote.length() == 0`).
    static func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }
}
