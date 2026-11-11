import CacheboxCore
import MapKit
import MapsforgeCore
import MapsforgeRender
import SwiftUI

/// Tab 3: Mapsforge offline map rendered by the Swift port and shown through MapKit, with map/theme/style
/// selection and a small performance HUD. The caches of the open list (filtered like the list) and the waypoints
/// of the selected cache are drawn on the map; tapping a cache opens its info bubble. The map centers on the cache
/// when it is selected or shown with "Auf der Karte" (Cachebox `MapView.setSelectedCache`). Map, theme, style,
/// position and zoom of the last session come back on the next launch.
///
/// Maps (`*.map`) and external themes (`*.xml` in sub-folders) are taken from the `BundledMaps`
/// folder of the app bundle (`App/BundledMaps`, not in git) and from the downloads (`MapLibrary`).
struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var model = MapModel()
    /// Additional waypoints of the selected cache.
    @State private var waypoints: [Waypoint] = []

    var body: some View {
        ZStack(alignment: .bottom) {
            if let renderer = model.renderer {
                MapsforgeMapView(renderer: renderer, stats: model.stats, center: model.center, markers: markers,
                                 showsUserLocation: state.location.coordinate != nil,
                                 onSelect: { state.select($0, show: .map) },
                                 onShowDetails: { state.select($0, show: .cache) },
                                 onCameraChange: { model.cameraChanged($0) })
                .ignoresSafeArea()
            } else {
                ContentUnavailableView("Karte nicht geladen", systemImage: "map",
                                       description: Text(model.error ?? "Lade Karte …"))
            }
            StatsView(stats: model.stats, loading: model.loading)
                .padding()
        }
        .overlay(alignment: .topTrailing) {
            MapMenu(model: model)
                .padding(.trailing, 12)
                .padding(.top, 56)
        }
        .overlay(alignment: .top) {
            if let notice = model.notice {
                Text(notice)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.top, 8)
                    .padding(.horizontal, 64)   // keep the map menu free
                    .transition(.opacity)
            }
        }
        .animation(.default, value: model.notice)
        .task { await model.reload() }
        // pick up maps and themes downloaded meanwhile; a changed selection reloads through MapMenu
        .onAppear { model.refreshSources() }
        .onChange(of: state.mapFocus, initial: true) {
            if let focus = state.mapFocus { model.focus(on: focus.coordinate) }
        }
        .task(id: waypointKey) { await loadWaypoints() }
        .task(id: model.notice) {
            guard model.notice != nil else { return }
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { model.notice = nil }
        }
    }

    /// The caches of the list as filtered there (Cachebox draws the filtered `CacheList`), each at its target
    /// (corrected coordinates, else a final with coordinates), plus the selected cache even if the filter hides it,
    /// and the waypoints of the selected cache that have coordinates.
    private var markers: [MapMarker] {
        let selected = state.selectedCache?.code
        let own: String? = if case .signedIn(let username, _) = state.account.status { username.lowercased() } else { nil }
        var markers = state.lists.rows.map { row in
            MapMarker.cache(row.cache, isSelected: row.cache.code == selected,
                            isOwn: own != nil && row.cache.owner.lowercased() == own)
        }
        if let cache = state.selectedCache, !markers.contains(where: { $0.id == cache.code }) {
            markers.append(.cache(cache, isSelected: true, isOwn: own != nil && cache.owner.lowercased() == own))
        }
        for waypoint in waypoints where waypoint.cacheCode == selected {
            if let coordinate = waypoint.coordinate { markers.append(.waypoint(waypoint, at: coordinate)) }
        }
        return markers
    }

    /// Reloads the waypoints for another cache, another list and after an import.
    private var waypointKey: [String?] {
        [state.selectedCache?.code, state.lists.currentName, state.lists.current?.lastImport?.description]
    }

    private func loadWaypoints() async {
        guard let code = state.selectedCache?.code, let name = state.lists.currentName else {
            waypoints = []
            return
        }
        let url = state.lists.store.url(of: name)
        waypoints = await Task.detached(priority: .userInitiated) {
            (try? CacheDatabase(url: url).waypoints(cacheCode: code)) ?? []
        }.value
    }
}

/// Map, theme, style and overlay selection.
struct MapMenu: View {
    @Bindable var model: MapModel

