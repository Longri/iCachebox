import CacheboxCore
import SwiftUI

/// Request to center the map on a position. Every request has its own `id`, so showing the same cache again
/// re-centers a map the user has moved meanwhile.
struct MapFocus: Equatable {
    let coordinate: Coordinate
    /// Asked for with "Auf der Karte": the map leaves the GPS mode for it. A focus that only comes from a changed
    /// selection leaves a map in GPS mode at the own position (Cachebox `MapView.setSelectedCache`).
    var isExplicit = false
    let id = UUID()
}

/// What the app navigates to: a chosen waypoint of the selected cache, else the cache itself (Cachebox
/// `GlobalCore.getSelectedCoordinate`). The compass, the map arrow, the distances and the approach notification
/// all use it.
struct NavigationTarget: Equatable {
    let coordinate: Coordinate
    /// The chosen waypoint, if the target is one.
    let waypoint: Waypoint?
    /// The cache the target belongs to; "Mein Parkplatz" belongs to none (Cachebox makes a pseudo cache of it).
    let cache: CacheSummary?

    /// The target is the parking place (`ParkingPlace`).
    var isParking: Bool { cache == nil }

    /// Name of the waypoint, else of the cache (Cachebox `CompassView`: `getTitleForGui`, else the cache name).
    var name: String {
        guard let waypoint else { return cache?.name ?? ParkingPlace.name }
        return waypoint.title.isEmpty ? waypoint.type.title : waypoint.title
    }

    /// Cachebox shows the GC code of the cache also for a waypoint; the waypoint has its own code besides.
    var code: String { waypoint?.code ?? cache?.code ?? ParkingPlace.code }

    /// Icon of the waypoint type, else of the cache type (Cachebox `CompassView.setCache`).
    var iconName: String {
        if let waypoint { return waypoint.type.iconName }
        guard let cache else { return ParkingPlace.iconName }
        return cache.type.iconName(solved: cache.isSolved)
    }

    /// Description of the waypoint (Cachebox `CompassShowWpDesc`); a cache has none here.
    var comment: String { waypoint?.comment ?? "" }

    var clue: String { waypoint?.clue ?? "" }

    var isWaypoint: Bool { waypoint != nil }

    /// Tells targets apart for the approach notification.
    var id: String { waypoint.map { $0.id } ?? cache?.code ?? ParkingPlace.code }
}

/// App-wide UI state: the shown view and the selected cache (Cachebox: `ViewManager`, `GlobalCore.getSelectedCache`).
@MainActor
@Observable
final class AppState {
    /// The view above the main buttons (Cachebox `CB_TabView.currentView`).
    private(set) var view: MainView = .cacheList
    /// The last view shown with each main button (Cachebox `GestureButton.aktActionView`); a tap on the button shows
    /// it again (setting `rememberLastAction`).
    private(set) var lastViews: [MainButton: MainView] = [:]
    /// The cache selected in the list; kept per cache list and selected again when the list is opened.
    private(set) var selectedCache: CacheSummary?
    /// The chosen waypoint of the selected cache (Cachebox `GlobalCore.selectedWayPoint`): it becomes the
    /// navigation target. Choosing another cache drops it, as in Cachebox.
    private(set) var selectedWaypoint: Waypoint?
    /// How much the menus offer (Mehr › Einstellungen › Funktionsumfang).
    var featureLevel = FeatureLevel.saved {
        didSet { featureLevel.save() }
    }
    /// Where the map should go: set when the selection changes and by "Auf der Karte" (Cachebox `MapView`
    /// centers on a newly selected cache, too).
    private(set) var mapFocus: MapFocus?
    let account = GeocachingAccount()
    let mapLibrary = MapLibrary.shared
    let lists = CacheListModel()
    let location = LocationModel()
    /// Details (waypoints, logs, attributes …) of the selected cache, for the cache views and the compass.
    let details = SelectedCacheDetails()
    /// Search text and sheets of the cache list, also opened from the menu of the list button.
    let listUI = CacheListUI()
    /// The map shown by the navigation button; its menu also offers map, theme and style.
    let map = MapModel()
    /// What the compass view shows (Cachebox `CompassShow…` settings).
    let compass = CompassOptions()
    /// Notifies when the selected cache comes near (Cachebox `SoundApproachDistance`).
    let approach = ApproachNotifier()
    /// Where the car stands (Cachebox `ParkingMenu`, settings `ParkingLatitude`/`ParkingLongitude`).
    let parking = ParkingPlace()
    /// Loading GCVote ratings into the open list (Cachebox: "GCVoteRatings" in the import dialog).
    let gcVote = GCVoteModel()
    /// The parking place is the navigation target (Cachebox selects its pseudo cache "CBPark" instead).
    private(set) var targetsParking = false
    /// "Parkplatz" of the list and the "Sonstiges" button opens the dialog (Cachebox `ParkingMenu`).
    var showParking = false
    /// Main button 3 › "Karten und Themes" shows the download as a sheet.
    var showMapDownload = false
    /// "GCVote-Bewertungen" of the list menu opens as a sheet.
    var showGCVote = false
    /// The torch is on (main button 5 › "Taschenlampe", Cachebox `SwitchTorch`).
    var isTorchOn = false
    /// The waypoint shown in the `WaypointEditor` (Cachebox `EditWaypoint`).
    var waypointEditor: WaypointEditRequest?
    /// Open projection of a new waypoint (Cachebox `ProjectionCoordinate`).
    var projection: ProjectionRequest?
    /// Open measurement of a new waypoint from the GPS fixes (Cachebox `MeasureCoordinate`).
    var measuring: MeasureRequest?
    /// Asks before deleting a waypoint of the user (Cachebox `deleteWP`).
    var waypointToDelete: Waypoint?
    /// A waypoint could not be created or saved.
    var waypointError: String?
    /// Counts changes of waypoints, so that details and map read them again.
    var waypointRevision = 0
    /// The selection was taken from a list at least once (the first time is the app launch).
    private var hasRestoredSelection = false

