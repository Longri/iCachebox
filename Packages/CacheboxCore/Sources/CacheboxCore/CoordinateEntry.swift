import Foundation

/// The state of the coordinate input of the waypoint editor (Cachebox `EditCoord`): every character of the coordinate
/// is a cell of its own, a number pad writes into the cell with the focus, and the focus then jumps to the next cell.
///
/// Formats (Cachebox pages 0…3, buttons Dec/Min/Sec/UTM):
///
///     degrees   N_48.46270  E009.28468      9 cells per line: hemisphere, 3 degrees, 5 decimals
///     minutes   N_48°27.762 E009°17.081     9 cells per line: hemisphere, 3 degrees, 2 minutes, 3 decimals
///     seconds   N_48°27'45.71 E009°17'04.86 10 cells per line: hemisphere, 3 degrees, 2 min, 2 sec, 2 decimals
///     utm       easting 6 cells, northing 8 cells, zone 2 digits + band letter
///
/// In the first three formats the cells of the latitude come first, then those of the longitude. Cell 0 of each line
/// is the hemisphere (a tap switches N/S or E/W), the first degree cell of the latitude is not shown (latitudes have
/// two degree digits). The focus starts on the first decimal of the latitude; after its last cell it jumps to the
/// first decimal of the longitude, after the last cell of the longitude back to the degrees of the latitude
/// (Cachebox `setNextFocus`, `focusStartLon`). Usually only the decimals change, so they come first.
///
/// For UTM the focus runs through easting (0…5), northing (6…13), zone digits (14, 15) and the band (16), then starts
/// again with the easting (Cachebox `setNextUTMFocus`). A blank key empties a cell, the band is typed as a letter.
public struct CoordinateEntry: Equatable, Sendable {
    public enum Format: Int, CaseIterable, Sendable {
        case degrees, minutes, seconds, utm

        /// Title of the toggle button (Cachebox `bDec`, `bMin`, `bSec`, `bUtm`).
        public var title: String {
            switch self {
            case .degrees: "Dec"
            case .minutes: "Min"
            case .seconds: "Sec"
            case .utm: "UTM"
            }
        }

        /// Cells of one line (latitude or longitude); UTM has its own layout.
        var lineLength: Int {
            switch self {
            case .degrees, .minutes: 9
            case .seconds: 10
            case .utm: 0
            }
        }

        /// Where the focus starts in each line: the first decimal of the minutes (or degrees, or the seconds).
        var firstEditedCell: Int {
            switch self {
            case .degrees: 4
            case .minutes, .seconds: 6
            case .utm: 0
            }
        }
    }

    /// Something in a line of cells: a cell, or a separator drawn between them (half a cell wide in Cachebox).
    public enum LineItem: Hashable, Sendable {
        case cell(Int)
        case separator(String)
    }

    // UTM cells
    public static let eastingCells = 0..<6
    public static let northingCells = 6..<14
    public static let zoneCells = 14..<16
    public static let bandCell = 16
    static let utmCellCount = 17
    /// Band letters that can be typed (Cachebox `utmTest`); the bands themselves are C…X.
    public static let bandLetters = "ABCDEFGHJKLMNPQRSTUVWXYZ"

    public private(set) var format: Format
    /// One character per cell, "" for an empty cell.
    public private(set) var cells: [String]
    /// The cell that takes the next key.
    public private(set) var focus: Int
    /// The coordinate the cells were last filled from or parsed into.
    public private(set) var coordinate: Coordinate

    /// Starts with degrees and minutes, like Cachebox.
    public init(coordinate: Coordinate, format: Format = .minutes) {
        self.coordinate = coordinate
        self.format = format
        cells = []
        focus = 0
        fill()
    }

    // MARK: - Layout

