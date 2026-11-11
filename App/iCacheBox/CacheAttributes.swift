import CacheboxCore
import SwiftUI

// Cache attributes as in the Cachebox description (`DescriptionViewControl.getAttributesHtml`): a row of icons in
// front of the description text, first the attributes that apply, then those that do not, each group in the order of
// the Cachebox `Attribute` enum (`CacheDetail.getAttributes`); a tap shows the text (Cachebox: a MessageBox with
// `Translation.get("att_N_x")`). `Assets.xcassets/Attributes` holds the 32 × 32 px icons of
// `CB_Android/assets/data/attributes`, named like there: `att_<ordinal>_1` applies, `att_<ordinal>_0` does not.
// Rights: see UI-KONZEPT.md. The texts are our own wording (the Cachebox translations are GPL).

extension CacheAttribute {
    /// How the icon is drawn.
    enum Icon: Equatable {
        /// A Cachebox icon as it is.
        case cachebox(String)
        /// Cachebox has no "does not apply" icon for this attribute: its "applies" icon, crossed out in the style of
        /// the other `_0` icons. Cachebox leaves such an attribute out (it only logs the missing file).
        case crossedOut(String)
        /// An id Cachebox does not know (it maps it to `Default`, which has no icon, and leaves it out).
        case unknown
    }

    /// Ordinal of the Cachebox `Attribute` enum (`Attribute.getAttributeEnumByGcComId(id).ordinal()`), which names
    /// the icons and gives the order. Equal to the Groundspeak id up to 67; the enum then has Challenge (gc 71) as 68,
    /// Bonus 69, Power trail 70 and the solution checker (gc 72) as 71. Groundspeak has no attribute 68.
    var cacheboxIndex: Int? {
        switch id {
        case 1...67, 69, 70: id
        case 71: 68
        case 72: 71
        default: nil
        }
    }

    /// Cachebox ordinals without a `_0` icon.
    private static let withoutNegativeIcon: Set<Int> = [2, 3, 4, 5, 11, 12, 18, 19, 20, 21, 22, 23, 26, 39, 42, 43,
                                                        44, 48, 49, 50, 51, 60]

    var icon: Icon {
        guard let index = cacheboxIndex else { return .unknown }
        if isPositive { return .cachebox("att_\(index)_1") }
        return Self.withoutNegativeIcon.contains(index) ? .crossedOut("att_\(index)_1") : .cachebox("att_\(index)_0")
    }

    /// German text for the attribute as it applies or not; unknown ids use the name from the GPX file.
    var title: String {
        if let texts = Self.texts[id] { return isPositive ? texts.applies : texts.doesNotApply }
        let name = name.isEmpty ? "Attribut \(id)" : name
        return isPositive ? name : "Nicht: \(name)"
    }

    /// The attributes in Cachebox order: those that apply first, then the others, each sorted by `cacheboxIndex`,
    /// unknown ids last. Cachebox keeps the attributes as two bit masks, so each one appears once per group at most.
    static func displayOrder(_ attributes: [CacheAttribute]) -> [CacheAttribute] {
        var seen = Set<[Int]>()
        return attributes
            .filter { seen.insert([$0.id, $0.isPositive ? 1 : 0]).inserted }
            .sorted { a, b in
                if a.isPositive != b.isPositive { return a.isPositive }
                return (a.cacheboxIndex ?? 1000 + a.id) < (b.cacheboxIndex ?? 1000 + b.id)
            }
    }

