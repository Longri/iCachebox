import Foundation

/// One record read from a GPX file.
public enum GPXRecord: Sendable {
    /// A geocache with its logs and trackables (`<wpt>` with a `<groundspeak:cache>` element).
    case cache(Geocache, logs: [CacheLog], trackables: [Trackable])
    /// An additional waypoint belonging to a cache (parking, stage, …), e.g. from a "-wpts.gpx" file.
    case waypoint(Waypoint)
}

/// Streaming parser for geocaching GPX files.
///
/// Understands GPX 1.0 and 1.1 with the Groundspeak cache extension (versions 1.0, 1.0.1 and 1.0.2, as written by
/// pocket queries, the geocaching.com GPX download, GSAK, c:geo and Opencaching) plus the GSAK waypoint extension.
/// Element names are matched without namespace prefix, so both `<groundspeak:cache>` inside `<wpt>` (GPX 1.0) and
/// inside `<extensions>` (GPX 1.1) work. Waypoints without cache data become additional waypoints: their cache is
/// taken from `<gsak:Parent>` or, as in pocket queries, from the code ("PK1A2B3" belongs to "GC1A2B3").
public final class GPXParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private let onRecord: (GPXRecord) -> Void
    private var error: Error?

    // state of the current <wpt>
    private var inWaypoint = false
    private var waypointAttributes: [String: String] = [:]
    private var fields: [String: String] = [:]        // direct children of <wpt> (name, desc, sym, type, cmt, url, …)
    private var cacheFields: [String: String] = [:]   // children of <cache>
    private var cacheAttributes: [String: String] = [:]
    private var inCache = false
    private var gsakFields: [String: String] = [:]
    private var inGSAK = false
    private var attributes: [CacheAttribute] = []
    private var logs: [CacheLog] = []
    private var currentLog: [String: String]?
    private var trackables: [Trackable] = []
    private var currentTrackable: [String: String]?
    private var path: [String] = []
    /// Attributes of the open elements, parallel to `path`.
    private var attributeStack: [[String: String]] = []
    private var text = ""
    /// Attributes of the element that is ending (valid in `didEndElement`).
    private var textAttributes: [String: String] { attributeStack.last ?? [:] }
    private var parent: String? { path.count >= 2 ? path[path.count - 2] : nil }

    /// Parses `data` and calls `onRecord` for each cache and waypoint in document order.
    public init(data: Data, onRecord: @escaping (GPXRecord) -> Void) {
        parser = XMLParser(data: data)
        self.onRecord = onRecord
        super.init()
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
    }

    public func parse() throws {
        guard parser.parse() else {
            throw error ?? GPXError("GPX nicht lesbar (Zeile \(parser.lineNumber)): "
                                    + (parser.parserError?.localizedDescription ?? "unbekannter Fehler"))
        }
    }

    public func abort() { parser.abortParsing() }

    // MARK: XMLParserDelegate

    public func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                       qualifiedName: String?, attributes: [String: String] = [:]) {
        let local = name.lowercased()
        path.append(local)
        attributeStack.append(attributes)
        text = ""
        switch local {
        case "wpt" where !inWaypoint:
            inWaypoint = true
            waypointAttributes = attributes
            fields = [:]
            cacheFields = [:]
            cacheAttributes = [:]
            gsakFields = [:]
            self.attributes = []
            logs = []
            trackables = []
        case "cache" where inWaypoint && !inCache:
            inCache = true
            cacheAttributes = attributes
        case "wptextension" where inWaypoint:
            inGSAK = true
        case "log" where inCache:
            currentLog = ["id": attributes["id"] ?? ""]
        case "travelbug" where inCache:
            currentTrackable = ["ref": attributes["ref"] ?? "", "id": attributes["id"] ?? ""]
        case "attribute" where inCache:
            break   // id/inc are read at the end of the element
        default:
            break
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    public func parser(_ parser: XMLParser, foundCDATA block: Data) {
        text += String(decoding: block, as: UTF8.self)
    }

    public func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let local = name.lowercased()
        defer {
            if !path.isEmpty { path.removeLast() }
            if !attributeStack.isEmpty { attributeStack.removeLast() }
            text = ""
        }
        guard inWaypoint else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if var log = currentLog {
            switch local {
            case "log":
                finishLog(log)
                currentLog = nil
            case "text":
                log["text"] = text   // keep line breaks inside log texts
                log["encoded"] = textAttributes["encoded"]
                currentLog = log
            case "finder":
                log["finder"] = value
                currentLog = log
            default:
                log[local] = value
                currentLog = log
            }
            return
        }
        if var trackable = currentTrackable {
            if local == "travelbug" {
                let code = trackable["ref"].flatMap { $0.isEmpty ? nil : $0 } ?? "TB" + (trackable["id"] ?? "")
                trackables.append(Trackable(code: code, name: trackable["name"] ?? code, cacheCode: ""))
                currentTrackable = nil
            } else {
                trackable[local] = value
                currentTrackable = trackable
            }
            return
        }

        switch local {
        case "wpt":
            finishWaypoint()
            inWaypoint = false
        case "cache" where inCache:
            inCache = false
        case "wptextension":
            inGSAK = false
        case "attribute" where inCache:
            if let id = Int(textAttributes["id"] ?? "") {
                let positive = (textAttributes["inc"] ?? "1") != "0"
                attributes.append(CacheAttribute(id: id, isPositive: positive, name: value))
            }
        case "short_description", "long_description":
            cacheFields[local] = text
            cacheFields[local + "_html"] = textAttributes["html"]
        case "link" where parent == "wpt":
            // GPX 1.1: <link href="…"><text>…</text></link> instead of <url>/<urlname>
            if fields["url"] == nil { fields["url"] = textAttributes["href"] }
        case "text" where parent == "link":
            if fields["urlname"] == nil { fields["urlname"] = value }
        default:
            if inCache {
                // "name" and "owner"-like elements of logs and trackables were handled above
                if cacheFields[local] == nil { cacheFields[local] = value }
            } else if inGSAK {
                gsakFields[local] = value
            } else if parent == "wpt" {
                fields[local] = value
            }
        }
    }

    public func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        error = error ?? parseError
    }

    // MARK: Records

    private func finishLog(_ log: [String: String]) {
        var text = log["text"] ?? ""
        if (log["encoded"] ?? "").lowercased() == "true" { text = GPXParser.rot13(text) }
        let date = log["date"].flatMap(GPXParser.parseDate)
        let id = (log["id"] ?? "").isEmpty ? "\(log["finder"] ?? "")-\(log["date"] ?? "")-\(logs.count)" : log["id"]!
        logs.append(CacheLog(id: id, cacheCode: "", date: date, type: LogType(gpxName: log["type"] ?? ""),
                             finder: log["finder"] ?? "", text: text.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    private func finishWaypoint() {
        guard let code = fields["name"]?.trimmingCharacters(in: .whitespaces), !code.isEmpty else { return }
        let lat = Double(waypointAttributes["lat"] ?? "") ?? 0
        let lon = Double(waypointAttributes["lon"] ?? "") ?? 0
        let coordinate = Coordinate(latitude: lat, longitude: lon)

        if !cacheAttributes.isEmpty || !cacheFields.isEmpty {
            onRecord(makeCache(code: code, coordinate: coordinate))
            return
        }
        // a plain waypoint: an additional waypoint of a cache, or a cache without Groundspeak data
        let type = fields["type"] ?? ""
        if type.lowercased().hasPrefix("geocache") {
            var cache = Geocache(code: code, name: fields["urlname"] ?? fields["desc"] ?? code, coordinate: coordinate,
                                 type: CacheType(gpxName: type.components(separatedBy: "|").last ?? ""))
            cache.isFound = (fields["sym"] ?? "").lowercased() == "geocache found"
            cache.url = fields["url"] ?? ""
            cache.hidden = fields["time"].flatMap(GPXParser.parseDate)
            onRecord(.cache(cache, logs: [], trackables: []))
            return
        }
        guard let parent = gsakFields["parent"].flatMap({ $0.isEmpty ? nil : $0 }) ?? GPXParser.parentCode(of: code)
        else { return }
        let waypoint = Waypoint(code: code, cacheCode: parent,
                                title: fields["desc"] ?? fields["urlname"] ?? code,
                                comment: fields["cmt"] ?? "",
                                type: WaypointType(gpxName: fields["sym"] ?? type),
                                coordinate: coordinate.isValid ? coordinate : nil)
        onRecord(.waypoint(waypoint))
    }

    private func makeCache(code: String, coordinate: Coordinate) -> GPXRecord {
        let sym = (fields["sym"] ?? "").lowercased()
        let typeName = cacheFields["type"] ?? fields["type"]?.components(separatedBy: "|").last ?? ""
        var cache = Geocache(code: code,
                             name: cacheFields["name"] ?? fields["urlname"] ?? code,
                             coordinate: coordinate,
                             type: CacheType(gpxName: typeName),
                             container: ContainerSize(gpxName: cacheFields["container"] ?? ""),
                             difficulty: GPXParser.rating(cacheFields["difficulty"]),
                             terrain: GPXParser.rating(cacheFields["terrain"]))
        cache.sourceID = Int(cacheAttributes["id"] ?? "")
        cache.owner = cacheFields["owner"] ?? cacheFields["placed_by"] ?? ""
        cache.placedBy = cacheFields["placed_by"] ?? cache.owner
        cache.hidden = fields["time"].flatMap(GPXParser.parseDate)
        cache.isAvailable = GPXParser.bool(cacheAttributes["available"], default: true)
        cache.isArchived = GPXParser.bool(cacheAttributes["archived"], default: false)
        cache.isFound = sym == "geocache found" || GPXParser.bool(gsakFields["userfound"], default: false)
            || GPXParser.bool(cacheFields["found"], default: false)
        cache.country = cacheFields["country"] ?? ""
        cache.state = cacheFields["state"] ?? ""
        cache.url = fields["url"] ?? ""
        if cache.url.isEmpty, code.hasPrefix("GC") { cache.url = "https://coord.info/" + code }
        cache.shortDescription = cacheFields["short_description"] ?? ""
        // like Cachebox: a description without html attribute is taken as HTML
        cache.shortDescriptionIsHTML = GPXParser.bool(cacheFields["short_description_html"], default: true)
        cache.longDescription = cacheFields["long_description"] ?? ""
        cache.longDescriptionIsHTML = GPXParser.bool(cacheFields["long_description_html"], default: true)
        cache.hint = cacheFields["encoded_hints"] ?? cacheFields["hints"] ?? ""
        cache.favoritePoints = (gsakFields["favpoints"] ?? cacheFields["favorite_points"]).flatMap { Int($0) }
        cache.attributes = attributes
        // GSAK writes the original coordinates when the cache has corrected ones
        if let lat = gsakFields["latbeforecorrect"].flatMap(Double.init),
           let lon = gsakFields["lonbeforecorrect"].flatMap(Double.init) {
            cache.correctedCoordinate = coordinate
            cache.coordinate = Coordinate(latitude: lat, longitude: lon)
        }
        let cacheLogs = logs.map { log -> CacheLog in var log = log; log.cacheCode = code; return log }
        let cacheTrackables = trackables.map { Trackable(code: $0.code, name: $0.name, cacheCode: code) }
        return .cache(cache, logs: cacheLogs, trackables: cacheTrackables)
    }

    // MARK: Helpers

    /// Cache code of a pocket query waypoint: the two-letter prefix is replaced by "GC" ("PK1A2B3" → "GC1A2B3").
    static func parentCode(of code: String) -> String? {
        guard code.count > 2 else { return nil }
        return "GC" + code.dropFirst(2)
    }

    static func rating(_ text: String?) -> Double {
        guard let text, let value = Double(text.replacingOccurrences(of: ",", with: ".")) else { return 1 }
        return min(5, max(1, value))
    }

    static func bool(_ text: String?, default value: Bool) -> Bool {
        guard let text = text?.lowercased() else { return value }
        switch text {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return value
        }
    }

    nonisolated(unsafe) private static let isoFormatters: [ISO8601DateFormatter] = {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return [plain, withFraction]
    }()

    private static let localFormatters: [DateFormatter] = {
        ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = format
            return formatter
        }
    }()

    /// GPX dates with or without time zone and fractions ("2026-05-01T19:00:00Z", "2010-05-01T00:00:00",
    /// "2011-03-14T07:00:00.123-07:00"). Dates without zone are taken as UTC.
    static func parseDate(_ text: String) -> Date? {
        for formatter in isoFormatters { if let date = formatter.date(from: text) { return date } }
        for formatter in localFormatters { if let date = formatter.date(from: text) { return date } }
        return nil
    }

    /// Decodes ROT13 like the hint display of geocaching.com (text in [brackets] stays as it is).
    public static func rot13(_ text: String) -> String {
        var inBracket = false
        return String(text.unicodeScalars.map { scalar -> Character in
            if scalar == "[" { inBracket = true } else if scalar == "]" { inBracket = false }
            guard !inBracket else { return Character(scalar) }
            switch scalar.value {
            case 65...90: return Character(UnicodeScalar((scalar.value - 65 + 13) % 26 + 65)!)
            case 97...122: return Character(UnicodeScalar((scalar.value - 97 + 13) % 26 + 97)!)
            default: return Character(scalar)
            }
        })
    }
}

public struct GPXError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
