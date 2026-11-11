import Foundation

/// Geocache types as named in Groundspeak GPX files (`<groundspeak:type>`).
public enum CacheType: String, Codable, Sendable, CaseIterable {
    case traditional, multi, mystery, letterbox, wherigo
    case event, megaEvent, gigaEvent, cito, communityCelebration
    case earth, virtual, webcam, lab, locationless, ape, hq, gpsAdventures
    case other

    /// Maps the type text of a GPX file, e.g. "Traditional Cache", "Unknown Cache", "Earthcache".
    public init(gpxName: String) {
        let name = gpxName.lowercased()
            .replacingOccurrences(of: "geocache|", with: "")
            .trimmingCharacters(in: .whitespaces)
        switch name {
        case "traditional cache", "traditional", "classic": self = .traditional
        case "multi-cache", "multi cache", "multicache", "multi": self = .multi
        case "unknown cache", "mystery cache", "mystery", "unknown", "puzzle", "quiz": self = .mystery
        case "letterbox hybrid", "letterbox": self = .letterbox
        case "wherigo cache", "wherigo": self = .wherigo
        case "event cache", "event": self = .event
        case "mega-event cache", "mega-event", "mega event cache": self = .megaEvent
        case "giga-event cache", "giga-event", "giga event cache": self = .gigaEvent
        case "cache in trash out event", "cito": self = .cito
        case "community celebration event", "lost and found event cache": self = .communityCelebration
        case "earthcache", "earth cache", "earth": self = .earth
        case "virtual cache", "virtual": self = .virtual
        case "webcam cache", "webcam": self = .webcam
        case "lab cache", "geocaching lab cache", "lab": self = .lab
        case "locationless (reverse) cache", "locationless cache", "reverse": self = .locationless
        case "project ape cache", "project a.p.e. cache": self = .ape
        case "geocaching hq", "geocaching hq celebration", "geocaching hq block party", "groundspeak hq",
             "groundspeak block party", "groundspeak lost and found celebration": self = .hq
        case "gps adventures exhibit", "gps adventures maze exhibit": self = .gpsAdventures
        default: self = .other
        }
    }

    public var isEvent: Bool { [.event, .megaEvent, .gigaEvent, .cito, .communityCelebration, .hq].contains(self) }
}

/// Container sizes as named in GPX files (`<groundspeak:container>`).
public enum ContainerSize: String, Codable, Sendable, CaseIterable, Comparable {
    case notChosen, micro, small, regular, large, virtual, other

    public init(gpxName: String) {
        switch gpxName.lowercased().trimmingCharacters(in: .whitespaces) {
        case "micro", "nano": self = .micro
        case "small": self = .small
        case "regular", "medium": self = .regular
        case "large", "very large", "extra large": self = .large
        case "virtual", "none": self = .virtual
        case "other": self = .other
        default: self = .notChosen
        }
    }

    private var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    public static func < (a: Self, b: Self) -> Bool { a.order < b.order }
}

/// Additional waypoint types (`<sym>` / `<type>Waypoint|…</type>` in GPX files).
public enum WaypointType: String, Codable, Sendable, CaseIterable {
    case parking, stage, question, final, trailhead, reference, other

    public init(gpxName: String) {
        let name = gpxName.lowercased().replacingOccurrences(of: "waypoint|", with: "")
        switch name.trimmingCharacters(in: .whitespaces) {
        case "parking area", "parking": self = .parking
        case "stages of a multicache", "physical stage", "stage": self = .stage
        case "question to answer", "virtual stage", "question": self = .question
        case "final location", "final": self = .final
        case "trailhead": self = .trailhead
        case "reference point", "reference": self = .reference
        default: self = .other
        }
    }
}

/// Log types (`<groundspeak:log><groundspeak:type>`).
public enum LogType: String, Codable, Sendable, CaseIterable {
    case found, didNotFind, note, attended, willAttend, webcamPhoto
    case needsMaintenance, ownerMaintenance, needsArchived, disable, enable, publish, archive, unarchive
    case updateCoordinates, reviewerNote, announcement, retract, other