    /// Groundspeak id → text if the attribute applies / does not apply.
    private static let texts: [Int: (applies: String, doesNotApply: String)] = [
        1: ("Hunde erlaubt", "Hunde nicht erlaubt"),
        2: ("Eintritt oder Parkgebühr", "Kein Eintritt, keine Parkgebühr"),
        3: ("Kletterausrüstung nötig", "Keine Kletterausrüstung nötig"),
        4: ("Boot nötig", "Kein Boot nötig"),
        5: ("Tauchausrüstung nötig", "Keine Tauchausrüstung nötig"),
        6: ("Für Kinder geeignet", "Nicht für Kinder geeignet"),
        7: ("Dauert weniger als eine Stunde", "Dauert länger als eine Stunde"),
        8: ("Schöne Aussicht", "Keine besondere Aussicht"),
        9: ("Anstrengende Wanderung", "Keine anstrengende Wanderung"),
        10: ("Schwierige Kletterei", "Keine schwierige Kletterei"),
        11: ("Waten kann nötig sein", "Kein Waten nötig"),
        12: ("Schwimmen kann nötig sein", "Kein Schwimmen nötig"),
        13: ("Rund um die Uhr zugänglich", "Nicht rund um die Uhr zugänglich"),
        14: ("Nachts empfohlen", "Nachts nicht empfohlen"),
        15: ("Auch im Winter zugänglich", "Im Winter nicht zugänglich"),
        16: ("Kakteen", "Keine Kakteen"),
        17: ("Giftige Pflanzen", "Keine giftigen Pflanzen"),
        18: ("Gefährliche Tiere", "Keine gefährlichen Tiere"),
        19: ("Zecken", "Keine Zecken"),
        20: ("Verlassene Minen", "Keine verlassenen Minen"),
        21: ("Steinschlag", "Kein Steinschlag"),
        22: ("Jagdgebiet", "Kein Jagdgebiet"),
        23: ("Gefährliches Gelände", "Kein gefährliches Gelände"),
        24: ("Rollstuhlgeeignet", "Nicht rollstuhlgeeignet"),
        25: ("Parkplatz vorhanden", "Kein Parkplatz"),
        26: ("Öffentliche Verkehrsmittel", "Keine öffentlichen Verkehrsmittel"),
        27: ("Trinkwasser in der Nähe", "Kein Trinkwasser in der Nähe"),
        28: ("Öffentliche Toilette in der Nähe", "Keine öffentliche Toilette in der Nähe"),
        29: ("Telefon in der Nähe", "Kein Telefon in der Nähe"),
        30: ("Picknicktische in der Nähe", "Keine Picknicktische in der Nähe"),
        31: ("Camping möglich", "Kein Camping"),
        32: ("Fahrräder erlaubt", "Fahrräder nicht erlaubt"),
        33: ("Motorräder erlaubt", "Motorräder nicht erlaubt"),
        34: ("Quads erlaubt", "Quads nicht erlaubt"),
        35: ("Geländewagen erlaubt", "Geländewagen nicht erlaubt"),
        36: ("Schneemobile erlaubt", "Schneemobile nicht erlaubt"),
        37: ("Pferde erlaubt", "Pferde nicht erlaubt"),
        38: ("Lagerfeuer erlaubt", "Lagerfeuer nicht erlaubt"),
        39: ("Dornen", "Keine Dornen"),
        40: ("Unauffälligkeit nötig", "Keine Unauffälligkeit nötig"),
        41: ("Für Kinderwagen geeignet", "Nicht für Kinderwagen geeignet"),
        42: ("Wartung nötig", "Keine Wartung nötig"),
        43: ("Weidetiere, Vorsicht", "Keine Weidetiere"),
        44: ("Taschenlampe nötig", "Keine Taschenlampe nötig"),
        45: ("Lost and Found Tour", "Keine Lost and Found Tour"),
        46: ("Für Lkw und Wohnmobile geeignet", "Nicht für Lkw und Wohnmobile geeignet"),
        47: ("Rätsel vor Ort", "Kein Rätsel vor Ort"),
        48: ("UV-Lampe nötig", "Keine UV-Lampe nötig"),
        49: ("Schneeschuhe nötig", "Keine Schneeschuhe nötig"),
        50: ("Langlaufski nötig", "Keine Langlaufski nötig"),
        51: ("Spezialwerkzeug nötig", "Kein Spezialwerkzeug nötig"),
        52: ("Nachtcache", "Kein Nachtcache"),
        53: ("Park and Grab", "Kein Park and Grab"),
        54: ("Verlassenes Bauwerk", "Kein verlassenes Bauwerk"),
        55: ("Kurze Wanderung (unter 1 km)", "Keine kurze Wanderung (über 1 km)"),
        56: ("Mittlere Wanderung (1–10 km)", "Keine mittlere Wanderung (1–10 km)"),
        57: ("Lange Wanderung (über 10 km)", "Keine lange Wanderung (unter 10 km)"),
        58: ("Tankstelle in der Nähe", "Keine Tankstelle in der Nähe"),
        59: ("Essen in der Nähe", "Kein Essen in der Nähe"),
        60: ("Funksender (Beacon)", "Kein Funksender"),
        61: ("Partnerschafts-Cache", "Kein Partnerschafts-Cache"),
        62: ("Nur saisonal zugänglich", "Ganzjährig zugänglich"),
        63: ("Touristenfreundlich", "Nicht touristenfreundlich"),
        64: ("Baumklettern", "Kein Baumklettern"),
        65: ("Vorgarten (Privatgrundstück)", "Kein Vorgarten"),
        66: ("Teamarbeit nötig", "Keine Teamarbeit nötig"),
        67: ("Teil einer GeoTour", "Nicht Teil einer GeoTour"),
        69: ("Bonus-Cache", "Kein Bonus-Cache"),
        70: ("Powertrail", "Kein Powertrail"),
        71: ("Challenge-Cache", "Kein Challenge-Cache"),
        72: ("Lösungsprüfer auf geocaching.com", "Kein Lösungsprüfer"),
    ]
}