    /// The two lines of the formats with latitude and longitude; empty for UTM.
    public var lines: [[LineItem]] {
        let n = format.lineLength
        switch format {
        case .degrees:
            return [0, n].map { o in (0..<4).map { .cell(o + $0) } + [.separator(".")] + (4..<9).map { .cell(o + $0) }
                + [.separator("°")] }
        case .minutes:
            return [0, n].map { o in (0..<4).map { .cell(o + $0) } + [.separator("°"), .cell(o + 4), .cell(o + 5),
                    .separator("."), .cell(o + 6), .cell(o + 7), .cell(o + 8)] }
        case .seconds:
            return [0, n].map { o in (0..<4).map { .cell(o + $0) } + [.separator("°"), .cell(o + 4), .cell(o + 5),
                    .separator("'"), .cell(o + 6), .cell(o + 7), .separator("."), .cell(o + 8), .cell(o + 9)] }
        case .utm:
            return []
        }
    }

    /// The cell is drawn: not the first degree digit of the latitude, not the unused easting cells (Cachebox hides
    /// `btnUTMLon[6]`, `[7]` – this layout has no such cells).
    public func isVisible(_ cell: Int) -> Bool {
        format == .utm || cell != 1
    }

    /// Hemisphere cells switch with a tap instead of taking digits.
    public func isHemisphere(_ cell: Int) -> Bool {
        format != .utm && (cell == 0 || cell == format.lineLength)
    }

    /// The focus is on the band letter, which comes from the keyboard instead of the number pad.
    public var expectsLetter: Bool { format == .utm && focus == Self.bandCell }

    // MARK: - Input

    /// Switches the format; the coordinate is parsed from the shown one first (Cachebox `showPage`, which keeps the
    /// last valid coordinate if the cells do not make one).
    public mutating func select(_ newFormat: Format) {
        guard newFormat != format else { return }
        if let parsed = parse() { coordinate = parsed }
        format = newFormat
        fill()
    }

    /// A tap on a cell: the hemisphere switches, any other cell takes the focus.
    public mutating func tap(_ cell: Int) {
        guard cells.indices.contains(cell), isVisible(cell) else { return }
        if isHemisphere(cell) {
            switch cells[cell] {
            case "N": cells[cell] = "S"
            case "S": cells[cell] = "N"
            case "E": cells[cell] = "W"
            default: cells[cell] = "E"
            }
        } else {
            focus = cell
        }
    }

    /// A key of the number pad: writes the digit into the focused cell and moves on.
    public mutating func enter(digit: Int) {
        guard (0...9).contains(digit), !expectsLetter else { return }
        cells[focus] = String(digit)
        advance()
    }

    /// The blank key, only for UTM (Cachebox `leerTaste`): empties the focused cell and moves on.
    public mutating func enterBlank() {
        guard format == .utm, !expectsLetter else { return }
        cells[focus] = ""
        advance()
    }

    /// A letter from the keyboard for the UTM band; other characters are ignored.
    public mutating func enter(letter: Character) {
        let upper = Character(letter.uppercased())
        guard expectsLetter, Self.bandLetters.contains(upper) else { return }
        cells[Self.bandCell] = String(upper)
        advance()
    }

    private mutating func advance() {
        if format == .utm {
            focus = (focus + 1) % Self.utmCellCount
            return
        }
        let n = format.lineLength
        var next = focus + 1
        if next == n { next = n + format.firstEditedCell }   // end of the latitude: decimals of the longitude
        if next == 2 * n { next = 2 }                         // end of the longitude: degrees of the latitude
        focus = next
    }

    // MARK: - Cells from a coordinate

    private mutating func fill() {
        switch format {
        case .degrees, .minutes, .seconds:
            cells = line(coordinate.latitude, positive: "N", negative: "S")
                + line(coordinate.longitude, positive: "E", negative: "W")
            focus = format.firstEditedCell
        case .utm:
            cells = Array(repeating: "", count: Self.utmCellCount)
            if let utm = UTMCoordinate(coordinate) {
                put(String(Int(utm.easting.rounded())), at: Self.eastingCells)
                put(String(Int(utm.northing.rounded())), at: Self.northingCells)
                put(String(format: "%02d", utm.zone), at: Self.zoneCells)
                cells[Self.bandCell] = String(utm.band)
            }
            focus = 0
        }
    }