    public init(gpxName: String) {
        switch gpxName.lowercased().trimmingCharacters(in: .whitespaces) {
        case "found it", "found": self = .found
        case "didn't find it", "did not find it", "didn't find": self = .didNotFind
        case "write note", "note", "comment": self = .note
        case "attended": self = .attended
        case "will attend": self = .willAttend
        case "webcam photo taken": self = .webcamPhoto
        case "needs maintenance": self = .needsMaintenance
        case "owner maintenance": self = .ownerMaintenance
        case "needs archived", "needs archiving": self = .needsArchived
        case "temporarily disable listing": self = .disable
        case "enable listing": self = .enable
        case "publish listing": self = .publish
        case "archive": self = .archive
        case "unarchive": self = .unarchive
        case "update coordinates": self = .updateCoordinates
        case "post reviewer note": self = .reviewerNote
        case "announcement": self = .announcement
        case "retract listing": self = .retract
        default: self = .other
        }
    }
}

/// A geographic position in WGS84 degrees.
public struct Coordinate: Hashable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// GPX files use 0/0 for waypoints whose coordinates are hidden.
    public var isValid: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude) && !(latitude == 0 && longitude == 0)
    }
}

/// A cache attribute: the Groundspeak attribute id and whether it applies ("inc").
public struct CacheAttribute: Hashable, Codable, Sendable {
    public var id: Int
    public var isPositive: Bool
    public var name: String

    public init(id: Int, isPositive: Bool, name: String = "") {
        self.id = id
        self.isPositive = isPositive
        self.name = name
    }
}

/// All stored data of one geocache.
public struct Geocache: Identifiable, Hashable, Codable, Sendable {
    /// GC code (or OC code for Opencaching).
    public var code: String
    public var id: String { code }
    public var name: String
    public var coordinate: Coordinate
    /// Coordinates the user corrected (e.g. a solved mystery); kept on re-import.
    public var correctedCoordinate: Coordinate?
    public var type: CacheType
    public var container: ContainerSize
    public var difficulty: Double
    public var terrain: Double
    public var owner: String
    public var placedBy: String
    public var hidden: Date?
    public var isAvailable: Bool
    public var isArchived: Bool
    public var isFound: Bool
    public var country: String
    public var state: String
    public var url: String
    public var shortDescription: String
    public var shortDescriptionIsHTML: Bool
    public var longDescription: String
    public var longDescriptionIsHTML: Bool
    public var hint: String
    public var favoritePoints: Int?
    public var attributes: [CacheAttribute]
    /// The user's own note; kept on re-import.
    public var note: String
    /// Marked by the user; kept on re-import.
    public var isFavorite: Bool
    /// Groundspeak's numeric cache id, if known.
    public var sourceID: Int?
    /// Name of the GPX file the cache was last imported from (Cachebox: category).
    public var gpxFile: String
    public var updated: Date?

    public init(code: String, name: String, coordinate: Coordinate, type: CacheType = .other,
                container: ContainerSize = .notChosen, difficulty: Double = 1, terrain: Double = 1) {
        self.code = code
        self.name = name
        self.coordinate = coordinate
        self.type = type
        self.container = container
        self.difficulty = difficulty
        self.terrain = terrain
        owner = ""
        placedBy = ""
        isAvailable = true
        isArchived = false
        isFound = false
        country = ""
        state = ""
        url = ""
        shortDescription = ""
        shortDescriptionIsHTML = false
        longDescription = ""
        longDescriptionIsHTML = false
        hint = ""
        attributes = []
        note = ""
        isFavorite = false
        gpxFile = ""
    }

    /// The position to navigate to: corrected coordinates win.
    public var target: Coordinate { correctedCoordinate ?? coordinate }
}

/// An additional waypoint of a cache (parking, stage, final, …).
public struct Waypoint: Identifiable, Hashable, Codable, Sendable {
    /// Waypoint code, e.g. "PK1A2B3" for cache GC1A2B3.
    public var code: String
    public var cacheCode: String
    public var id: String { cacheCode + "/" + code }
    public var title: String
    public var comment: String
    public var type: WaypointType
    public var coordinate: Coordinate?
    /// Created by the user in the app (not from a GPX file); never replaced by an import.
    public var isUserCreated: Bool

