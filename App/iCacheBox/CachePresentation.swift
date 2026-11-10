import CacheboxCore
import SwiftUI

// Names, symbols and colours of the cache model for the UI. Symbols are SF Symbols: the Cachebox icon set is
// not used until its rights are clear (UI-KONZEPT.md).

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

    var symbol: String {
        switch self {
        case .traditional: "shippingbox.fill"
        case .multi: "square.stack.3d.up.fill"
        case .mystery: "questionmark.square.fill"
        case .letterbox: "envelope.fill"
        case .wherigo: "iphone.gen1"
        case .event, .megaEvent, .gigaEvent, .communityCelebration, .hq: "calendar"
        case .cito: "trash.fill"
        case .earth: "globe.europe.africa.fill"
        case .virtual: "eye.fill"
        case .webcam: "web.camera.fill"
        case .lab: "flask.fill"
        case .locationless, .ape, .gpsAdventures, .other: "mappin.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .traditional: .green
        case .multi: .orange
        case .mystery, .wherigo: .blue
        case .letterbox: .teal
        case .event, .megaEvent, .gigaEvent, .communityCelebration, .hq: .red
        case .cito: .mint
        case .earth: .brown
        case .virtual, .webcam, .locationless: .purple
        case .lab: .cyan
        case .ape, .gpsAdventures, .other: .gray
        }
    }

    /// Types offered in the filter, in a stable order.
    static let filterChoices: [CacheType] = [.traditional, .multi, .mystery, .letterbox, .wherigo, .earth, .virtual,
                                             .webcam, .event, .megaEvent, .gigaEvent, .cito, .lab, .other]
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

    var symbol: String {
        switch self {
        case .parking: "parkingsign.circle.fill"
        case .stage: "flag.fill"
        case .question: "questionmark.circle.fill"
        case .final: "flag.checkered"
        case .trailhead: "figure.walk"
        case .reference: "scope"
        case .other: "mappin"
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

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}

/// The type symbol of a cache with small status marks (found, favourite, unavailable), like the Cachebox list icon.
struct CacheTypeIcon: View {
    let type: CacheType
    var isFound = false
    var isFavorite = false
    var isUnavailable = false
    var isSolved = false

    var body: some View {
        Image(systemName: type.symbol)
            .font(.title2)
            .foregroundStyle(type.color)
            .frame(width: 34, height: 34)
            .overlay(alignment: .bottomLeading) {
                if isFound {
                    badge("checkmark.circle.fill", .green)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isFavorite {
                    badge("star.fill", .yellow)
                } else if isSolved {
                    badge("pencil.circle.fill", .blue)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isUnavailable {
                    badge("nosign", .red)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(accessibilityText)
    }

    private func badge(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(color)
            .background(Circle().fill(Color(.systemBackground)).padding(-1))
    }

    private var accessibilityText: String {
        var parts = [type.title]
        if isFound { parts.append("gefunden") }
        if isFavorite { parts.append("Favorit") }
        if isSolved { parts.append("korrigierte Koordinaten") }
        if isUnavailable { parts.append("nicht verfügbar") }
        return parts.joined(separator: ", ")
    }
}
