import CacheboxCore
import SwiftUI

// Names, icons and colours of the cache model for the UI. Cache and waypoint types use the icons of the Android
// app: `Assets.xcassets/Cachebox` holds copies of `SkinPacker/Icons/default/day/UI_IconPack` from the Cachebox
// repository, named like the sprites there (`"big" + GeoCacheType.name()`); `Assets.xcassets/CacheboxMap` holds the
// small map sprites (`small1` … `small7`) and `star` from the same folder. Rights: see UI-KONZEPT.md.

extension CacheType {
    var title: String {
        switch self {
        case .traditional: "Traditional"
        case .multi: "Multi"
        case .mystery: "Mystery"
        case .letterbox: "Letterbox"
        case .wherigo: "Wherigo"
        case .event: "Event"
        case .megaEvent: "Mega-Event"
        case .gigaEvent: "Giga-Event"
        case .cito: "CITO"
        case .communityCelebration: "Community-Event"
        case .earth: "Earthcache"
        case .virtual: "Virtual"
        case .webcam: "Webcam"
        case .lab: "Lab-Cache"
        case .locationless: "Locationless"
        case .ape: "Project APE"
        case .hq: "Geocaching HQ"
        case .gpsAdventures: "GPS Adventures"
        case .other: "Sonstige"
        }
    }

    /// Asset name of the Cachebox icon (`GeoCacheType` names; Cachebox has no Locationless type and shows it as
    /// `Undefined`, the three HQ types share `bigHQ` here because the model does not tell them apart).
    var iconName: String {
        switch self {
        case .traditional: "bigTraditional"
        case .multi: "bigMulti"
        case .mystery: "bigMystery"
        case .letterbox: "bigLetterbox"
        case .wherigo: "bigWherigo"
        case .event: "bigEvent"
        case .megaEvent: "bigMegaEvent"
        case .gigaEvent: "bigGiga"
        case .cito: "bigCITO"
        case .communityCelebration: "bigCelebrationEvent"
        case .earth: "bigEarth"
        case .virtual: "bigVirtual"
        case .webcam: "bigCamera"
        case .lab: "bigLab"
        case .ape: "bigAPE"
        case .hq: "bigHQ"
        case .gpsAdventures: "bigAdventuresExhibit"
        case .locationless, .other: "bigUndefined"
        }
    }

    /// The icon with corrected coordinates (Cachebox `CacheInfo`: `"big" + type + "Solved"`). Cachebox has this
    /// variant only for the types below; the others keep their normal icon.
    func iconName(solved: Bool) -> String {
        switch self {
        case .traditional, .multi, .mystery, .letterbox, .wherigo, .earth, .virtual, .webcam:
            solved ? iconName + "Solved" : iconName
        default:
            iconName
        }
    }

    /// Types offered in the filter, in a stable order.
    /// All types, so that a type filter can show every cache of the list.
    static let filterChoices: [CacheType] = [.traditional, .multi, .mystery, .letterbox, .wherigo, .earth, .virtual,
                                             .webcam, .event, .megaEvent, .gigaEvent, .cito, .communityCelebration,
                                             .hq, .lab, .locationless, .ape, .gpsAdventures, .other]
}

extension ContainerSize {
    var title: String {
        switch self {
        case .notChosen: "Nicht gewählt"
        case .micro: "Micro"
        case .small: "Small"
        case .regular: "Regular"
        case .large: "Large"
        case .virtual: "Virtuell"
        case .other: "Andere"
        }
    }

    /// One letter like the size column in Cachebox (M/S/R/L/O).
    var letter: String {
        switch self {
        case .micro: "M"
        case .small: "S"
        case .regular: "R"
        case .large: "L"
        case .virtual: "V"
        case .other, .notChosen: "O"
        }
    }
}

extension WaypointType {
    var title: String {
        switch self {
        case .parking: "Parkplatz"
        case .stage: "Station"
        case .question: "Frage"
        case .final: "Final"
        case .trailhead: "Startpunkt"
        case .reference: "Referenzpunkt"
        case .other: "Wegpunkt"
        }
    }

    /// Asset name of the Cachebox icon; waypoints are `GeoCacheType` values there, too.
    var iconName: String {
        switch self {
        case .parking: "bigParkingArea"
        case .stage: "bigMultiStage"
        case .question: "bigMultiQuestion"
        case .final: "bigFinal"
        case .trailhead: "bigTrailhead"
        case .reference: "bigReferencePoint"
        case .other: "bigUndefined"
        }
    }
}

