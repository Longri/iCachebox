// Port of org.mapsforge.map.rendertheme.XmlRenderThemeStyleMenu / XmlRenderThemeStyleLayer
// plus the category selection of Cachebox' MapsForgeLayer menu callback.
// Licensed under LGPL-3.0 like the original mapsforge code.

import Foundation

/// One entry of a theme's `<stylemenu>`: either a selectable map style (`visible="true"`)
/// or an overlay that a style can switch on and off.
public final class RenderThemeStyleLayer: @unchecked Sendable {
    public let id: String
    /// Shown as selectable base style in a style chooser.
    public let isVisible: Bool
    /// Default state when used as overlay.
    public let isEnabled: Bool
    public let defaultLanguage: String
    /// Categories in document order (mapsforge keeps a LinkedHashSet).
    public private(set) var categories: [String] = []
    public private(set) var overlays: [RenderThemeStyleLayer] = []
    public private(set) var titles: [String: String] = [:]

    init(id: String, visible: Bool, enabled: Bool, defaultLanguage: String) {
        self.id = id
        self.isVisible = visible
        self.isEnabled = enabled
        self.defaultLanguage = defaultLanguage
    }

    /// Title in `language`, falling back to the menu's default language.
    public func title(language: String) -> String? {
        titles[language] ?? titles[defaultLanguage]
    }

    func addCategory(_ c: String) {
        if !categories.contains(c) { categories.append(c) }
    }

    func addOverlay(_ l: RenderThemeStyleLayer) { overlays.append(l) }
    func addTranslation(language: String, title: String) { titles[language] = title }
}

public final class RenderThemeStyleMenu: @unchecked Sendable {
    public let id: String
    public let defaultLanguage: String
    /// Id of the style used when nothing else is selected.
    public let defaultValue: String
    /// All layers in document order.
    public private(set) var layers: [RenderThemeStyleLayer] = []
    private var byId: [String: RenderThemeStyleLayer] = [:]

    init(id: String, defaultLanguage: String, defaultValue: String) {
        self.id = id
        self.defaultLanguage = defaultLanguage
        self.defaultValue = defaultValue
    }

    /// The selectable base styles (`visible="true"`).
    public var styles: [RenderThemeStyleLayer] { layers.filter(\.isVisible) }

    public func layer(_ id: String) -> RenderThemeStyleLayer? { byId[id] }

    func createLayer(id: String, visible: Bool, enabled: Bool) -> RenderThemeStyleLayer {
        let l = RenderThemeStyleLayer(id: id, visible: visible, enabled: enabled, defaultLanguage: defaultLanguage)
        layers.append(l)
        byId[id] = l
        return l
    }

    /// Categories to render for `style` (default: `defaultValue`): the style's own categories plus
    /// those of its enabled overlays. `overlays` overrides the overlays' default `enabled` state
    /// (Cachebox stores this as `+id`/`-id` in its style setting). Returns nil (= render all
    /// categories, mapsforge semantics) if the style does not exist.
    public func categories(style: String? = nil, overlays: [String: Bool] = [:]) -> Set<String>? {
        guard let selected = layer(style ?? defaultValue) else { return nil }
        var result = Set(selected.categories)
        for overlay in selected.overlays where overlays[overlay.id] ?? overlay.isEnabled {
            result.formUnion(overlay.categories)
        }
        return result
    }
}

/// mapsforge `XmlRenderThemeMenuCallback`: picks the categories once the style menu is parsed.
/// Returning nil renders all categories.
public typealias RenderThemeMenuCallback = (RenderThemeStyleMenu) -> Set<String>?
