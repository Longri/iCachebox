import AVFoundation
import CacheboxCore
import MapKit
import SwiftUI
import UIKit

/// The context menu of a view (Cachebox `AbstractShowAction.getContextMenu`).
struct ViewContextMenu {
    let title: String
    let entries: [MenuEntry]
}

// What the main buttons do, and the context menus of the views. The toolbar menus of the views show the same
// entries, so both places stay alike.
extension AppState {
    // MARK: - Functions of the main buttons

    func isEnabled(_ action: MainAction) -> Bool {
        switch action {
        case .show, .mapDownload: true
        case .share, .navigate: selectedCache != nil
        case .hint: !(selectedDetails?.cache.hint.isEmpty ?? true)
        case .notes: selectedDetails != nil
        case .browser: selectedCacheURL != nil
        case .torch: Torch.isAvailable
        // not built yet
        case .parking, .trackables, .tracks, .solver, .solver2, .photo, .video, .voiceNote, .settings, .help: false
        }
    }

    func perform(_ action: MainAction) {
        guard isEnabled(action) else { return }
        switch action {
        case .show(let view): show(view)
        case .share: shareSelectedCache()
        case .hint: details.showHint = true
        case .notes: details.editingNote = true
        case .browser: if let url = selectedCacheURL { UIApplication.shared.open(url) }
        case .navigate: navigateToSelectedCache()
        case .mapDownload: showMapDownload = true
        case .torch: isTorchOn = Torch.set(!isTorchOn)
        case .parking, .trackables, .tracks, .solver, .solver2, .photo, .video, .voiceNote, .settings, .help: break
        }
    }

    /// The functions of a button as menu entries; the shown view has a checkmark (Cachebox greys it out). What the
    /// chosen "Funktionsumfang" does not cover is left out (`MainAction.level`).
    func functionEntries(for button: MainButton) -> [MenuEntry] {
        button.functions.map { function in
            let action = function.action
            let isView: Bool
            let checked: Bool?
            switch action {
            case .show(let shown):
                isView = true
                checked = shown == view
            case .torch:
                isView = false
                checked = isTorchOn
            default:
                isView = false
                checked = nil
            }
            return MenuEntry(action.title, systemImage: action.systemImage, id: "function-\(action)",
                             isDisabled: !isEnabled(action), isChecked: checked, gesture: function.gesture,
                             keepsMenuOpen: action == .torch, runsImmediately: isView,
                             level: action.level) { [weak self] in
                self?.perform(action)
            }
        }
        .shown(at: featureLevel)
    }

    // MARK: - Context menus

    /// Cheap check for the three dots on the button (without building the entries).
    func hasContextMenu(_ view: MainView) -> Bool {
        switch view {
        case .cacheList, .map, .compass, .drafts: true
        case .description, .waypoints, .logs, .spoiler: selectedCache != nil
        case .more: false
        }
    }

    /// The context menu of a view, without what the chosen "Funktionsumfang" hides.
    func contextMenu(for view: MainView) -> ViewContextMenu? {
        guard let menu = fullContextMenu(for: view) else { return nil }
        let entries = menu.entries.shown(at: featureLevel)
        return entries.isEmpty ? nil : ViewContextMenu(title: menu.title, entries: entries)
    }

    private func fullContextMenu(for view: MainView) -> ViewContextMenu? {
        guard hasContextMenu(view) else { return nil }
        switch view {
        case .cacheList:
            return ViewContextMenu(title: lists.currentName ?? "Cacheliste", entries: cacheListEntries)
        case .waypoints:
            guard let cache = selectedCache else { return nil }
            return ViewContextMenu(title: "Wegpunkt", entries: waypointEntries(cache))
        case .description, .logs, .spoiler:
            guard let cache = selectedCache else { return nil }
            return ViewContextMenu(title: cache.name, entries: cacheEntries(cache))
        case .map:
            return ViewContextMenu(title: "Karte", entries: mapEntries)
        case .compass:
            return ViewContextMenu(title: "Kompass", entries: compassEntries)
        case .drafts:
            return ViewContextMenu(title: "Entwürfe", entries: draftEntries)
        case .more:
            return nil
        }
    }