extension LogType {
    var title: String {
        switch self {
        case .found: "Gefunden"
        case .didNotFind: "Nicht gefunden"
        case .note: "Notiz"
        case .attended: "Teilgenommen"
        case .willAttend: "Teilnahme geplant"
        case .webcamPhoto: "Webcam-Foto"
        case .needsMaintenance: "Wartung nötig"
        case .ownerMaintenance: "Wartung durchgeführt"
        case .needsArchived: "Archivierung nötig"
        case .disable: "Deaktiviert"
        case .enable: "Aktiviert"
        case .publish: "Veröffentlicht"
        case .archive: "Archiviert"
        case .unarchive: "Wiederhergestellt"
        case .updateCoordinates: "Koordinaten geändert"
        case .reviewerNote: "Reviewer-Notiz"
        case .announcement: "Ankündigung"
        case .retract: "Zurückgezogen"
        case .other: "Log"
        }
    }

    var symbol: String {
        switch self {
        case .found, .attended, .webcamPhoto: "face.smiling.inverse"
        case .didNotFind: "face.dashed"
        case .needsMaintenance, .needsArchived: "wrench.adjustable"
        case .ownerMaintenance: "wrench.and.screwdriver.fill"
        case .disable, .archive, .retract: "pause.circle.fill"
        case .enable, .publish, .unarchive: "play.circle.fill"
        case .willAttend: "calendar.badge.plus"
        default: "text.bubble.fill"
        }
    }

    var color: Color {
        switch self {
        case .found, .attended, .webcamPhoto: .green
        case .didNotFind: .blue
        case .needsMaintenance, .needsArchived, .disable, .archive, .retract: .orange
        default: .secondary
        }
    }
}

extension CacheSummary {
    /// Icon on the map from zoom 13 (Cachebox `MapViewCacheList.getMapIcon`): star for own caches, smiley for found
    /// ones, else the type icon, "Solved" with corrected coordinates or a final. The `big` sprites have the same
    /// drawings as Cachebox's 32 px `map` sprites but 80 px, which stays sharp at @3x.
    func mapIconName(isOwn: Bool) -> String {
        if isOwn { return "star" }
        if isFound { return "log0icon" }
        return type.iconName(solved: isSolved)
    }

    /// Icon on the map below zoom 13 (Cachebox `getSmallMapIcon`): a 15 px sprite per type group, "no" for archived
    /// or unavailable caches, "Solved" with corrected coordinates or a final. Deviations: Cachebox marks only a
    /// final or start waypoint as solved here (corrected coordinates count everywhere else), and it would draw
    /// nothing for the few combinations without a sprite (e.g. a solved event); those use the unsolved sprite.
    func smallMapIconName(isOwn: Bool) -> String {
        var icon: String
        var solved = ""
        if isFound {
            icon = "small6"
        } else if isOwn {
            icon = "small7"
        } else {
            if isSolved { solved = "Solved" }
            icon = switch type {
            case .multi: "small2"
            case .event, .megaEvent, .gigaEvent, .cito, .communityCelebration: "small3"
            case .virtual, .webcam, .earth: "small4"
            case .mystery, .wherigo: "small5"
            default: "small1"
            }
        }
        if isArchived || !isAvailable { icon += "no" }
        return Self.smallIcons.contains(icon + solved) ? icon + solved : icon
    }

    /// The small sprites in `Assets.xcassets/CacheboxMap`.
    private static let smallIcons: Set<String> = [
        "small1", "small1Solved", "small1no", "small1noSolved", "small2", "small2Solved", "small2no", "small2noSolved",
        "small3", "small3no", "small4", "small4Solved", "small4no", "small5", "small5Solved", "small5no",
        "small5noSolved", "small6", "small6no", "small7", "small7no",
    ]

    /// "D 1,5 · T 2 · S", the rating line of the list.
    var ratingText: String {
        "D \(Self.rating(difficulty)) · T \(Self.rating(terrain)) · \(container.letter)"
    }