    var body: some View {
        Menu {
            Picker("Karte", selection: $model.selectedMap) {
                ForEach(model.maps, id: \.self) { url in
                    Text(url.deletingPathExtension().lastPathComponent).tag(Optional(url))
                }
            }
            .pickerStyle(.menu)
            Picker("Theme", selection: $model.selectedTheme) {
                ForEach(model.themes) { theme in
                    Text(theme.name).tag(theme)
                }
            }
            .pickerStyle(.menu)
            if let menu = model.styleMenu {
                Picker("Stil", selection: $model.selectedStyle) {
                    ForEach(menu.styles, id: \.id) { layer in
                        Text(layer.title(language: model.language) ?? layer.id).tag(Optional(layer.id))
                    }
                }
                .pickerStyle(.menu)
                if let style = menu.layer(model.selectedStyle ?? menu.defaultValue), !style.overlays.isEmpty {
                    Menu("Overlays") {
                        ForEach(style.overlays, id: \.id) { overlay in
                            Toggle(overlay.title(language: model.language) ?? overlay.id,
                                   isOn: model.overlayBinding(overlay))
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "square.3.layers.3d")
                .font(.title3)
                .padding(10)
                .background(.regularMaterial, in: Circle())
        }
        .onChange(of: model.selectedMap) { Task { await model.reload(recenter: true) } }
        .onChange(of: model.selectedTheme) {
            model.selectedStyle = nil
            model.overlays = [:]
            Task { await model.reload() }
        }
        .onChange(of: model.selectedStyle) { Task { await model.reload() } }
        .onChange(of: model.overlays) { Task { await model.reload() } }
    }
}

struct ThemeChoice: Hashable, Identifiable {
    enum Source: Hashable {
        case builtIn(String)
        case file(URL)
    }
    let name: String
    let source: Source
    var id: Self { self }
}

@MainActor
@Observable
final class MapModel {
    var renderer: TileRenderer?
    var error: String?
    var loading = false
    let stats = RenderStats()

    private(set) var maps: [URL] = []
    private(set) var themes: [ThemeChoice] = []
    var selectedMap: URL?
    var selectedTheme: ThemeChoice
    var selectedStyle: String?
    var overlays: [String: Bool] = [:]
    private(set) var styleMenu: RenderThemeStyleMenu?
    /// Map file of the current renderer (the selection may already point to the next one).
    private(set) var loadedMap: URL?
    private(set) var center = MapCenterRequest(latitude: 53.0758, longitude: 8.8072, resetZoom: true)
    /// Short message over the map, e.g. when no map covers the selected cache; hidden after a few seconds.
    var notice: String?

    let language = Locale.current.language.languageCode?.identifier ?? "en"
    private var generation = 0
    /// `BundledMaps` and the download folders; maps and themes are remembered by their path inside them, because
    /// the app's folders move with every install.
    private var sourceFolders: [URL] = []
    /// Position and zoom of the last session, used by the first load if the map shows that place.
    private var savedCamera = MapCamera.saved
    private var savedCameraMap = UserDefaults.standard.string(forKey: Keys.map)
    /// Area of each map file, read from its header.
    private var bounds: [URL: BoundingBox] = [:]
    /// Last place asked for with `focus(on:)` (the selected cache); a map chosen later starts there if it covers it.
    private var focusTarget: LatLong?
    /// A place asked for while no map was loaded or another one was loading; that load starts there.
    private var pendingFocus: LatLong?

    private static let builtInThemes = [ThemeChoice(name: "Default", source: .builtIn("default")),
                                        ThemeChoice(name: "Osmarender", source: .builtIn("osmarender"))]

    private enum Keys {
        static let map = "map.file"
        static let theme = "map.theme"
        static let style = "map.style"
        static let overlays = "map.overlays"
    }

    /// Starts with the map, theme, style and overlays of the last session (Cachebox `currentMapLayer`, theme and
    /// style settings), else with the Bremen test map or the first map.
    init() {
        selectedTheme = Self.builtInThemes[0]
        refreshSources()
        let defaults = UserDefaults.standard
        let lastMap = defaults.string(forKey: Keys.map).flatMap { key in maps.first { sourceKey($0) == key } }
        selectedMap = lastMap ?? maps.first { $0.lastPathComponent.hasPrefix("bremen") } ?? maps.first
        if let key = defaults.string(forKey: Keys.theme), let theme = themes.first(where: { themeKey($0) == key }) {
            selectedTheme = theme
            selectedStyle = defaults.string(forKey: Keys.style)
            overlays = defaults.data(forKey: Keys.overlays)
                .flatMap { try? JSONDecoder().decode([String: Bool].self, from: $0) } ?? [:]
        }
    }

    /// Path of a map or theme file inside its source folder, e.g. `Elevate/Elevate.xml`.
    private func sourceKey(_ url: URL) -> String {
        let path = url.resolvingSymlinksInPath().path
        for folder in sourceFolders {
            let prefix = folder.resolvingSymlinksInPath().path + "/"
            if path.hasPrefix(prefix) { return String(path.dropFirst(prefix.count)) }
        }
        return url.lastPathComponent
    }

    private func themeKey(_ theme: ThemeChoice) -> String {
        switch theme.source {
        case .builtIn(let name): "builtin:" + name
        case .file(let url): "file:" + sourceKey(url)
        }
    }

    /// Remembers where the map is for the next launch.
    func cameraChanged(_ camera: MapCamera) {
        guard renderer != nil else { return }
        camera.save()
    }

    /// Scans `BundledMaps` and the download folders for maps and themes. A selection whose file is gone
    /// (deleted download) falls back to the first map or the default theme.
    func refreshSources() {
        let fm = FileManager.default
        var folders = [MapLibrary.mapsFolder, MapLibrary.themesFolder]
        if let bundled = Bundle.main.url(forResource: "BundledMaps", withExtension: nil) { folders.insert(bundled, at: 0) }
        sourceFolders = folders
        let files = folders.flatMap {
            fm.enumerator(at: $0, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)?.allObjects as? [URL] ?? []
        }
        func byName(_ a: URL, _ b: URL) -> Bool {
            a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }
        maps = files.filter { $0.pathExtension == "map" }.sorted(by: byName)
        for map in maps where bounds[map] == nil {
            bounds[map] = (try? MapFile(url: map))?.boundingBox   // reads only the header
        }
        themes = Self.builtInThemes + files.filter { $0.pathExtension == "xml" }.sorted(by: byName)
            .map { ThemeChoice(name: $0.deletingPathExtension().lastPathComponent, source: .file($0)) }

        if selectedMap.map({ !maps.contains($0) }) ?? true { selectedMap = maps.first }
        if !themes.contains(selectedTheme) { selectedTheme = themes[0] }
        if maps.isEmpty { error = "Keine Karte vorhanden. Karten gibt es unter Mehr → Karten und Themes." }
    }

    /// Freizeitkarte maps need their own design; Cachebox detects them by "FZK" in the map comment
    /// (`MapsForgeLayer.prepareLayer`).
    private var freizeitkarteTheme: ThemeChoice? {
        let candidates = themes.filter {
            guard case .file(let url) = $0.source else { return false }
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            return name.hasPrefix("freizeitkarte") || name.hasPrefix("fzk")
        }
        return candidates.first { $0.name == "freizeitkarte-v5" } ?? candidates.first
    }

    /// Centers the map on a place (the selected cache). If the chosen map does not cover it, another map that does
    /// is chosen; if none does, the map still moves there (the marker shows the place) and says that a map is missing.
    func focus(on coordinate: Coordinate) {
        let point = LatLong(latitude: coordinate.latitude, longitude: coordinate.longitude)
        focusTarget = point
        let covers = { (map: URL) in self.bounds[map]?.contains(point) == true }
        let covering = selectedMap.flatMap { covers($0) ? $0 : nil } ?? maps.first(where: covers)
        notice = covering == nil && !maps.isEmpty
            ? "Keine Karte für diesen Ort. Karten gibt es unter Mehr › Karten und Themes." : nil
        if let covering, covering != selectedMap {
            pendingFocus = point
            selectedMap = covering   // MapMenu reloads the map, which then starts at the place
        } else if renderer == nil || loadedMap != selectedMap {
            pendingFocus = point     // the first or the running load starts there
        } else {
            center = MapCenterRequest(latitude: point.latitude, longitude: point.longitude, resetZoom: false)
        }
    }

    func overlayBinding(_ overlay: RenderThemeStyleLayer) -> Binding<Bool> {
        Binding(get: { self.overlays[overlay.id] ?? overlay.isEnabled },
                set: { self.overlays[overlay.id] = $0 })
    }

    /// Opens map and theme off the main thread and swaps in a new renderer.
    func reload(recenter: Bool = false) async {
        guard let mapURL = selectedMap else { return }
        generation += 1
        let current = generation
        loading = true
        let (theme, style, overlays, language) = (selectedTheme, selectedStyle, overlays, language)
        let result = await Task.detached(priority: .userInitiated) { () -> Result<(TileRenderer, MapFile), Error> in
            Result {
                let map = try MapFile(url: mapURL, language: language)
                let renderTheme: RenderTheme
                switch theme.source {
                case .builtIn(let name):
                    renderTheme = try RenderTheme.builtIn(name)
                case .file(let url):
                    renderTheme = try RenderTheme.load(url: url, menuCallback: { $0.categories(style: style, overlays: overlays) })
                }
                return (TileRenderer(mapFile: map, theme: renderTheme), map)
            }
        }.value
        guard current == generation else { return }   // a newer selection is already loading
        loading = false
        switch result {
        case .success(let (renderer, map)):
            if recenter || self.renderer == nil, map.info.comment?.contains("FZK") == true,
               case .builtIn = selectedTheme.source, let theme = freizeitkarteTheme {
                selectedTheme = theme   // MapMenu reloads with the matching design
            }
            let restored = self.renderer == nil && pendingFocus == nil ? savedCamera.flatMap { camera in
                // the position of the last session, if it was on this map or this map covers it
                savedCameraMap == sourceKey(mapURL)
                    || map.boundingBox.contains(LatLong(latitude: camera.latitude, longitude: camera.longitude))
                    ? camera : nil
            } : nil
            savedCamera = nil
            if let restored {
                center = MapCenterRequest(latitude: restored.latitude, longitude: restored.longitude,
                                          resetZoom: false, zoom: restored.zoom)
            } else if recenter || self.renderer == nil || pendingFocus != nil {
                // a place asked for meanwhile; the selected cache if the map covers it; else Bremen market square
                // for the test map, otherwise the map's own start position
                let start = if let pending = pendingFocus {
                    pending
                } else if let target = focusTarget, map.boundingBox.contains(target) {
                    target
                } else if mapURL.lastPathComponent.hasPrefix("bremen") {
                    LatLong(latitude: 53.0758, longitude: 8.8072)
                } else {
                    map.startPosition
                }
                center = MapCenterRequest(latitude: start.latitude, longitude: start.longitude, resetZoom: true)
            }
            pendingFocus = nil
            styleMenu = renderer.theme.styleMenu
            if let menu = styleMenu, selectedStyle == nil { selectedStyle = menu.defaultValue }
            let defaults = UserDefaults.standard
            defaults.set(sourceKey(mapURL), forKey: Keys.map)
            defaults.set(themeKey(theme), forKey: Keys.theme)
            defaults.set(style ?? styleMenu?.defaultValue, forKey: Keys.style)
            defaults.set(try? JSONEncoder().encode(overlays), forKey: Keys.overlays)
            stats.reset()
            error = nil
            loadedMap = mapURL
            self.renderer = renderer
        case .failure(let e):
            error = "\(e)"
        }
    }
}

/// Tile render statistics, updated from the render queue.
@MainActor
@Observable
final class RenderStats {
    var tiles = 0
    var totalMs = 0.0
    var lastMs = 0.0
    var maxMs = 0.0
    var zoom = 0

    var averageMs: Double { tiles == 0 ? 0 : totalMs / Double(tiles) }

    func record(ms: Double, zoom: Int) {
        tiles += 1
        totalMs += ms
        lastMs = ms
        maxMs = max(maxMs, ms)
        self.zoom = zoom
    }

    func reset() {
        tiles = 0
        totalMs = 0
        lastMs = 0
        maxMs = 0
    }
}

struct StatsView: View {
    let stats: RenderStats
    var loading = false

    var body: some View {
        HStack(spacing: 12) {
            if loading { ProgressView().controlSize(.small) }
            Label("\(stats.tiles)", systemImage: "square.grid.3x3")
            Text("z\(stats.zoom)")
            Text(String(format: "Ø %.0f ms", stats.averageMs))
            Text(String(format: "max %.0f ms", stats.maxMs))
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }
}