    /// Cache list (Cachebox `ShowGeoCaches.getContextMenu`: sort, filter, import, lists, delete).
    var cacheListEntries: [MenuEntry] {
        let hasList = lists.current != nil
        var entries = [
            MenuEntry("Sortieren", systemImage: "arrow.up.arrow.down", entries: CacheSortOrder.allCases.map { order in
                MenuEntry(order.title, id: "sort-\(order.rawValue)", isChecked: lists.sortOrder == order,
                          runsImmediately: true) { [weak self] in self?.lists.sortOrder = order }
            }),
            MenuEntry("Filter …", systemImage: lists.filter.isActive
                      ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle",
                      isDisabled: !hasList) { [weak self] in self?.listUI.showFilter = true },
        ]
        if lists.filter.isActive {
            entries.append(MenuEntry("Filter zurücksetzen", systemImage: "xmark.circle", runsImmediately: true) {
                [weak self] in self?.lists.filter = .all
            })
        }
        entries += [
            .divider("lists"),
            MenuEntry("GPX importieren …", systemImage: "square.and.arrow.down") { [weak self] in
                self?.listUI.showImport = true
            },
            MenuEntry("Listen verwalten …", systemImage: "folder") { [weak self] in self?.listUI.showLists = true },
            MenuEntry("Caches löschen", systemImage: "trash", isDisabled: lists.caches.isEmpty, level: .advanced,
                      entries: CacheListView.DeleteChoice.allCases.map { choice in
                          MenuEntry(choice.menuTitle, id: "delete-\(choice.rawValue)",
                                    isDisabled: listUI.codes(for: choice, in: lists).isEmpty, role: .destructive) {
                              [weak self] in self?.listUI.pendingDelete = choice
                          }
                      }),
        ]
        return entries.shown(at: featureLevel)
    }

    /// The selected cache (Cachebox `CacheContextMenu`), for description, waypoints, logs and spoiler.
    func cacheEntries(_ cache: CacheSummary) -> [MenuEntry] {
        [
            MenuEntry("Auf der Karte", systemImage: "map", runsImmediately: true) { [weak self] in
                self?.select(cache, show: .map)
            },
            MenuEntry(cache.isFound ? "Als nicht gefunden markieren" : "Als gefunden markieren",
                      systemImage: cache.isFound ? "xmark.circle" : "checkmark.circle", id: "found",
                      runsImmediately: true) { [weak self] in
                self?.lists.setFound(!cache.isFound, code: cache.code)
                self?.refreshSelection()
            },
            MenuEntry("Favorit", systemImage: "star", isChecked: cache.isFavorite, runsImmediately: true) {
                [weak self] in
                self?.lists.setFavorite(!cache.isFavorite, code: cache.code)
                self?.refreshSelection()
            },
            MenuEntry("Notiz bearbeiten …", systemImage: "note.text", isDisabled: selectedDetails == nil) {
                [weak self] in self?.details.editingNote = true
            },
            MenuEntry("Koordinaten kopieren", systemImage: "doc.on.doc", runsImmediately: true, level: .advanced) {
                UIPasteboard.general.string = cache.coordinate.formatted
            },
            MenuEntry("Im Browser öffnen", systemImage: "safari", isDisabled: selectedCacheURL == nil,
                      runsImmediately: true, level: .advanced) { [weak self] in
                if let url = self?.selectedCacheURL { UIApplication.shared.open(url) }
            },
            .divider("api"),
            // TODO: Aktualisieren über die API, Solver (Cachebox: cache menu)
            MenuEntry("Aktualisieren", systemImage: "arrow.clockwise", isDisabled: true, level: .expert) {},
            MenuEntry("Solver", systemImage: "function", isDisabled: true, level: .expert) {},
            .divider("delete"),
            MenuEntry("Aus der Liste löschen", systemImage: "trash", role: .destructive, level: .advanced) {
                [weak self] in self?.details.confirmDelete = true
            },
        ].shown(at: featureLevel)
    }

    /// Map, theme, style and overlays, map rotation and a waypoint at the map center (Cachebox
    /// `ShowMap.getContextMenu`: Layer, Renderthemes, overlays, AlignToCompass, CenterWP).
    var mapEntries: [MenuEntry] {
        let model = map
        var entries = [
            MenuEntry("Karte wählen", systemImage: "map", isDisabled: model.maps.isEmpty, entries: model.maps.map { url in
                MenuEntry(url.deletingPathExtension().lastPathComponent, id: url.path,
                          isChecked: model.selectedMap == url, runsImmediately: true) { model.selectedMap = url }
            }),
            MenuEntry("Theme wählen", systemImage: "paintpalette", level: .advanced,
                      entries: model.themes.map { theme in
                MenuEntry(theme.name, id: "\(theme.source)", isChecked: model.selectedTheme == theme,
                          runsImmediately: true) { model.selectedTheme = theme }
            }),
        ]
        if let menu = model.styleMenu {
            entries.append(MenuEntry("Stil", systemImage: "paintbrush", level: .expert,
                                     entries: menu.styles.map { layer in
                MenuEntry(layer.title(language: model.language) ?? layer.id, id: layer.id,
                          isChecked: (model.selectedStyle ?? menu.defaultValue) == layer.id,
                          runsImmediately: true) { model.selectedStyle = layer.id }
            }))
            if let style = menu.layer(model.selectedStyle ?? menu.defaultValue), !style.overlays.isEmpty {
                entries.append(MenuEntry("Overlays", systemImage: "square.3.layers.3d", level: .expert,
                                         entries: style.overlays.map { overlay in
                    let binding = model.overlayBinding(overlay)
                    return MenuEntry(overlay.title(language: model.language) ?? overlay.id, id: overlay.id,
                                     isChecked: binding.wrappedValue, keepsMenuOpen: true) {
                        binding.wrappedValue.toggle()
                    }
                }))
            }
        }
        // Cachebox `ShowMap.getContextMenu` › "AlignToCompass", "CenterWP"
        entries += [
            .divider("waypoint"),
            MenuEntry("Nach Kompass ausrichten", systemImage: "location.north.line", isChecked: model.alignsToCompass,
                      runsImmediately: true, level: .advanced) { model.alignsToCompass.toggle() },
            MenuEntry("WP vom Kartenmittelpunkt", systemImage: "mappin.and.ellipse", isDisabled: selectedCache == nil,
                      level: .advanced) { [weak self] in self?.addWaypointAtMapCenter() },
        ]
        return entries.shown(at: featureLevel)
    }