    static func rating(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

enum Format {
    /// Distance like in Cachebox: metres below 1 km, kilometres with one decimal below 10 km.
    static func distance(_ metres: Double) -> String {
        switch metres {
        case ..<1000: "\(Int(metres.rounded())) m"
        case ..<10_000: (metres / 1000).formatted(.number.precision(.fractionLength(1))) + " km"
        default: "\(Int((metres / 1000).rounded())) km"
        }
    }

    /// "1 Cache", "2 Caches": the number with the singular or plural noun.
    static func count(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}

/// A Cachebox bitmap icon fitted into a square of `size` points (keeps the aspect ratio, `bigFinal` is 80 × 96 px).
struct CacheboxIcon: View {
    let name: String
    var size: CGFloat = 28

    var body: some View {
        Image(name)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The type icon of a cache with the status marks of the Cachebox list (`CacheInfo`, half the icon size each):
/// smiley for found at the bottom left, heart for favourite at the top right, traffic cone for archived or stop sign
/// for disabled at the bottom right. Corrected coordinates switch to the "Solved" icon.
struct CacheTypeIcon: View {
    let type: CacheType
    var isFound = false
    var isFavorite = false
    var isArchived = false
    var isUnavailable = false
    var isSolved = false
    var size: CGFloat = 36

    var body: some View {
        CacheboxIcon(name: type.iconName(solved: isSolved), size: size)
            .overlay(alignment: .bottomLeading) {
                if isFound { mark("log0icon") }
            }
            .overlay(alignment: .topTrailing) {
                if isFavorite { mark("favorit") }
            }
            .overlay(alignment: .bottomTrailing) {
                if isArchived {
                    mark("log11icon")
                } else if isUnavailable {
                    mark("disabled")
                }
            }
            .accessibilityElement()
            .accessibilityLabel(accessibilityText)
    }

    private func mark(_ name: String) -> some View {
        CacheboxIcon(name: name, size: size / 2)
    }

    private var accessibilityText: String {
        var parts = [type.title]
        if isFound { parts.append("gefunden") }
        if isFavorite { parts.append("Favorit") }
        if isSolved { parts.append("korrigierte Koordinaten") }
        if isArchived {
            parts.append("archiviert")
        } else if isUnavailable {
            parts.append("nicht verfügbar")
        }
        return parts.joined(separator: ", ")
    }
}

/// Cachebox `CacheInfo` with `SHOW_S_D_T`: size letter and bar, D and T stars, trackables and favourite points. Used
/// in the cache list (`VIEW_MODE_CACHE_LIST`), the slider (`VIEW_MODE_SLIDER`) and the compass.
struct SizeDifficultyTerrain: View {
    let cache: CacheSummary
    /// Smaller letters and icons, for the list rows and the slider bar.
    var isCompact = false
    /// Trackables and favourite points behind the stars (Cachebox draws them in every mode with `SHOW_S_D_T`).
    var showsExtras = true
    @ScaledMetric(relativeTo: .footnote) private var baseHeight: CGFloat = 13

    private var height: CGFloat { isCompact ? (baseHeight * 0.85).rounded() : baseHeight }

    var body: some View {
        HStack(spacing: isCompact ? 3 : 4) {
            Text(cache.container.letter)
            Image(sizeImage).resizable().interpolation(.high)
                .frame(width: height * 45 / 12, height: height)
            Text("D").padding(.leading, isCompact ? 5 : 8)
            Image(Self.stars(cache.difficulty)).resizable().interpolation(.high)
                .frame(width: height * 5, height: height)
            Text("T").padding(.leading, isCompact ? 5 : 8)
            Image(Self.stars(cache.terrain)).resizable().interpolation(.high)
                .frame(width: height * 5, height: height)
            if showsExtras, cache.trackableCount > 0 {
                Image("tb").resizable().interpolation(.high)
                    .frame(width: height * 1.4, height: height * 1.4)
                    .rotationEffect(.degrees(90))
                    .padding(.leading, isCompact ? 6 : 10)
                if cache.trackableCount > 1 { Text("x\(cache.trackableCount)") }
            }
            if showsExtras, let points = cache.favoritePoints, points > 0 {
                Image("FavPoi").resizable().interpolation(.high)
                    .frame(width: height * 1.2, height: height * 1.2)
                    .padding(.leading, isCompact ? 6 : 10)
                Text("x\(points)")
            }
        }
        .font(isCompact ? .caption.weight(.semibold) : .footnote.weight(.semibold))
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// Cachebox `Sprites.SizesIcons` (`other`, `micro`, `small`, `regular`, `large`).
    private var sizeImage: String {
        switch cache.container {
        case .micro: "size-micro"
        case .small: "size-small"
        case .regular: "size-regular"
        case .large: "size-large"
        default: "size-other"
        }
    }

    /// Cachebox `Sprites.Stars.get((int) (rating * 2))`: `stars0icon`, `stars0-5icon` … `stars5icon`.
    static func stars(_ rating: Double) -> String {
        let halves = min(10, max(0, Int(rating * 2)))
        return halves.isMultiple(of: 2) ? "stars\(halves / 2)icon" : "stars\(halves / 2)-5icon"
    }

    private var accessibilityText: String {
        var parts = ["Größe \(cache.container.title)",
                     "Schwierigkeit \(CacheSummary.rating(cache.difficulty))",
                     "Gelände \(CacheSummary.rating(cache.terrain))"]
        if showsExtras, cache.trackableCount > 0 { parts.append("\(cache.trackableCount) Trackables") }
        if showsExtras, let points = cache.favoritePoints, points > 0 { parts.append("\(points) Favoritenpunkte") }
        return parts.joined(separator: ", ")
    }
}
