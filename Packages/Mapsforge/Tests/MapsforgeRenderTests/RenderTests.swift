import CoreGraphics
import Foundation
import Testing
@testable import MapsforgeCore
@testable import MapsforgeRender

enum TestData {
    static func url(_ name: String) -> URL? {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir.appendingPathComponent("TestData").appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }
}

@Suite("Rendering")
struct RenderTests {
    @Test func builtInThemesParse() throws {
        for name in ["default", "osmarender"] {
            let theme = try RenderTheme.builtIn(name)
            func count(_ r: Rule) -> Int { 1 + r.subRules.map(count).reduce(0, +) }
            #expect(theme.rules.map(count).reduce(0, +) > 300, "\(name)")
            #expect(theme.levels > 100, "\(name)")
        }
    }

    /// `src` references of symbols, area patterns and line symbols that cannot be loaded.
    static func unloadableResources(_ theme: RenderTheme) -> Set<String> {
        var missing: Set<String> = []
        func visit(_ r: Rule) {
            for i in r.instructions {
                if let s = i as? SymbolInstruction, let src = s.src, s.bitmap == nil { missing.insert(src) }
                if let a = i as? AreaInstruction, let src = a.src,
                   theme.resources.bitmap(src, width: a.symbolWidth, height: a.symbolHeight, percent: a.percent) == nil {
                    missing.insert(src)
                }
                if let l = i as? LineSymbolInstruction, let src = l.src,
                   theme.resources.bitmap(src, width: l.width, height: l.height, percent: l.percent) == nil {
                    missing.insert(src)
                }
            }
            r.subRules.forEach(visit)
        }
        theme.rules.forEach(visit)
        return missing
    }

    @Test func allThemeSymbolsLoad() throws {
        let missing = Self.unloadableResources(try RenderTheme.builtIn())
        #expect(missing.isEmpty, "unloadable resources: \(missing.sorted())")
    }

    @Test func styleMenuSelectsCategories() throws {
        let xml = """
        <rendertheme version="5" map-background="#FFFFFF">
          <stylemenu id="menu" defaultvalue="hike" defaultlang="en">
            <layer id="routes" enabled="true"><cat id="routes"/></layer>
            <layer id="shops" enabled="false"><name lang="en" value="Shops"/><cat id="shops"/></layer>
            <layer id="base"><cat id="common"/><overlay id="routes"/></layer>
            <layer id="hike" parent="base" visible="true">
              <name lang="en" value="Hiking"/><name lang="de" value="Wandern"/>
              <cat id="hike"/><overlay id="shops"/><overlay id="later"/>
            </layer>
            <layer id="city" visible="true"><cat id="city"/></layer>
            <layer id="later"><cat id="later"/></layer>
          </stylemenu>
          <rule e="way" k="highway" v="*">
            <line stroke="#000000" cat="city"/>
            <line stroke="#111111"/>
          </rule>
          <rule cat="city" e="way" k="building" v="*"><area fill="#222222"/></rule>
          <rule cat="hike" e="way" k="path" v="*"><line stroke="#333333"/></rule>
        </rendertheme>
        """
        func parse(_ callback: RenderThemeMenuCallback?) throws -> RenderTheme {
            try RenderThemeParser(data: Data(xml.utf8), resources: ThemeResources(baseDirectories: []),
                                  menuCallback: callback).parse()
        }
        let theme = try parse { $0.categories() }
        let menu = try #require(theme.styleMenu)
        #expect(menu.styles.map(\.id) == ["hike", "city"])
        #expect(menu.layer("hike")?.title(language: "de") == "Wandern")
        #expect(menu.layer("hike")?.title(language: "fr") == "Hiking")
        // parent categories + overlays are inherited; overlays defined later are ignored (mapsforge)
        #expect(menu.layer("hike")?.overlays.map(\.id) == ["routes", "shops"])
        #expect(theme.enabledCategories == ["common", "hike", "routes"])
        #expect(menu.categories(style: "hike", overlays: ["shops": true, "routes": false]) == ["common", "hike", "shops"])
        #expect(menu.categories(style: "nope") == nil)
        // invisible rules and instructions are dropped, levels stay as in the full theme
        #expect(theme.rules.count == 2)
        #expect(theme.rules[0].instructions.count == 1)
        #expect(theme.levels == 4)
        #expect(try parse(nil).rules.count == 3)   // no selection = all categories
    }

