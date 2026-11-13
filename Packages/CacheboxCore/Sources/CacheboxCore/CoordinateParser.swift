import Foundation

public extension Coordinate {
    /// Reads a coordinate typed or pasted as text (Cachebox `Coordinate.parseCoordinate`), e.g.
    ///
    ///     N 53° 04.548 E 008° 48.432        degrees and minutes (also "N53 04.548 / E8 48.432")
    ///     N 53.0758° E 8.8072°              degrees
    ///     N 53° 04' 32.88" E 8° 48' 25.92"  degrees, minutes, seconds
    ///     53° 04.548 N 008° 48.432 E        hemisphere behind the numbers
    ///     53.0758 8.8072                    signed decimal degrees
    ///     32U 487745 5880580                UTM (also "32U E 487745 N 5880580")
    ///
    /// Decimal commas are read as points. Returns nil if the text is none of these or out of range.
    init?(parsing text: String) {
        var text = text.uppercased().replacingOccurrences(of: ",", with: ".")
        for separator in ["\r", "\n", "\t"] { text = text.replacingOccurrences(of: separator, with: " ") }
        text = text.trimmingCharacters(in: .whitespaces)
        if let utm = Self.utm(text) {
            self = utm
            return
        }
        for mark in ["'", "\"", "′", "″", "’", "”", "/"] { text = text.replacingOccurrences(of: mark, with: " ") }
        text = text.replacingOccurrences(of: "°", with: " ")

        let latLetter = text.firstIndex { $0 == "N" || $0 == "S" }
        let lonLetter = text.firstIndex { $0 == "E" || $0 == "W" || $0 == "O" }
        guard let latLetter, let lonLetter else {
            // no hemispheres: two signed decimal numbers
            let numbers = text.split(separator: " ").compactMap { Double($0) }
            guard text.split(separator: " ").count == 2, numbers.count == 2 else { return nil }
            self.init(latitude: numbers[0], longitude: numbers[1])
            guard abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
            return
        }
        guard latLetter < lonLetter else { return nil }
        let latPart: Substring, lonPart: Substring
        if !text[..<latLetter].contains(where: \.isNumber) {
            // hemisphere in front: N 53 04.548 E 008 48.432
            latPart = text[text.index(after: latLetter)..<lonLetter]
            lonPart = text[text.index(after: lonLetter)...]
        } else {
            // hemisphere behind: 53 04.548 N 008 48.432 E
            latPart = text[..<latLetter]
            lonPart = text[text.index(after: latLetter)..<lonLetter]
            guard text[text.index(after: lonLetter)...].allSatisfy(\.isWhitespace) else { return nil }
        }
        guard var latitude = Self.angle(latPart), var longitude = Self.angle(lonPart),
              latitude <= 90, longitude <= 180 else { return nil }
        if text[latLetter] == "S" { latitude = -latitude }
        if text[lonLetter] == "W" { longitude = -longitude }
        self.init(latitude: latitude, longitude: longitude)
    }

    /// Degrees, degrees and minutes, or degrees, minutes and seconds.
    private static func angle(_ text: Substring) -> Double? {
        let parts = text.split(separator: " ")
        let numbers = parts.compactMap { Double($0) }
        guard numbers.count == parts.count, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        switch numbers.count {
        case 1:
            return numbers[0]
        case 2:
            guard numbers[0] == numbers[0].rounded(), numbers[1] < 60 else { return nil }
            return numbers[0] + numbers[1] / 60
        case 3:
            guard numbers[0] == numbers[0].rounded(), numbers[1] == numbers[1].rounded(),
                  numbers[1] < 60, numbers[2] < 60 else { return nil }
            return numbers[0] + numbers[1] / 60 + numbers[2] / 3600
        default:
            return nil
        }
    }

    private static func utm(_ text: String) -> Coordinate? {
        let pattern = /^(\d{1,2})\s*([C-HJ-NP-X])\s+(?:E\s*)?(\d+(?:\.\d+)?)\s+(?:N\s*)?(\d+(?:\.\d+)?)$/
        guard let match = text.wholeMatch(of: pattern), let zone = Int(match.1), (1...60).contains(zone),
              let band = match.2.first, let easting = Double(match.3), let northing = Double(match.4) else {
            return nil
        }
        return UTMCoordinate(zone: zone, band: band, easting: easting, northing: northing).coordinate
    }
}
