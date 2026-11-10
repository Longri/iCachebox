import Foundation

/// One downloadable map or theme of a catalog.
struct MapCatalogEntry: Identifiable, Hashable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case map, theme
    }

    /// Unique name in the catalog, e.g. `Freizeitkarte_BREMEN` or `freizeitkarte-v5`.
    let id: String
    let kind: Kind
    let titleGerman: String
    let titleEnglish: String
    let url: URL
    /// Size of the download (the ZIP file) in bytes.
    let size: Int64
    /// Size after unpacking (map entries only).
    let unpackedSize: Int64?
    let md5: String?
    /// Catalog release the entry belongs to, e.g. `2609`.
    let release: String

    func title(language: String) -> String {
        language == "de" ? titleGerman : titleEnglish
    }
}

/// A map catalog: release information plus its maps and themes.
struct MapCatalog: Sendable {
    let release: String
    let hintGerman: String
    let hintEnglish: String
    let entries: [MapCatalogEntry]

    func hint(language: String) -> String { language == "de" ? hintGerman : hintEnglish }
    func entry(_ id: String) -> MapCatalogEntry? { entries.first { $0.id == id } }
}

/// The Freizeitkarte-OSM repository file, also used by Cachebox (`FZKDownload`).
///
/// The project invites apps to integrate downloads through this file. It is only served over HTTP (the HTTPS
/// certificate does not cover `repository.`), hence the ATS exception in `iCacheBox-Info.plist`. The map and
/// theme files themselves are available over HTTPS and are requested that way.
enum FreizeitkarteCatalog {
    static let url = URL(string: "http://repository.freizeitkarte-osm.de/repository_freizeitkarte_android.xml")!
    static let homepage = URL(string: "https://www.freizeitkarte-osm.de/android/de/")!
    /// As stated in the maps' header comment ("(c) Map: FZK project (CC-BY-3.0); Map data: OpenStreetMap
    /// contributors; Contour data: sonny.4lima.de").
    static let attribution = "Karten: FZK-Projekt (CC BY 3.0) · Kartendaten © OpenStreetMap-Mitwirkende (ODbL) · "
        + "Höhenlinien: sonny.4lima.de"

    static func parse(_ data: Data) throws -> MapCatalog {
        let handler = Handler()
        let parser = XMLParser(data: data)
        parser.delegate = handler
        guard parser.parse(), !handler.entries.isEmpty else {
            throw CatalogError(parser.parserError?.localizedDescription ?? "Katalog enthält keine Karten")
        }
        let release = handler.general["Release"] ?? ""
        let entries = handler.entries.compactMap { fields -> MapCatalogEntry? in
            guard let name = fields["Name"], let kind = fields["kind"].flatMap(MapCatalogEntry.Kind.init(rawValue:)),
                  let raw = fields["Url"], let url = secure(URL(string: raw)) else { return nil }
            // every map is called "Freizeitkarte …"; the list only needs the region
            func title(_ key: String) -> String {
                let text = fields[key] ?? name
                return text.hasPrefix("Freizeitkarte ") ? String(text.dropFirst("Freizeitkarte ".count)) : text
            }
            return MapCatalogEntry(id: name, kind: kind,
                                   titleGerman: title("DescriptionGerman"),
                                   titleEnglish: title("DescriptionEnglish"),
                                   url: url,
                                   size: fields["Size"].flatMap { Int64($0) } ?? 0,
                                   unpackedSize: fields["MapsforgeFileSize"].flatMap { Int64($0) },
                                   md5: fields["Checksum"]?.lowercased(),
                                   release: release)
        }
        return MapCatalog(release: release,
                          hintGerman: handler.general["HeaderHintGerman"] ?? "",
                          hintEnglish: handler.general["HeaderHintEnglish"] ?? "",
                          entries: entries)
    }

    /// The download server answers on HTTPS as well; background sessions and ATS need it.
    private static func secure(_ url: URL?) -> URL? {
        guard let url, url.scheme == "http", url.host() == "download.freizeitkarte-osm.de",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.scheme = "https"
        return components.url
    }

    /// Collects the text of the child elements of `<General>`, `<Map>` and `<Theme>`.
    private final class Handler: NSObject, XMLParserDelegate {
        var general: [String: String] = [:]
        var entries: [[String: String]] = []
        private var current: [String: String]?
        private var inGeneral = false
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            switch name {
            case "General": inGeneral = true
            case "Map": current = ["kind": MapCatalogEntry.Kind.map.rawValue]
            case "Theme": current = ["kind": MapCatalogEntry.Kind.theme.rawValue]
            default: break
            }
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            text = ""
            switch name {
            case "General": inGeneral = false
            case "Map", "Theme":
                if let current { entries.append(current) }
                current = nil
            default:
                if current != nil {
                    current?[name] = value
                } else if inGeneral {
                    general[name] = value
                }
            }
        }
    }
}

struct CatalogError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
