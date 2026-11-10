// Port of org.mapsforge.map.rendertheme.rule.* (RenderTheme, RenderThemeHandler,
// RuleBuilder, Rule, PositiveRule, NegativeRule, matchers).
// Licensed under LGPL-3.0 like the original mapsforge code.

import CoreGraphics
import Foundation
import MapsforgeCore

public struct RenderThemeError: Error, CustomStringConvertible {
    public let description: String
    init(_ d: String) { description = d }
}

enum ElementType {
    case node, way, any
    init(_ s: String) throws {
        switch s {
        case "node": self = .node
        case "way": self = .way
        case "any": self = .any
        default: throw RenderThemeError("invalid element value: \(s)")
        }
    }
}

enum Closed {
    case yes, no, any
    init(_ s: String) throws {
        switch s {
        case "yes": self = .yes
        case "no": self = .no
        case "any": self = .any
        default: throw RenderThemeError("invalid closed value: \(s)")
        }
    }
}

/// Tag matching of a rule (`k`/`v` attributes).
enum TagMatcher {
    /// nil = wildcard `*`
    case positive(keys: Set<String>?, values: Set<String>?)
    /// `v` contained `~`: matches if no tag has one of the keys, or any tag value is in `values`.
    case negative(keys: Set<String>, values: Set<String>)

    @inline(__always)
    func matches(_ tags: [Tag]) -> Bool {
        switch self {
        case let .positive(keys, values):
            for tag in tags {
                if (keys == nil || keys!.contains(tag.key)) && (values == nil || values!.contains(tag.value)) {
                    return true
                }
            }
            return false
        case let .negative(keys, values):
            if !tags.contains(where: { keys.contains($0.key) }) { return true }
            return tags.contains(where: { values.contains($0.value) })
        }
    }
}

final class Rule {
    let category: String?
    let element: ElementType
    let closed: Closed
    let zoomMin: Int
    let zoomMax: Int
    let matcher: TagMatcher
    var instructions: [RenderInstruction] = []
    var subRules: [Rule] = []

    init(attributes: [String: String]) throws {
        guard let e = attributes["e"], let k = attributes["k"], let v = attributes["v"] else {
            throw RenderThemeError("rule requires e, k and v attributes")
        }
        element = try ElementType(e)
        closed = try attributes["closed"].map(Closed.init) ?? .any
        category = attributes["cat"]
        zoomMin = Int(attributes["zoom-min"] ?? "") ?? 0
        zoomMax = Int(attributes["zoom-max"] ?? "") ?? 127
        guard zoomMin <= zoomMax else { throw RenderThemeError("zoom-min > zoom-max") }

        let keyList = k.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        var valueList = v.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if let i = valueList.firstIndex(of: "~") {
            valueList.remove(at: i)
            matcher = .negative(keys: Set(keyList), values: Set(valueList))
        } else {
            matcher = .positive(keys: keyList.first == "*" ? nil : Set(keyList),
                                values: valueList.first == "*" ? nil : Set(valueList))
        }
    }

    @inline(__always)
    func matchesNode(_ tags: [Tag], zoom: Int) -> Bool {
        zoomMin <= zoom && zoomMax >= zoom && element != .way && matcher.matches(tags)
    }

    @inline(__always)
    func matchesWay(_ tags: [Tag], zoom: Int, closed c: Closed) -> Bool {
        zoomMin <= zoom && zoomMax >= zoom && element != .node
            && (closed == .any || closed == c) && matcher.matches(tags)
    }

    func collectNode(_ tags: [Tag], zoom: Int, into list: inout [RenderInstruction]) {
        guard matchesNode(tags, zoom: zoom) else { return }
        list.append(contentsOf: instructions)
        for r in subRules { r.collectNode(tags, zoom: zoom, into: &list) }
    }

    func collectWay(_ tags: [Tag], zoom: Int, closed: Closed, into list: inout [RenderInstruction]) {
        guard matchesWay(tags, zoom: zoom, closed: closed) else { return }
        list.append(contentsOf: instructions)
        for r in subRules { r.collectWay(tags, zoom: zoom, closed: closed, into: &list) }
    }
}

/// A parsed mapsforge render theme (XML version ≤ 6).
public final class RenderTheme: @unchecked Sendable {
    public let mapBackground: ARGB
    public let mapBackgroundOutside: ARGB?
    public let baseStrokeWidth: Double
    public let baseTextSize: Double
    /// Number of drawing levels (each area/line/circle gets its own level, in document order).
    public private(set) var levels = 0
    /// The theme's `<stylemenu>`, if any.
    public private(set) var styleMenu: RenderThemeStyleMenu?
    /// Categories selected when parsing (nil = all categories are rendered).
    public private(set) var enabledCategories: Set<String>?

    var rules: [Rule] = []
    let resources: ThemeResources

    private struct CacheKey: Hashable {
        let tags: [Tag]
        let zoom: Int
        let closed: Closed
    }
    private var nodeCache: [CacheKey: [RenderInstruction]] = [:]
    private var wayCache: [CacheKey: [RenderInstruction]] = [:]
    private let cacheLock = NSLock()