    /// Elevate (OpenAndroMaps) – only if TestData/elevate is present (not in git).
    @Test(.enabled(if: TestData.url("elevate/Elevate.xml") != nil))
    func elevateThemeLoads() throws {
        let url = try #require(TestData.url("elevate/Elevate.xml"))
        let all = try RenderTheme.load(url: url, menuCallback: { _ in nil })
        let menu = try #require(all.styleMenu)
        #expect(menu.defaultValue == "elv-hiking")
        #expect(menu.styles.map(\.id) == ["elv-hiking", "elv-city", "elv-cycling", "elv-mtb"])
        let missing = Self.unloadableResources(all)
        #expect(missing.isEmpty, "unloadable resources: \(missing.sorted())")

        let hiking = try RenderTheme.load(url: url)
        #expect(hiking.enabledCategories?.contains("hike") == true)
        #expect(hiking.enabledCategories?.contains("city") == false)
        #expect(hiking.levels == all.levels)

        guard let mapURL = TestData.url("Hamburg_oam.osm.map") else { return }
        let renderer = TileRenderer(mapFile: try MapFile(url: mapURL), theme: hiking)
        var stats = TileRenderer.Statistics()
        let image = try #require(renderer.renderTile(Tile(tileX: 17293, tileY: 10590, zoomLevel: 15), scale: 2, statistics: &stats))
        #expect(image.width == 512)
        #expect(stats.ways > 1000 && stats.labels > 10)
    }

    /// Repeated attributes (Freizeitkarte V5) are rejected by XMLParser; `load` retries without them.
    @Test func duplicateAttributesAreRepaired() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!-- <layer enabled="1" enabled="2"> inside a comment stays untouched -->
        <rendertheme xmlns="http://mapsforge.org/renderTheme" version="5">
          <stylemenu id="m" defaultvalue="base" defaultlang="en">
            <layer id="routes" enabled="true" visible="false" enabled="false"><cat id="routes"/></layer>
            <layer id="base" visible="true"><cat id="common"/><overlay id="routes"/></layer>
          </stylemenu>
          <rule e="way" k="highway" v="*"><line stroke="#000000" stroke-width="1" stroke-width = '3'/></rule>
          <rule cat="routes" e="way" k="route" v="*"><line stroke="#111111"/></rule>
        </rendertheme>
        """
        let repaired = String(decoding: try #require(DuplicateAttributeRepair.repair(Data(xml.utf8))), as: UTF8.self)
        // stylemenu: first value wins (getStringAttribute), rule instructions: last value wins
        #expect(repaired.contains(#"<layer id="routes" enabled="true" visible="false">"#))
        #expect(repaired.contains(##"<line stroke="#000000" stroke-width = '3'/>"##))
        #expect(repaired.contains(#"<layer enabled="1" enabled="2">"#))
        #expect(DuplicateAttributeRepair.repair(Data(repaired.utf8)) == nil)

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("dup-\(UUID().uuidString).xml")
        try Data(xml.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let theme = try RenderTheme.load(url: file)
        #expect(theme.enabledCategories == ["common", "routes"])
        #expect(theme.rules.count == 2)
    }

    /// Freizeitkarte V5 theme – only if TestData/freizeitkarte-v5 is present (not in git).
    @Test(.enabled(if: TestData.url("freizeitkarte-v5/freizeitkarte-v5.xml") != nil))
    func freizeitkarteThemeLoads() throws {
        let url = try #require(TestData.url("freizeitkarte-v5/freizeitkarte-v5.xml"))
        let theme = try RenderTheme.load(url: url)
        #expect(theme.styleMenu != nil)
        let missing = Self.unloadableResources(theme)
        #expect(missing.isEmpty, "unloadable resources: \(missing.sorted())")
    }

    @Test func rendersReferenceTiles() throws {
        let map = try MapFile(url: try #require(TestData.url("bremen.map")))
        let renderer = TileRenderer(mapFile: map, theme: try RenderTheme.builtIn())
        for (z, x, y) in [(12, 2148, 1332), (14, 8592, 5331), (16, 34370, 21324)] {
            var stats = TileRenderer.Statistics()
            let image = try #require(renderer.renderTile(Tile(tileX: x, tileY: y, zoomLevel: z), scale: 2, statistics: &stats))
            #expect(image.width == 512)
            #expect(stats.ways > 0)
        }
    }

    @Test func svgPathParser() {
        let p = SVGPathParser.parse("M10-20l5.5,0h-1e1v3.5z m1 1 2 2 a1 1 0 01 2 2")
        let box = p.boundingBoxOfPath
        // M(10,-20) l→(15.5,-20) h→(5.5,-20) v→(5.5,-16.5) z, m→(11,-19) l→(13,-17) a→(15,-15)
        #expect(abs(box.minX - 5.5) < 0.01 && abs(box.maxX - 15.5) < 0.01)
        #expect(abs(box.minY + 20) < 0.01 && abs(box.maxY + 15) < 0.01)
        #expect(!p.isEmpty)
    }
}