    /// Writes the characters from the left of a range of cells; the rest stays empty (Cachebox does the same).
    private mutating func put(_ text: String, at range: Range<Int>) {
        for (offset, character) in text.prefix(range.count).enumerated() {
            cells[range.lowerBound + offset] = String(character)
        }
    }

    /// Digits of one line. Rounded on the last digit as a whole number, so that 59.9996' becomes the next degree
    /// instead of "60.000" (Cachebox rounds the decimals alone and could show 1000 thousandths).
    private func line(_ value: Double, positive: String, negative: String) -> [String] {
        let v = abs(value)
        let digits: String
        switch format {
        case .degrees:
            let units = Int((v * 100_000).rounded())
            digits = String(format: "%03d%05d", units / 100_000, units % 100_000)
        case .minutes:
            let units = Int((v * 60_000).rounded())   // thousandths of a minute
            digits = String(format: "%03d%02d%03d", units / 60_000, units % 60_000 / 1000, units % 1000)
        case .seconds:
            let units = Int((v * 360_000).rounded())  // hundredths of a second
            digits = String(format: "%03d%02d%02d%02d", units / 360_000, units % 360_000 / 6000,
                            units % 6000 / 100, units % 100)
        case .utm:
            digits = ""
        }
        return [value < 0 ? negative : positive] + digits.map(String.init)
    }

    // MARK: - Coordinate from the cells

    /// The coordinate of the cells, or nil if they do not make one (Cachebox `parseView`; here also minutes and
    /// seconds must be below 60 and latitudes within ±90°).
    public func parse() -> Coordinate? {
        if format == .utm { return parseUTM() }
        let n = format.lineLength
        guard let latitude = parseLine(Array(cells[0..<n]), skipping: 1),
              let longitude = parseLine(Array(cells[n..<2 * n]), skipping: nil),
              abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }

    private func parseLine(_ line: [String], skipping hidden: Int?) -> Double? {
        func number(_ range: Range<Int>) -> Int? {
            let text = range.filter { $0 != hidden }.map { line[$0] }.joined()
            guard text.count == range.filter({ $0 != hidden }).count else { return nil }   // an empty cell
            return Int(text)
        }
        guard let degrees = number(1..<4) else { return nil }
        var value: Double
        switch format {
        case .degrees:
            guard let decimals = number(4..<9) else { return nil }
            value = Double(degrees) + Double(decimals) / 100_000
        case .minutes:
            guard let minutes = number(4..<6), let decimals = number(6..<9), minutes < 60 else { return nil }
            value = Double(degrees) + (Double(minutes) + Double(decimals) / 1000) / 60
        case .seconds:
            guard let minutes = number(4..<6), let seconds = number(6..<8), let decimals = number(8..<10),
                  minutes < 60, seconds < 60 else { return nil }
            value = Double(degrees) + Double(minutes) / 60 + (Double(seconds) + Double(decimals) / 100) / 3600
        case .utm:
            return nil
        }
        if line[0] == "S" || line[0] == "W" { value = -value }
        return value
    }

    private func parseUTM() -> Coordinate? {
        func joined(_ range: Range<Int>) -> String { range.map { cells[$0] }.joined() }
        guard let easting = Double(joined(Self.eastingCells)), let northing = Double(joined(Self.northingCells)),
              let zone = Int(joined(Self.zoneCells)), (1...60).contains(zone),
              let band = cells[Self.bandCell].first, UTMCoordinate.bands.contains(band) else { return nil }
        let coordinate = UTMCoordinate(zone: zone, band: band, easting: easting, northing: northing).coordinate
        guard coordinate.latitude.isFinite, coordinate.longitude.isFinite, abs(coordinate.latitude) <= 90 else {
            return nil
        }
        return coordinate
    }
}
