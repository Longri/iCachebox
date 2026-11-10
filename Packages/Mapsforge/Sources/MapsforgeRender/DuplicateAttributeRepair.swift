// Not part of mapsforge: works around a difference between XML parsers.
// Licensed under LGPL-3.0 like the rest of MapsforgeRender.

import Foundation

/// Removes repeated attributes from start tags so that `XMLParser` accepts the document.
///
/// libxml2 (behind `XMLParser`) treats `<layer enabled="true" id="x" enabled="false">` as a fatal error,
/// Android's `XmlPullParser` used by mapsforge does not, and themes in the wild rely on that
/// (Freizeitkarte V5). Which value survives follows mapsforge's `RenderThemeHandler`:
/// stylemenu elements are read with `getStringAttribute`, which returns the first match;
/// all other elements loop over every attribute, so the last one wins.
enum DuplicateAttributeRepair {
    /// Elements whose attributes mapsforge reads with `RenderThemeHandler.getStringAttribute`.
    static let firstWins: Set<String> = ["stylemenu", "layer", "name", "cat", "overlay"]

    /// The repaired document, or nil if no start tag repeats an attribute.
    static func repair(_ data: Data) -> Data? {
        let b = [UInt8](data)
        let n = b.count
        var remove: [Range<Int>] = []

        func starts(_ s: StaticString, at p: Int) -> Bool {
            let count = s.utf8CodeUnitCount
            guard p + count <= n else { return false }
            return s.withUTF8Buffer { buf in (0..<count).allSatisfy { b[p + $0] == buf[$0] } }
        }
        /// Index just behind the next occurrence of `s` at or after `p` (or `n`).
        func skip(past s: StaticString, from p: Int) -> Int {
            var q = p
            while q < n, !starts(s, at: q) { q += 1 }
            return min(n, q + s.utf8CodeUnitCount)
        }
        func isSpace(_ c: UInt8) -> Bool { c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D }
        let lt = UInt8(ascii: "<"), gt = UInt8(ascii: ">"), slash = UInt8(ascii: "/"), eq = UInt8(ascii: "=")
        let dq = UInt8(ascii: "\""), sq = UInt8(ascii: "'")

        var i = 0
        while i < n {
            guard b[i] == lt else { i += 1; continue }
            if starts("<!--", at: i) { i = skip(past: "-->", from: i + 4); continue }
            if starts("<![CDATA[", at: i) { i = skip(past: "]]>", from: i + 9); continue }
            if starts("<?", at: i) || starts("<!", at: i) || starts("</", at: i) { i = skip(past: ">", from: i + 1); continue }

            // start tag: name, then attributes
            var p = i + 1
            let nameStart = p
            while p < n, !isSpace(b[p]), b[p] != gt, b[p] != slash { p += 1 }
            let tag = String(decoding: b[nameStart..<p], as: UTF8.self)
            var seen: [String: Range<Int>] = [:]
            while p < n {
                let attributeStart = p   // including the leading white space, so removal keeps the tag valid
                while p < n, isSpace(b[p]) { p += 1 }
                guard p < n, b[p] != gt, b[p] != slash else { break }
                let nameBegin = p
                while p < n, !isSpace(b[p]), b[p] != eq, b[p] != gt { p += 1 }
                let name = String(decoding: b[nameBegin..<p], as: UTF8.self)
                while p < n, isSpace(b[p]) { p += 1 }
                guard p < n, b[p] == eq else { break }   // malformed: leave it to XMLParser
                p += 1
                while p < n, isSpace(b[p]) { p += 1 }
                guard p < n, b[p] == dq || b[p] == sq else { break }
                let quote = b[p]
                p += 1
                while p < n, b[p] != quote { p += 1 }
                p = min(n, p + 1)
                let range = attributeStart..<p
                if let previous = seen[name] {
                    if firstWins.contains(tag) {
                        remove.append(range)
                    } else {
                        remove.append(previous)
                        seen[name] = range
                    }
                } else {
                    seen[name] = range
                }
            }
            i = p
        }
        guard !remove.isEmpty else { return nil }
        remove.sort { $0.lowerBound < $1.lowerBound }
        var out: [UInt8] = []
        out.reserveCapacity(n)
        var position = 0
        for r in remove {
            out += b[position..<r.lowerBound]
            position = r.upperBound
        }
        out += b[position...]
        return Data(out)
    }
}