    init(mapBackground: ARGB, mapBackgroundOutside: ARGB?, baseStrokeWidth: Double, baseTextSize: Double,
         resources: ThemeResources) {
        self.mapBackground = mapBackground
        self.mapBackgroundOutside = mapBackgroundOutside
        self.baseStrokeWidth = baseStrokeWidth
        self.baseTextSize = baseTextSize
        self.resources = resources
    }

    /// Loads a theme from an XML file. Relative `src` references are resolved against the theme's
    /// directory and its parent (mapsforge `jar:`/`file:`/`assets:` prefixes are accepted).
    ///
    /// `menuCallback` selects the categories once the `<stylemenu>` is parsed, like mapsforge's
    /// `XmlRenderThemeMenuCallback`. Deviation: without a callback mapsforge renders all categories,
    /// which for themes like Elevate draws every style on top of each other; here the menu's default
    /// style with its enabled overlays is used instead.
    public static func load(url: URL, menuCallback: RenderThemeMenuCallback? = nil) throws -> RenderTheme {
        let data = try Data(contentsOf: url)
        let resources = ThemeResources(baseDirectories: [url.deletingLastPathComponent(),
                                                         url.deletingLastPathComponent().deletingLastPathComponent()])
        return try RenderThemeParser(data: data, resources: resources,
                                     menuCallback: menuCallback ?? { $0.categories() }).parse()
    }

    /// The `<stylemenu>` of a theme, e.g. for a style chooser (parses the whole theme; symbols load lazily).
    public static func styleMenu(url: URL) throws -> RenderThemeStyleMenu? {
        var menu: RenderThemeStyleMenu?
        _ = try load(url: url, menuCallback: { menu = $0; return nil })
        return menu
    }

    /// The internal themes shipped with this package ("default", "osmarender").
    public static func builtIn(_ name: String = "default") throws -> RenderTheme {
        guard let url = Bundle.module.url(forResource: name, withExtension: "xml", subdirectory: "themes/mapsforge") else {
            throw RenderThemeError("built-in theme not found: \(name)")
        }
        return try load(url: url)
    }

    func setLevels(_ n: Int) { levels = n }
    func setStyleMenu(_ menu: RenderThemeStyleMenu, categories: Set<String>?) {
        styleMenu = menu
        enabledCategories = categories
    }

    /// Matching instructions for a POI, in rule order. Cached like mapsforge (name tag ignored).
    func instructions(forNode tags: [Tag], zoom: Int) -> [RenderInstruction] {
        let key = CacheKey(tags: tags.filter { $0.key != "name" }, zoom: zoom, closed: .no)
        cacheLock.lock()
        if let hit = nodeCache[key] { cacheLock.unlock(); return hit }
        cacheLock.unlock()
        var list: [RenderInstruction] = []
        for r in rules { r.collectNode(tags, zoom: zoom, into: &list) }
        cacheLock.lock()
        if nodeCache.count > 8192 { nodeCache.removeAll(keepingCapacity: true) }
        nodeCache[key] = list
        cacheLock.unlock()
        return list
    }

    func instructions(forWay tags: [Tag], zoom: Int, closed: Closed) -> [RenderInstruction] {
        let key = CacheKey(tags: tags.filter { $0.key != "name" }, zoom: zoom, closed: closed)
        cacheLock.lock()
        if let hit = wayCache[key] { cacheLock.unlock(); return hit }
        cacheLock.unlock()
        var list: [RenderInstruction] = []
        for r in rules { r.collectWay(tags, zoom: zoom, closed: closed, into: &list) }
        cacheLock.lock()
        if wayCache.count > 8192 { wayCache.removeAll(keepingCapacity: true) }
        wayCache[key] = list
        cacheLock.unlock()
        return list
    }
}

// MARK: - XML parsing

final class RenderThemeParser: NSObject, XMLParserDelegate {
    private let data: Data
    private let resources: ThemeResources
    private var theme: RenderTheme?
    private var ruleStack: [Rule] = []
    private var level = 0
    private var symbols: [String: SymbolInstruction] = [:]
    private var error: Error?
    private let menuCallback: RenderThemeMenuCallback?
    private var styleMenu: RenderThemeStyleMenu?
    private var currentLayer: RenderThemeStyleLayer?
    /// nil = all categories visible (RenderThemeHandler.categories)
    private var categories: Set<String>?

    init(data: Data, resources: ThemeResources, menuCallback: RenderThemeMenuCallback? = nil) {
        self.data = data
        self.resources = resources
        self.menuCallback = menuCallback
    }

    private func isVisible(category: String?) -> Bool {
        categories == nil || category == nil || categories!.contains(category!)
    }

