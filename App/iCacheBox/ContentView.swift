import MapKit
import MapsforgeCore
import MapsforgeRender
import SwiftUI

/// Prototype screen: Mapsforge offline map rendered by the Swift port and shown through MapKit,
/// with map/theme/style selection and a small performance HUD.
///
/// Maps (`*.map`) and external themes (`*.xml` in sub-folders) are taken from the `BundledMaps`
/// folder of the app bundle (`App/BundledMaps`, not in git).
struct ContentView: View {
    @State private var model = MapModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            if let renderer = model.renderer, let map = model.loadedMap {
                MapsforgeMapView(renderer: renderer, stats: model.stats, mapID: map, center: model.center)
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
        .task { await model.reload() }
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

    let maps: [URL]
    let themes: [ThemeChoice]
    var selectedMap: URL?
    var selectedTheme: ThemeChoice
    var selectedStyle: String?
    var overlays: [String: Bool] = [:]
    private(set) var styleMenu: RenderThemeStyleMenu?
    /// Map file of the current renderer (the selection may already point to the next one).
    private(set) var loadedMap: URL?
    private(set) var center = CLLocationCoordinate2D(latitude: 53.0758, longitude: 8.8072)

    let language = Locale.current.language.languageCode?.identifier ?? "en"
    private var generation = 0

    init() {
        let fm = FileManager.default
        let folder = Bundle.main.url(forResource: "BundledMaps", withExtension: nil)
        let files = folder.flatMap { fm.enumerator(at: $0, includingPropertiesForKeys: nil)?.allObjects as? [URL] } ?? []
        maps = files.filter { $0.pathExtension == "map" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let external = files.filter { $0.pathExtension == "xml" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { ThemeChoice(name: $0.deletingPathExtension().lastPathComponent, source: .file($0)) }
        themes = [ThemeChoice(name: "Default", source: .builtIn("default")),
                  ThemeChoice(name: "Osmarender", source: .builtIn("osmarender"))] + external
        selectedMap = maps.first { $0.lastPathComponent.hasPrefix("bremen") } ?? maps.first
        selectedTheme = themes[0]
        if maps.isEmpty { error = "Keine .map-Datei in BundledMaps" }
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
            if recenter || self.renderer == nil {
                // Bremen market square for the test map, otherwise the map's own start position
                center = mapURL.lastPathComponent.hasPrefix("bremen")
                    ? CLLocationCoordinate2D(latitude: 53.0758, longitude: 8.8072)
                    : CLLocationCoordinate2D(latitude: map.startPosition.latitude, longitude: map.startPosition.longitude)
            }
            styleMenu = renderer.theme.styleMenu
            if let menu = styleMenu, selectedStyle == nil { selectedStyle = menu.defaultValue }
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