    init() {
        // whenever a list is (re)opened, also after an import, its remembered cache becomes the selection
        lists.onOpen = { [weak self] in self?.restoreSelection() }
        // every fix is measured against the selected cache (Cachebox `GlobalLocationReceiver.positionChanged`)
        location.onPositionChanged = { [weak self] in self?.checkApproach() }
    }

    /// Where compass, map arrows, distances and the approach notification point: the chosen waypoint of the
    /// selected cache, else the cache itself (Cachebox `GlobalCore.getSelectedCoordinate`).
    var target: NavigationTarget? {
        if targetsParking, let coordinate = parking.coordinate {
            return NavigationTarget(coordinate: coordinate, waypoint: nil, cache: nil)
        }
        guard let cache = selectedCache else { return nil }
        if let waypoint = selectedWaypoint, let coordinate = waypoint.coordinate, coordinate.isValid {
            return NavigationTarget(coordinate: coordinate, waypoint: waypoint, cache: cache)
        }
        return NavigationTarget(coordinate: cache.target, waypoint: nil, cache: cache)
    }

    /// Chooses a waypoint of the selected cache as the target, or the cache itself with `nil` (Cachebox
    /// `GlobalCore.setSelectedWaypoint`). A waypoint without coordinates cannot be a target.
    func selectWaypoint(_ waypoint: Waypoint?) {
        guard waypoint?.cacheCode == nil || waypoint?.cacheCode == selectedCache?.code else { return }
        targetsParking = false
        selectedWaypoint = waypoint.flatMap { $0.coordinate?.isValid == true ? $0 : nil }
        approach.reset()
        checkApproach()
        if let coordinate = selectedWaypoint?.coordinate {
            mapFocus = MapFocus(coordinate: coordinate)
        }
    }

    /// After the details were loaded again (edited, deleted or imported waypoints): keeps the target on the same
    /// waypoint, with its new coordinates, and drops it when the waypoint is gone.
    func refreshSelectedWaypoint() {
        guard let chosen = selectedWaypoint else { return }
        guard let waypoints = selectedDetails?.waypoints else { return }
        selectedWaypoint = waypoints.first { $0.code == chosen.code && $0.coordinate?.isValid == true }
    }

    // MARK: - My parking area (Cachebox `ParkingMenu`)

    /// Cachebox `btnSetGPS`: saves the own position as the parking place. Without a fix nothing is saved and the
    /// dialog says so.
    @discardableResult
    func saveParking() -> Bool {
        guard let here = location.coordinate, here.isValid else { return false }
        parking.set(here)
        if targetsParking {
            // the target moved: announce the new place again
            approach.reset()
            checkApproach()
            mapFocus = MapFocus(coordinate: here)
        }
        return true
    }

    /// Cachebox `btnSelectWP`: the parking place becomes the navigation target (Cachebox selects its pseudo cache).
    func selectParking() {
        guard let coordinate = parking.coordinate else { return }
        targetsParking = true
        selectedWaypoint = nil
        approach.reset()
        checkApproach()
        mapFocus = MapFocus(coordinate: coordinate)
    }

    /// Cachebox `btnDeleteP`: forgets the parking place; the target falls back to the selected cache.
    func deleteParking() {
        parking.clear()
        guard targetsParking else { return }
        targetsParking = false
        approach.reset()
        checkApproach()
    }

    /// Notifies when the target is nearer than the set distance and, if asked for, shows the compass
    /// (Cachebox `switchViewApproach`).
    func checkApproach() {
        guard approach.update(target: target, here: location.coordinate) else { return }
        if approach.options.switchesToCompass { show(.compass) }
    }

