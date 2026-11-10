// mfdump – developer tool for the Swift mapsforge port.
//
//   mfdump info   <file.map>
//   mfdump dump   <file.map> <z> <x> <y> [tag substring]
//   mfdump render <file.map> <z> <x> <y> <out.png> [scale] [theme.xml[#style,+overlay,-overlay]|default|osmarender]
//   mfdump grid   <file.map> <z> <x> <y> <cols> <rows> <out.png> [scale] [theme]
//   mfdump bench  <file.map> <z> <x> <y> <cols> <rows> [scale] [theme]

import CoreGraphics
import Foundation
import ImageIO
import MapsforgeCore
import MapsforgeRender
import UniformTypeIdentifiers

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

func loadTheme(_ arg: String?) throws -> RenderTheme {
    switch arg {
    case nil, "default": return try RenderTheme.builtIn("default")
    case "osmarender": return try RenderTheme.builtIn("osmarender")
    case let spec?:
        // theme.xml[#style[,+overlay,-overlay...]]
        let parts = spec.split(separator: "#", maxSplits: 1).map(String.init)
        let url = URL(fileURLWithPath: parts[0])
        guard parts.count == 2 else { return try RenderTheme.load(url: url) }
        var items = parts[1].split(separator: ",").map(String.init)
        let style = items.isEmpty || items[0].hasPrefix("+") || items[0].hasPrefix("-") ? nil : items.removeFirst()
        var overlays: [String: Bool] = [:]
        for item in items where item.count > 1 { overlays[String(item.dropFirst())] = item.hasPrefix("+") }
        let theme = try RenderTheme.load(url: url, menuCallback: { $0.categories(style: style, overlays: overlays) })
        if let menu = theme.styleMenu {
            let styles = menu.styles.map { "\($0.id) (\($0.title(language: "de") ?? ""))" }.joined(separator: ", ")
            FileHandle.standardError.write("styles: \(styles)\ncategories: \(theme.enabledCategories?.sorted() ?? [])\n".data(using: .utf8)!)
        }
        return theme
    }
}

func writePNG(_ image: CGImage, _ path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else { fail("cannot write \(path)") }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let args = CommandLine.arguments
guard args.count >= 3 else { fail("usage: mfdump info|dump|render|grid|bench <file.map> ...") }
let map: MapFile
do { map = try MapFile(url: URL(fileURLWithPath: args[2])) } catch { fail("cannot open map: \(error)") }
func int(_ i: Int) -> Int { guard args.count > i, let v = Int(args[i]) else { fail("missing integer argument #\(i)") }; return v }

switch args[1] {
case "info":
    let i = map.info
    print("version \(i.fileVersion), \(i.fileSize) bytes, zoom \(i.zoomLevelMin)-\(i.zoomLevelMax), bbox \(i.boundingBox)")
    print("start \(map.startPosition) z\(map.startZoomLevel), languages \(map.languages), created by \(i.createdBy ?? "-")")
    print("\(i.poiTags.count) POI tags, \(i.wayTags.count) way tags, \(i.numberOfSubFiles) sub-files")

case "dump":
    // prints POIs and ways of a tile, optionally only those whose tags contain a substring
    let (z, x, y) = (int(3), int(4), int(5))
    let filter = args.count > 6 ? args[6] : nil
    guard let result = map.readMapData(Tile(tileX: x, tileY: y, zoomLevel: z)) else { fail("no data") }
    func line(_ tags: [Tag]) -> String? {
        let s = tags.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        return filter.map { s.contains($0) } ?? true ? s : nil
    }
    for p in result.pointOfInterests { if let s = line(p.tags) { print("POI layer \(p.layer) \(p.position.latitude),\(p.position.longitude): \(s)") } }
    for w in result.ways {
        if let s = line(w.tags) {
            let closed = w.latLongs.first.map { $0.count > 2 && $0.first == $0.last } ?? false
            print("WAY layer \(w.layer) \(w.latLongs.map(\.count)) pts\(closed ? " closed" : ""): \(s)")
        }
    }

case "render":
    let (z, x, y) = (int(3), int(4), int(5))
    guard args.count > 6 else { fail("missing output path") }
    let scale = args.count > 7 ? CGFloat(Double(args[7]) ?? 2) : 2
    let renderer = TileRenderer(mapFile: map, theme: try loadTheme(args.count > 8 ? args[8] : nil))
    var stats = TileRenderer.Statistics()
    guard let img = renderer.renderTile(Tile(tileX: x, tileY: y, zoomLevel: z), scale: scale, statistics: &stats) else { fail("render failed") }
    writePNG(img, args[6])
    print(String(format: "z%d/%d/%d: %d POIs, %d ways, %d labels – read %.1f ms, match %.1f ms, draw %.1f ms",
                 z, x, y, stats.pois, stats.ways, stats.labels, stats.readTime * 1000, stats.matchTime * 1000, stats.drawTime * 1000))

case "grid":
    let (z, x0, y0, cols, rows) = (int(3), int(4), int(5), int(6), int(7))
    guard args.count > 8 else { fail("missing output path") }
    let scale = args.count > 9 ? CGFloat(Double(args[9]) ?? 1) : 1
    let renderer = TileRenderer(mapFile: map, theme: try loadTheme(args.count > 10 ? args[10] : nil))
    let tilePx = Int(256 * scale)
    guard let cg = CGContext(data: nil, width: cols * tilePx, height: rows * tilePx, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    else { fail("context") }
    // render in a shuffled order to exercise cross-tile label handling
    var tiles: [(Int, Int)] = []
    for r in 0..<rows { for c in 0..<cols { tiles.append((c, r)) } }
    tiles.shuffle()
    let start = Date()
    for (c, r) in tiles {
        guard let img = renderer.renderTile(Tile(tileX: x0 + c, tileY: y0 + r, zoomLevel: z), scale: scale) else { continue }
        cg.draw(img, in: CGRect(x: c * tilePx, y: (rows - 1 - r) * tilePx, width: tilePx, height: tilePx))
    }
    writePNG(cg.makeImage()!, args[8])
    print(String(format: "%d tiles in %.0f ms (%.1f ms/tile)", tiles.count, Date().timeIntervalSince(start) * 1000,
                 Date().timeIntervalSince(start) * 1000 / Double(tiles.count)))

case "bench":
    let (z, x0, y0, cols, rows) = (int(3), int(4), int(5), int(6), int(7))
    let scale = args.count > 8 ? CGFloat(Double(args[8]) ?? 2) : 2
    let renderer = TileRenderer(mapFile: map, theme: try loadTheme(args.count > 9 ? args[9] : nil))
    var total = TileRenderer.Statistics()
    var count = 0
    var worst = 0.0
    let start = Date()
    for r in 0..<rows {
        for c in 0..<cols {
            var s = TileRenderer.Statistics()
            _ = renderer.renderTile(Tile(tileX: x0 + c, tileY: y0 + r, zoomLevel: z), scale: scale, statistics: &s)
            total.readTime += s.readTime; total.matchTime += s.matchTime; total.drawTime += s.drawTime
            worst = max(worst, s.total)
            count += 1
        }
    }
    let wall = Date().timeIntervalSince(start)
    print(String(format: "z%d, %d tiles @%.0fx: avg %.1f ms/tile (read %.1f, match %.1f, draw %.1f), worst %.1f ms, wall %.0f ms",
                 z, count, scale, wall * 1000 / Double(count), total.readTime * 1000 / Double(count),
                 total.matchTime * 1000 / Double(count), total.drawTime * 1000 / Double(count), worst * 1000, wall * 1000))

default:
    fail("unknown command \(args[1])")
}