/// The attribute icons of a cache, wrapped into lines like the inline images in the Cachebox description; a tap
/// shows the text in a popover.
struct CacheAttributeIcons: View {
    let attributes: [CacheAttribute]
    var size: CGFloat = 32
    @State private var shown: CacheAttribute?

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(CacheAttribute.displayOrder(attributes), id: \.self) { attribute in
                Button {
                    shown = attribute
                } label: {
                    CacheAttributeIcon(attribute: attribute, size: size)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(attribute.title)
                .popover(isPresented: Binding(get: { shown == attribute },
                                              set: { if !$0, shown == attribute { shown = nil } })) {
                    Text(attribute.title)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 260)
                        .padding()
                        .presentationCompactAdaptation(.popover)
                }
            }
        }
    }
}

/// One attribute icon, see `CacheAttribute.Icon`.
struct CacheAttributeIcon: View {
    let attribute: CacheAttribute
    var size: CGFloat = 32
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        icon.overlay {
            if colorScheme == .dark, isFlat {
                RoundedRectangle(cornerRadius: size * 0.12).strokeBorder(Color(white: 0.45), lineWidth: 1)
            }
        }
    }

    /// The newer Cachebox icons (GeoTour, Challenge, Bonus, Power trail, solution checker) and the placeholder are
    /// flat black squares without the grey rim of the others; on a dark background they need a rim to be seen.
    private var isFlat: Bool {
        switch attribute.icon {
        case .unknown: true
        case .cachebox: attribute.isPositive && (67...71).contains(attribute.cacheboxIndex ?? 0)
        case .crossedOut: false
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch attribute.icon {
        case .cachebox(let name):
            CacheboxIcon(name: name, size: size)
        case .crossedOut(let name):
            CacheboxIcon(name: name, size: size)
                .overlay { CrossOut().stroke(Color.red, lineWidth: size / 16) }
        case .unknown:
            RoundedRectangle(cornerRadius: size * 0.16)
                .fill(Color.black)
                .overlay {
                    Text(attribute.isPositive ? "?" : "–?")
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }

    /// Red frame and diagonal from top left to bottom right, as in the Cachebox `_0` icons.
    private struct CrossOut: Shape {
        func path(in rect: CGRect) -> Path {
            let inset = rect.insetBy(dx: rect.width * 0.04, dy: rect.height * 0.04)
            var path = Path(roundedRect: inset, cornerRadius: rect.width * 0.14)
            path.move(to: CGPoint(x: inset.minX + inset.width * 0.08, y: inset.minY + inset.height * 0.08))
            path.addLine(to: CGPoint(x: inset.maxX - inset.width * 0.08, y: inset.maxY - inset.height * 0.08))
            return path
        }
    }
}

/// Places its subviews left to right at their ideal size and starts a new line when the width is used up.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, arrange(width: bounds.width, subviews).frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width: CGFloat, _ subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            usedWidth = max(usedWidth, x + size.width)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return (frames, CGSize(width: usedWidth, height: y + lineHeight))
    }
}