    /// Cachebox `ShowCompass.getContextMenu`: "Ansicht" opens the elements to show.
    var compassEntries: [MenuEntry] {
        // stays in every "Funktionsumfang": it is the only entry of this menu, and the button shows its three dots
        [MenuEntry("Ansicht", systemImage: "eye",
                   entries: CompassOptions.Element.allCases.map { element in
            MenuEntry(element.title, id: element.rawValue, isChecked: compass[element], keepsMenuOpen: true) {
                [weak self] in self?.compass[element].toggle()
            }
        })].shown(at: featureLevel)
    }

    /// Cachebox `ShowDrafts.getContextMenu`; drafts are not built yet.
    var draftEntries: [MenuEntry] {
        // TODO: Entwürfe anlegen und hochladen (Geocaching-API: logdrafts)
        [
            MenuEntry("Gefunden", systemImage: "face.smiling", isDisabled: true) {},
            MenuEntry("Nicht gefunden", systemImage: "questionmark.circle", isDisabled: true) {},
            MenuEntry("Notiz", systemImage: "note.text", isDisabled: true) {},
            MenuEntry("Wartung nötig", systemImage: "wrench.adjustable", isDisabled: true) {},
            .divider("upload"),
            MenuEntry("Entwürfe hochladen", systemImage: "square.and.arrow.up", isDisabled: true) {},
        ]
    }

    // MARK: - Helpers

    /// The loaded details, if they belong to the selected cache.
    var selectedDetails: SelectedCacheDetails.Details? {
        guard let value = details.value, value.cache.code == selectedCache?.code else { return nil }
        return value
    }

    /// The listing of the selected cache (Cachebox `StartExternalDescription`).
    var selectedCacheURL: URL? {
        guard let text = selectedDetails?.cache.url, !text.isEmpty else { return nil }
        return URL(string: text)
    }

    /// Cachebox `Share`: name, code, coordinates and link of the selected cache to another app.
    private func shareSelectedCache() {
        guard let cache = selectedCache else { return }
        let link = selectedCacheURL ?? (cache.code.uppercased().hasPrefix("GC")
                                          ? URL(string: "https://coord.info/\(cache.code)") : nil)
        var text = "\(cache.name) (\(cache.code))\n\(cache.target.formatted)"
        if let link { text += "\n\(link.absoluteString)" }
        ShareSheet.present([text])
    }

    /// Cachebox `NavigateTo`: route to the navigation target — the chosen waypoint, else the cache — in Apple Maps.
    private func navigateToSelectedCache() {
        guard let target else { return }
        let coordinate = target.coordinate
        let item: MKMapItem
        if #available(iOS 26, *) {
            item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                             address: nil)
        } else {
            item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
                latitude: coordinate.latitude, longitude: coordinate.longitude)))
        }
        item.name = "\(target.name) (\(target.code))"
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
}

/// The torch of the back camera (Cachebox `SwitchTorch`).
@MainActor
enum Torch {
    private static let device = AVCaptureDevice.default(for: .video)

    static var isAvailable: Bool { device?.hasTorch == true }

    static var isOn: Bool { device?.torchMode == .on }

    /// Switches the torch and returns whether it is on now.
    static func set(_ on: Bool) -> Bool {
        guard let device, device.hasTorch else { return false }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if on {
                try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
            } else {
                device.torchMode = .off
            }
        } catch {
            return isOn
        }
        return on
    }
}

/// Presents the system share sheet over the topmost screen.
@MainActor
enum ShareSheet {
    static func present(_ items: [Any]) {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            // iPad: from the bottom middle, where the main buttons are
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 60, width: 1, height: 1)
        }
        top.present(controller, animated: true)
    }
}