    public init(code: String, cacheCode: String, title: String, comment: String = "", type: WaypointType = .other,
                coordinate: Coordinate? = nil, isUserCreated: Bool = false) {
        self.code = code
        self.cacheCode = cacheCode
        self.title = title
        self.comment = comment
        self.type = type
        self.coordinate = coordinate
        self.isUserCreated = isUserCreated
    }
}

/// A log entry of a cache.
public struct CacheLog: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var cacheCode: String
    public var date: Date?
    public var type: LogType
    public var finder: String
    public var text: String

    public init(id: String, cacheCode: String, date: Date?, type: LogType, finder: String, text: String) {
        self.id = id
        self.cacheCode = cacheCode
        self.date = date
        self.type = type
        self.finder = finder
        self.text = text
    }
}

/// A trackable (travel bug, coin) listed in a cache.
public struct Trackable: Identifiable, Hashable, Codable, Sendable {
    public var code: String
    public var id: String { code }
    public var name: String
    public var cacheCode: String

    public init(code: String, name: String, cacheCode: String) {
        self.code = code
        self.name = name
        self.cacheCode = cacheCode
    }
}

/// The fields of a cache needed for the cache list (cheap to load for thousands of caches).
public struct CacheSummary: Identifiable, Hashable, Sendable {
    public var code: String
    public var id: String { code }
    public var name: String
    /// The corrected coordinates if there are any, else the listing coordinates.
    public var coordinate: Coordinate
    public var hasCorrectedCoordinate: Bool
    /// Coordinates of the first final waypoint that has some (not 0/0), e.g. a solved mystery entered as waypoint.
    public var finalCoordinate: Coordinate?
    public var type: CacheType
    public var container: ContainerSize
    public var difficulty: Double
    public var terrain: Double
    public var owner: String
    public var hidden: Date?
    public var isAvailable: Bool
    public var isArchived: Bool
    public var isFound: Bool
    public var isFavorite: Bool
    public var favoritePoints: Int?
    public var waypointCount: Int
    public var trackableCount: Int

    public init(code: String, name: String, coordinate: Coordinate, hasCorrectedCoordinate: Bool = false,
                finalCoordinate: Coordinate? = nil, type: CacheType, container: ContainerSize, difficulty: Double, terrain: Double, owner: String = "",
                hidden: Date? = nil, isAvailable: Bool = true, isArchived: Bool = false, isFound: Bool = false,
                isFavorite: Bool = false, favoritePoints: Int? = nil, waypointCount: Int = 0, trackableCount: Int = 0) {
        self.code = code
        self.name = name
        self.coordinate = coordinate
        self.hasCorrectedCoordinate = hasCorrectedCoordinate
        self.finalCoordinate = finalCoordinate
        self.type = type
        self.container = container
        self.difficulty = difficulty
        self.terrain = terrain
        self.owner = owner
        self.hidden = hidden
        self.isAvailable = isAvailable
        self.isArchived = isArchived
        self.isFound = isFound
        self.isFavorite = isFavorite
        self.favoritePoints = favoritePoints
        self.waypointCount = waypointCount
        self.trackableCount = trackableCount
    }

    /// Where the cache is searched: the corrected coordinates, else a final waypoint with coordinates, else the
    /// listing coordinates. Cachebox draws the cache there on the map and measures the list distance to it
    /// (`MapViewCacheList`, `Cache.getCorrectedFinal`, `CacheList.resortList`). Cachebox also uses a start waypoint of
    /// multis and mysteries; this model has no start waypoints yet.
    public var target: Coordinate {
        hasCorrectedCoordinate ? coordinate : finalCoordinate ?? coordinate
    }

    /// Corrected coordinates or a final waypoint with coordinates (Cachebox
    /// `hasCorrectedCoordinatesOrHasCorrectedFinal`, shown with the "Solved" icon).
    public var isSolved: Bool { hasCorrectedCoordinate || finalCoordinate != nil }
}