    func parse() throws -> RenderTheme {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        let ok = parser.parse()
        if let error { throw error }
        guard ok, let theme else {
            throw RenderThemeError("XML parse error: \(parser.parserError?.localizedDescription ?? "missing rendertheme element")")
        }
        theme.setLevels(level)
        return theme
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        guard error == nil else { return }
        do {
            try start(name, attributes)
        } catch {
            self.error = error
            parser.abortParsing()
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard error == nil else { return }
        if name == "rule" {
            // invisible rules are dropped with all their sub-rules; levels are already counted
            let rule = ruleStack.removeLast()
            guard isVisible(category: rule.category) else { return }
            if ruleStack.isEmpty {
                theme?.rules.append(rule)
            } else {
                ruleStack[ruleStack.count - 1].subRules.append(rule)
            }
        } else if name == "stylemenu", let styleMenu {
            // the menu precedes all rules, so the selection applies to the whole theme
            categories = menuCallback?(styleMenu)
            theme?.setStyleMenu(styleMenu, categories: categories)
        }
    }

    private func start(_ name: String, _ a: [String: String]) throws {
        switch name {
        case "rendertheme":
            let version = Int(a["version"] ?? "") ?? 0
            guard version <= 6 else { throw RenderThemeError("unsupported render theme version: \(version)") }
            theme = RenderTheme(
                mapBackground: try a["map-background"].map(ARGB.parse) ?? .white,
                mapBackgroundOutside: try a["map-background-outside"].map(ARGB.parse),
                baseStrokeWidth: Double(a["base-stroke-width"] ?? "") ?? 1,
                baseTextSize: Double(a["base-text-size"] ?? "") ?? 1,
                resources: resources)
        case "rule":
            ruleStack.append(try Rule(attributes: a))
        case "area":
            try add(AreaInstruction(a, level: nextLevel(), resources: resources))
        case "line":
            try add(LineInstruction(a, level: nextLevel(), resources: resources))
        case "circle":
            try add(CircleInstruction(a, level: nextLevel()))
        case "caption":
            try add(CaptionInstruction(a, symbols: symbols))
        case "pathText":
            try add(PathTextInstruction(a))
        case "symbol":
            let s = try SymbolInstruction(a, resources: resources)
            if let id = s.id { symbols[id] = s }
            try add(s)
        case "lineSymbol":
            try add(LineSymbolInstruction(a, resources: resources))
        case "hillshading":
            _ = nextLevel()   // reserves a level like mapsforge; rendering not implemented yet
        case "stylemenu":
            styleMenu = RenderThemeStyleMenu(id: a["id"] ?? "", defaultLanguage: a["defaultlang"] ?? "en",
                                             defaultValue: a["defaultvalue"] ?? "")
        case "layer":
            guard let styleMenu, let id = a["id"] else { throw RenderThemeError("layer outside of stylemenu or without id") }
            let layer = styleMenu.createLayer(id: id, visible: a["visible"] == "true", enabled: a["enabled"] == "true")
            if let parent = a["parent"].flatMap(styleMenu.layer) {
                parent.categories.forEach(layer.addCategory)
                parent.overlays.forEach(layer.addOverlay)
            }
            currentLayer = layer
        case "cat":
            if let id = a["id"] { currentLayer?.addCategory(id) }
        case "name":
            if let lang = a["lang"], let value = a["value"] { currentLayer?.addTranslation(language: lang, title: value) }
        case "overlay":
            // mapsforge ignores overlays that refer to layers defined later
            if let overlay = a["id"].flatMap({ styleMenu?.layer($0) }) { currentLayer?.addOverlay(overlay) }
        default:
            break   // mapsforge throws on unknown elements; we are lenient
        }
    }

    private func nextLevel() -> Int {
        defer { level += 1 }
        return level
    }

    private func add(_ instruction: RenderInstruction) throws {
        guard !ruleStack.isEmpty else { throw RenderThemeError("render instruction outside of rule") }
        guard isVisible(category: instruction.category) else { return }
        ruleStack[ruleStack.count - 1].instructions.append(instruction)
    }
}

// MARK: - Colors

public struct ARGB: Hashable, Sendable {
    public var a, r, g, b: UInt8

    public static let white = ARGB(a: 255, r: 255, g: 255, b: 255)
    public static let black = ARGB(a: 255, r: 0, g: 0, b: 0)
    public static let transparent = ARGB(a: 0, r: 0, g: 0, b: 0)

    /// Parses `#RRGGBB` or `#AARRGGBB`.
    public static func parse(_ s: String) throws -> ARGB {
        let hex = s.hasPrefix("#") ? String(s.dropFirst()) : ""
        guard hex.count == 6 || hex.count == 8, let v = UInt32(hex, radix: 16) else {
            throw RenderThemeError("unsupported color format: \(s)")
        }
        if hex.count == 6 {
            return ARGB(a: 255, r: UInt8(v >> 16 & 0xff), g: UInt8(v >> 8 & 0xff), b: UInt8(v & 0xff))
        }
        return ARGB(a: UInt8(v >> 24), r: UInt8(v >> 16 & 0xff), g: UInt8(v >> 8 & 0xff), b: UInt8(v & 0xff))
    }

    public var isTransparent: Bool { a == 0 }

    public var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}
