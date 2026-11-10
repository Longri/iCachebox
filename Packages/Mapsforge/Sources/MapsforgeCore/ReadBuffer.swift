// Port of org.mapsforge.map.reader.ReadBuffer and Deserializer.
// Licensed under LGPL-3.0 like the original mapsforge code.

import Foundation

/// Sequential reader over a block of bytes from a `.map` file.
/// All multi-byte integers are big-endian; variable-length integers use the
/// mapsforge VBE-U / VBE-S encoding.
struct ReadBuffer {
    private(set) var data: [UInt8]
    var position: Int = 0

    init(_ data: [UInt8]) {
        self.data = data
    }

    var size: Int { data.count }

    @inline(__always)
    mutating func readByte() -> Int8 {
        let b = Int8(bitPattern: data[position])
        position += 1
        return b
    }

    @inline(__always)
    mutating func readUInt8() -> UInt8 {
        let b = data[position]
        position += 1
        return b
    }

    mutating func readShort() -> Int16 {
        let v = Int16(bitPattern: UInt16(data[position]) << 8 | UInt16(data[position + 1]))
        position += 2
        return v
    }

    mutating func readInt() -> Int32 {
        var v: UInt32 = 0
        for i in 0..<4 { v = v << 8 | UInt32(data[position + i]) }
        position += 4
        return Int32(bitPattern: v)
    }

    mutating func readLong() -> Int64 {
        var v: UInt64 = 0
        for i in 0..<8 { v = v << 8 | UInt64(data[position + i]) }
        position += 8
        return Int64(bitPattern: v)
    }

    mutating func readFloat() -> Float {
        Float(bitPattern: UInt32(bitPattern: readInt()))
    }

    /// VBE-S: variable byte encoded signed integer.
    @inline(__always)
    mutating func readSignedInt() -> Int32 {
        var value: UInt32 = 0
        var shift: UInt32 = 0
        while data[position] & 0x80 != 0 {
            value |= UInt32(data[position] & 0x7f) << shift
            position += 1
            shift += 7
        }
        let last = data[position]
        position += 1
        let result = Int32(bitPattern: value | (UInt32(last & 0x3f) << shift))
        return (last & 0x40) != 0 ? 0 &- result : result
    }

    /// VBE-U: variable byte encoded unsigned integer.
    @inline(__always)
    mutating func readUnsignedInt() -> Int {
        var value: UInt32 = 0
        var shift: UInt32 = 0
        while data[position] & 0x80 != 0 {
            value |= UInt32(data[position] & 0x7f) << shift
            position += 1
            shift += 7
        }
        value |= UInt32(data[position]) << shift
        position += 1
        return Int(Int32(bitPattern: value))
    }

    mutating func readUTF8EncodedString() -> String? {
        readUTF8EncodedString(length: readUnsignedInt())
    }

    mutating func readUTF8EncodedString(length: Int) -> String? {
        guard length > 0, position + length <= data.count else { return nil }
        let s = String(decoding: data[position..<(position + length)], as: UTF8.self)
        position += length
        return s
    }

    mutating func skipBytes(_ n: Int) {
        position += n
    }

    /// Reads `count` tag ids and resolves them against the header tag table.
    /// Handles the mapsforge "variable value" tags (`%b`, `%i`, `%f`, `%h`, `%s`).
    mutating func readTags(_ table: [Tag], count: Int) -> [Tag]? {
        var ids = [Int]()
        ids.reserveCapacity(count)
        for _ in 0..<count {
            let id = readUnsignedInt()
            guard id >= 0, id < table.count else { return nil }
            ids.append(id)
        }
        var tags = [Tag]()
        tags.reserveCapacity(count + 3)
        for id in ids {
            var tag = table[id]
            let v = tag.value.utf8
            if v.count == 2, v.first == UInt8(ascii: "%") {
                let kind = v[v.index(after: v.startIndex)]
                var value: String? = tag.value
                switch kind {
                case UInt8(ascii: "b"):
                    value = String(readByte())
                case UInt8(ascii: "i"):
                    let i = readInt()
                    if tag.key.contains(":colour") {
                        value = "#" + String(UInt32(bitPattern: i), radix: 16)
                    } else {
                        value = String(i)
                    }
                case UInt8(ascii: "f"):
                    value = JavaFormat.floatToString(readFloat())
                case UInt8(ascii: "h"):
                    value = String(readShort())
                case UInt8(ascii: "s"):
                    value = readUTF8EncodedString()
                default:
                    break
                }
                tag = Tag(key: tag.key, value: value ?? "")
            }
            tags.append(tag)
        }
        return tags
    }
}

enum JavaFormat {
    /// Approximates `java.lang.Float.toString(float)` for the value range found in map files.
    static func floatToString(_ f: Float) -> String {
        if f.isNaN { return "NaN" }
        if f.isInfinite { return f < 0 ? "-Infinity" : "Infinity" }
        let a = abs(f)
        if a >= 1e-3 && a < 1e7 {
            var s = "\(f)"
            if !s.contains(".") && !s.contains("e") { s += ".0" }
            return s
        }
        // Java scientific notation, e.g. 1.0E7
        let exponent = Int(floor(log10(Double(a))))
        let mantissa = Double(f) / pow(10, Double(exponent))
        var m = "\(Float(mantissa))"
        if !m.contains(".") { m += ".0" }
        return "\(m)E\(exponent)"
    }
}