    /// Starts or stops watching the distance to the selected cache; called at launch and after a change of the
    /// approach settings.
    func updateApproachWatching() {
        location.setBackgroundUpdates(approach.options.isOn && approach.options.worksInBackground)
        if approach.options.isOn { location.start() }
        // measure against the known position at once, so that a changed setting does not first have to wait for a
        // fix — standing outside the circle now, the next approach notifies
        checkApproach()
    }

    /// Shows a view and remembers it for its main button (Cachebox `CB_TabView.showView`).
    func show(_ view: MainView) {
        self.view = view
        lastViews[view.button] = view
    }

    /// Shows the cache button's view that was shown last (description, waypoints, logs or spoiler), like a tap on
    /// the cache button.
    func showCacheDetails() {
        show(lastViews[.cache] ?? .description)
    }

    /// Selects a cache and shows `view`, by default its details; with `.map` the map centers on the cache (on its
    /// target: corrected coordinates or a final, where the map draws it), also in GPS mode unless the cache was chosen
    /// on the map.
    func select(_ cache: CacheSummary, show view: MainView? = nil, onMap: Bool = false) {
        if cache.code != selectedCache?.code || view == .map {
            mapFocus = MapFocus(coordinate: cache.target, isExplicit: view == .map && !onMap)
        }
        // another cache drops its predecessor's waypoint (Cachebox `setSelectedCache` → `setSelectedWaypoint(null)`)
        if cache.code != selectedCache?.code { selectedWaypoint = nil }
        // choosing a cache takes the target off the parking place (Cachebox replaces the selected pseudo cache)
        targetsParking = false
        selectedCache = cache
        lists.rememberSelection(cache.code)
        checkApproach()
        if let view { show(view) } else { showCacheDetails() }
    }

    /// Opens a cache list; its last selected cache is selected again (Cachebox: `ShowSelectDB`).
    func openList(_ name: String?) async {
        await lists.open(name)
    }

    /// Takes the selection from the loaded list: the remembered cache, or none. The map moves to it, except at
    /// launch when the map has a position from the last session (Cachebox starts at the last map position).
    func restoreSelection() {
        let code = lists.lastSelectedCode()
        let cache = lists.caches.first { $0.code == code }
        let isLaunch = !hasRestoredSelection
        hasRestoredSelection = true
        if let cache, cache.code != selectedCache?.code, !(isLaunch && MapCamera.saved != nil) {
            mapFocus = MapFocus(coordinate: cache.target)
        }
        if cache?.code != selectedCache?.code { selectedWaypoint = nil }
        selectedCache = cache
        checkApproach()
    }

    // MARK: - GCVote ratings (Cachebox `Importer.importGcVote`)

    /// The list file the caches are read from and written to.
    var currentListURL: URL? {
        lists.currentName.map { lists.store.url(of: $0) }
    }

    /// Which caches are asked about: those the list shows (filter and search, as Cachebox uses its filter) or
    /// every cache of the list.
    func gcVoteCodes() -> [String] {
        switch gcVote.scope {
        case .shown: listUI.shown(in: lists).map { $0.cache.code }
        case .all: lists.caches.map(\.code)
        }
    }

    /// Loads the ratings and reads the list again afterwards, so that stars and filter see them at once.
    func startGCVoteImport() {
        guard let list = currentListURL else { return }
        gcVote.start(codes: gcVoteCodes(), list: list) { [weak self] in
            guard let self else { return }
            Task {
                await self.lists.loadCaches()
                self.refreshSelection()
            }
        }
    }

    /// Forgets the ratings of the open list ("Bewertungen dieser Liste löschen").
    func clearGCVotes() {
        guard let database = lists.database() else { return }
        try? database.clearGCVotes()
        gcVote.clearResult()
        gcVote.readLastUpdated(list: currentListURL)
        Task {
            await lists.loadCaches()
            refreshSelection()
        }
    }

    /// Updates the selected cache after its flags changed in the list.
    func refreshSelection() {
        guard let code = selectedCache?.code else { return }
        selectedCache = lists.caches.first { $0.code == code }
    }
}

/// `UserDefaults` keys used with `@AppStorage`.
enum StorageKey {
    /// The welcome page was finished (signed in or started without an account).
    static let onboardingCompleted = "onboardingCompleted"
    /// Name and membership of the Geocaching.com account of the last sign-in, so that the account shows up
    /// without a network call. The tokens themselves live in the keychain.
    static let geocachingUsername = "geocaching.username"
    static let geocachingPremium = "geocaching.premium"
}

extension Color {
    /// Cachebox green, used as the app tint. Light: 5.2:1 against white (also white text on green).
    /// Dark: lighter, 4.5:1 on grouped list cells (#1C1C1E) and 5.6:1 on black; white text on it is ~3.8:1,
    /// the same trade-off as the system tint colors in dark mode.
    static let cachebox = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.30, green: 0.58, blue: 0.18, alpha: 1)
            : UIColor(red: 0.24, green: 0.48, blue: 0.13, alpha: 1)
    })
}
