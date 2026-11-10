import MapKit
import MapsforgeCore
import MapsforgeRender
import SwiftUI
import UIKit

/// MKMapView whose base map is replaced by Mapsforge tiles rendered on the device.
struct MapsforgeMapView: UIViewRepresentable {
    let renderer: TileRenderer
    let stats: RenderStats
    /// Identifies the map file; the view recenters when it changes.
    let mapID: URL
    let center: CLLocationCoordinate2D

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.pointOfInterestFilter = .excludingAll
        updateUIView(mapView, context: context)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let c = context.coordinator
        if c.overlay?.renderer !== renderer {
            // new map/theme/style: replace the tile overlay (MapKit has no API to flush its tile cache)
            let overlay = MapsforgeTileOverlay(renderer: renderer, stats: stats)
            mapView.addOverlay(overlay, level: .aboveLabels)
            if let old = c.overlay { mapView.removeOverlay(old) }
            c.overlay = overlay
        }
        if c.mapID != mapID {
            c.mapID = mapID
            mapView.setRegion(MKCoordinateRegion(center: center, latitudinalMeters: 1500, longitudinalMeters: 1500),
                              animated: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var overlay: MapsforgeTileOverlay?
        var mapID: URL?

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tiles)
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

/// Renders tiles on demand with the Swift Mapsforge renderer.
final class MapsforgeTileOverlay: MKTileOverlay, @unchecked Sendable {
    let renderer: TileRenderer
    private let stats: RenderStats
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "mapsforge.render"
        q.maxConcurrentOperationCount = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
        q.qualityOfService = .userInitiated
        return q
    }()

    init(renderer: TileRenderer, stats: RenderStats) {
        self.renderer = renderer
        self.stats = stats
        super.init(urlTemplate: nil)
        canReplaceMapContent = true
        minimumZ = 6
        maximumZ = 21
        tileSize = CGSize(width: 256, height: 256)
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let renderer = self.renderer
        let stats = self.stats
        nonisolated(unsafe) let result = result   // MapKit's completion handler may be called from any thread
        queue.addOperation {
            let start = CFAbsoluteTimeGetCurrent()
            let tile = Tile(tileX: path.x, tileY: path.y, zoomLevel: path.z, tileSize: 256)
            guard let image = renderer.renderTile(tile, scale: path.contentScaleFactor) else {
                result(nil, nil)
                return
            }
            let data = UIImage(cgImage: image).pngData()
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            Task { @MainActor in stats.record(ms: ms, zoom: path.z) }
            result(data, nil)
        }
    }
}
