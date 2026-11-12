# iCacheBox

iOS-Umsetzung der Android-Geocaching-App Cachebox (github.com/Ging-Buh/cachebox, Java/libGDX).
Ansatz: nativer Neubau in Swift/SwiftUI. Mapsforge-Offlinekarten (`.map` + XML-RenderThemes) sind Pflicht
und werden durch einen eigenen Swift-Port von Mapsforge gerendert (CoreGraphics, Anzeige über MapKit).

## Struktur

- `Packages/Mapsforge/` – Swift Package (LGPL-3.0, Port von mapsforge 0.2x)
  - `MapsforgeCore` – Kartenleser: Header, Index-Cache, POIs/Wege, Mehrsprachigkeit (Port von `mapsforge-map-reader`)
  - `MapsforgeRender` – RenderTheme-Parser inkl. Stylemenü (`StyleMenu.swift`, Kategorien wie Cachebox),
    Render-Instruktionen, Label-Platzierung inkl. Kachel-Abhängigkeiten, CoreText-Text (auch entlang Pfaden),
    Mini-SVG-Renderer für Theme-Symbole, `TileRenderer`
  - `mfdump` – Entwickler-CLI: `info`, `dump` (Tags einer Kachel), `render`, `grid` (Kachelraster, zufällige
    Reihenfolge), `bench`; Theme-Argument `pfad.xml#stil,+overlay,-overlay` wählt Stil/Overlays
  - `Resources/themes/` – interne Themes (default, osmarender) + Symbole/Patterns aus Cachebox
- `Packages/CacheboxCore/` – Swift Package (Apache-2.0, neu geschrieben; Cachebox nur als Funktionsvorlage, GPL!)
  - `Model.swift` (Geocache, Waypoint, CacheLog, Typen), `GPXParser.swift` (Groundspeak 1.0/1.0.1/1.0.2 in GPX 1.0/1.1,
    GSAK-Erweiterung, Wegpunkt-Zuordnung über `gsak:Parent` oder Präfix), `GPXImporter.swift` (GPX/ZIP, Wegpunktdateien
    zuletzt, Abbruch), `CacheDatabase.swift` (eine SQLite-Datei je Liste, Upsert behält Notiz/Favorit/Fund/korrigierte
    Koordinaten), `CacheListStore.swift` (Listen anlegen/umbenennen/löschen), `ZipArchive.swift`, `SQLite.swift`
  - Tests mit erfundenen Testdaten unter `Tests/CacheboxCoreTests/Resources` (PQ-GPX, -wpts, ZIP, GPX 1.1)
- `App/` – iOS-App (Xcode-Projekt, synchronisierter Ordner `App/iCacheBox/`), `MKTileOverlay` mit Mapsforge-Kacheln
  - Fünf Knöpfe unten wie Cachebox (`ViewManager`/`GestureButton`/`CB_TabView`), kein `TabView` mehr:
    `MainButtons.swift` (`MainButton` mit `functions` = Cachebox `addAction`: Ansicht/Funktion, Default, Wischrichtung;
    `MainView` = die Ansichten; `MainButtonBar`, `MainButtonView` = Antippen zeigt die letzte Ansicht des Knopfs
    (`rememberLastAction`), Antippen des aktiven Knopfs öffnet `MainMenuView` (Kontextmenü der Ansicht + Funktionen,
    `compoundMenu`), Wischen führt die Funktion der Richtung aus, Langdruck zeigt nur die Funktionen; Popover mit
    Untermenüs, Einträge laufen nach dem Schließen, damit Sheets/Alerts erscheinen), `MainActions.swift`
    (`AppState.perform`/`isEnabled`, Kontextmenüs je Ansicht, Teilen, Navigieren mit Apple Karten, `Torch`),
    `MenuEntry.swift` (ein Menümodell für Knopf-Popover und Toolbar-Menüs, `MenuEntriesContent`).
    `RootView.MainScreen`: ZStack der Bereiche, einmal erzeugt bleiben sie (wie Tabs); Leiste verschwindet bei Tastatur.
    Bilder `Assets.xcassets/CacheboxButtons` (Tagesskin, Rand-Pixel entfernt). Zustand für die Menüs in `AppState`:
    `view`/`lastViews`, `details` (`SelectedCacheDetails` in `CacheDetailView.swift`: Details des gewählten Caches,
    Hinweis/Notiz/Löschen), `listUI` (`CacheListUI`: Suche, Sheets), `map` (`MapModel`), `compass`
  - Kompass: `CompassView.swift` wie Cachebox `CompassView` ohne Minikarte (Infokasten oben, Kompass unten,
    `CompassOptions` = `CompassShow…`-Einstellungen, UserDefaults `compass.show.*`), `SkyPosition.swift` (Sonne/Mond,
    Formeln von Astronomy Answers/suncalc), Bilder `Assets.xcassets/CacheboxCompass` (`CompassViewFrame`/`Scale`,
    `sonne`, `mond`) und `CacheboxInfo` (Sterne, Größen, `tb`, `FavPoi`)
  - Kacheln zeichnen: `MapsforgeOverlayRenderer.swift` – eigener `MKOverlayRenderer` statt `MKTileOverlayRenderer`
    (der ließ Kacheln bis zum Laden leer/schwarz): Kachel erst auf den Schirm, wenn gerendert, bis dahin die passende
    gecachte Kachel anderer Zoomstufen (nächste darüber vergrößert, bis 3 Stufen darunter verkleinert), sonst
    Theme-Hintergrund; Rendern im Hintergrund, neueste Anfrage zuerst, dann `setNeedsDisplay`. `TileCache` =
    LRU in zwei Stufen (volle Auflösung, verdrängte Kacheln halb aufgelöst nur als Ersatz). Beim Karten-/Theme-/
    Stilwechsel zeigt der neue Renderer die Kacheln des alten, bis die eigenen fertig sind. Kein PNG mehr.
    `overrideUserInterfaceStyle = .light` am `MKMapView`: MapKits Platzhalter-Raster ist im Dunkelmodus schwarz
  - Caches: `CacheListModel.swift` (Listen in `Documents/Lists`, Sortierung, Filter, Import), `CacheListView.swift`,
    `CacheListsView.swift`, `CacheFilterView.swift`, `ImportView.swift`, `CacheDetailView.swift`, `HTMLView.swift`
    (WKWebView ohne JavaScript), `LocationModel.swift`, `CachePresentation.swift` (Cachetyp-/Wegpunkt-Icons
    aus Cachebox, `Assets.xcassets/Cachebox`, Namen wie die Sprites dort; Rechte noch ungeklärt, siehe UI-KONZEPT.md),
    `CacheAttributes.swift` (Attribut-Icons wie Cachebox `DescriptionViewControl`: zutreffende zuerst, dann nicht
    zutreffende, Tipp zeigt Text; `Assets.xcassets/Attributes` = `att_<Cachebox-Ordinal>_1/_0`, GC 71/72 → 68/71;
    fehlt ein `_0`-Icon, wird das `_1`-Icon durchgestrichen, Cachebox lässt es weg)
  - Gewählter Cache: `AppState` (Auswahl je Liste, `mapFocus`; `CacheListModel.onOpen` stellt die Auswahl nach jedem
    Öffnen/Import wieder her), `SelectedCacheBar` in `RootView.swift`, Zentrieren in `ContentView.swift`
    (`MapModel.focus`, wählt eine Karte, die den Ort abdeckt) und `MapsforgeMapView.swift` (`MapCenterRequest`)
  - Caches auf der Karte: `MapMarkers.swift` (`MapMarker` wie Cachebox `WayPointRenderInfo`, `MarkerImages` zeichnet
    Rahmen/Icon/Herz/`deact` je Zoomklasse wie `MapView.render`, `CacheBubble` = Info-Blase), Symbolwahl
    `mapIconName`/`smallMapIconName` in `CachePresentation.swift` (Cachebox `getMapIcon`/`getSmallMapIcon`,
    `Assets.xcassets/CacheboxMap` = `small1…7`, `star`); `MapsforgeMapView.Coordinator` gleicht Annotationen per ID ab,
    baut die Blase erst bei Auswahl, Tipp neben ein Symbol wählt das nächste (≤ 30 pt). Position: `CacheSummary.target`
    (korrigiert, sonst Final mit Koordinaten – `summaries()` holt `finalCoordinate`), auch für Listen-Entfernungen
  - Letzte Karte: `MapModel` merkt Karte/Theme/Stil/Overlays (Pfad relativ zum Quellordner, UserDefaults `map.*`),
    `MapCamera` Mitte + Kachel-Zoom; `CacheMapView.setCenter(_:zoomLevel:)` korrigiert, weil MapKit
    `setVisibleMapRect` in die Safe Area einpasst (auch `centerCoordinate`/`setCenter` meinen die Mitte der Safe Area)
  - Eigene Position und Kartenmodus (wie Cachebox `MapView`/`MapViewBase`): `LocationModel.swift` (Position, Tempo,
    Richtung wie `Locator`: unter 5 km/h Kompass = roter Pfeil, sonst GPS-Kurs = türkis; `headingOrientation` folgt
    dem Gerät), `MapPosition.swift` (`MapState` Free/GPS wie `btnMapState`, UserDefaults `map.state`;
    `OwnPositionView` = Pfeil + Genauigkeitskreis wie `renderPositionMarker`; `EdgeArrowsView` = Pfeile am Kartenrand,
    rot zum gewählten Cache wie `renderTargetArrow`, blau zur eigenen Position – nicht in Cachebox), `MapControls.swift`
    (`MapInfoPanel` wie Cachebox `MapInfoPanel`, `MapStateButton` mit LED, `MapFormat` = Cachebox-Zahlenformate),
    `CacheboxArrows.swift` (Pfeile der Skin als Vektoren nachgezeichnet), `Assets.xcassets/CacheboxUI` (Satellit,
    Karte, Kompassrose aus der Skin). Der Coordinator beobachtet `LocationModel` selbst (`withObservationTracking`),
    damit Kompass-Updates nicht `ContentView` samt tausender Marker neu berechnen; GPS zentriert ohne Animation,
    Pan mit einem Finger → Free, Zoomen/Drehen holt die Position zurück in die Mitte. Kompass und Maßstab platziert
    `CacheMapView` selbst (`MKCompassButton`/`MKScaleView`), sonst lägen sie unter dem Infofeld
  - Kartendownload: `MapCatalog.swift` (Freizeitkarte-Repository-XML), `MapLibrary.swift` (Hintergrund-`URLSession`,
    MD5-Prüfung, Entpacken nach `Documents/Maps` bzw. `Documents/Themes`), `ZipArchive.swift`, `MapDownloadView.swift`
  - `App/iCacheBox-Info.plist` wird mit der generierten Info.plist zusammengeführt (ATS-Ausnahme nur für
    `repository.freizeitkarte-osm.de`, der Katalog gibt es nur per HTTP; Dateien kommen per HTTPS)
- `TestData/` – Testdaten (nicht im Git):
  - `bremen.map`, `expected-bremen-tiles.json` aus `/Users/Shared/LongriShare/@Work/MapsforgeKit/resources/`
    (erzeugt mit mapsforge 0.21.0, Java-Referenz dort)
  - `Hamburg_oam.osm.map` – OpenAndroMaps V5 (ftp.gwdg.de/pub/misc/openstreetmap/openandromaps/mapsV5/germany/Hamburg.zip)
  - `elevate/` – Elevate 5.7 (openandromaps.org/wp-content/users/tobias/Elevate.zip); Tests dazu laufen nur, wenn vorhanden
  - `freizeitkarte-v5/` – Freizeitkarte-Theme (download.freizeitkarte-osm.de/android/2609/freizeitkarte-v5.zip), ebenso
- `docs/anleitung/README.md` – Anleitung (Markdown + `bilder/`), wird auch von der Website unter `/anleitung` gezeigt
- `App/BundledMaps/` – Ordnerreferenz, wird komplett ins App-Bundle kopiert; die App bietet alle `*.map` und
  Theme-XMLs in Unterordnern zur Auswahl an (Inhalt außer README nicht im Git)

## Befehle

```bash
cd Packages/Mapsforge && swift test                     # Leser-Referenztests + Rendertests
cd Packages/CacheboxCore && swift test                  # GPX-Parser, Import, Listen
cd Packages/Mapsforge && swift build -c release && .build/release/mfdump grid ../../TestData/bremen.map 17 68740 42648 4 3 /tmp/grid.png 1
cd App && xcodebuild -project iCacheBox.xcodeproj -scheme iCacheBox -configuration Release \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" -derivedDataPath ../.build/DerivedData build
```

Performance immer mit Release-Builds messen (Debug ist um Faktoren langsamer).

## Konventionen

- Port nah am Java-Original halten (gleiche Semantik, Klassennamen in Kommentaren nennen), damit Abgleich mit
  mapsforge möglich bleibt. Abweichungen bewusst und kommentiert.
- Leser-Änderungen müssen `ReferenceTileTests` bestehen (exakter Abgleich mit Java-Referenz, Toleranz 1e-9°).
- Koordinaten im Renderer: y nach unten, Einheit Punkte (Kachel = 256 pt); Gerätepixel nur über `scale`.
- Java-Quelle des eingebetteten mapsforge-Forks: `mapsforge/` im Cachebox-Repo.

## Stand (Prototyp, Nov. 2026)

Fertig: Kartenleser (verifiziert), RenderTheme v6 (Regeln, Negativ-Matcher, Cache, Stylemenü mit Stilen/Overlays),
area/line/circle/caption/pathText/symbol/lineSymbol, SVG-Symbole und -Patterns, Label-Kollision +
kachelübergreifende Labels, MapKit-App mit Karten-/Theme-/Stil-/Overlay-Auswahl.
OpenAndroMaps (Hamburg) + Elevate 5.7 laufen: alle ~500 Elevate-Ressourcen laden, Stile Wandern/Stadt/Rad/MTB
sichtbar getrennt, Mac @3x 10–41 ms/Kachel, Simulator @3x inkl. PNG ca. 70 ms.

Bewusste Abweichung: ohne Menü-Callback nimmt `RenderTheme.load` den Default-Stil des Stylemenüs
(mapsforge würde alle Kategorien zeichnen). An Kachelgrenzen behält – wie im Original – die zuerst gerenderte
Kachel ihre Labels, das Ergebnis hängt also von der Render-Reihenfolge ab. Theme-XML mit doppelten Attributen
(Freizeitkarte V5) lehnt `XMLParser` ab; `RenderTheme.load` versucht es dann ohne sie (`DuplicateAttributeRepair`).

Kartendownload (Mehr → Karten und Themes): Freizeitkarte-Katalog wie Cachebox `FZKDownload`, mit der ersten Karte
wird das Standard-Design geladen; Karten mit „FZK“ im Header-Kommentar wählen dieses Design automatisch.
Getestet im Simulator mit Bremen (10 MB). Nicht getestet: Pause/Fortsetzen, Neustart durch das System
bei Hintergrund-Downloads, ZIP64 (aktuelle Freizeitkarte-ZIPs sind < 4 GB).

GPX-Import und Listen (Caches-Tab): Import über Dateiauswahl, „Teilen › iCacheBox“ (Document Types in
`iCacheBox-Info.plist`) oder Mehr › GPX importieren; Fortschritt als Karte über den Tabs. Liste = SQLite-Datei wie eine
Cachebox-Datenbank (eigenes Schema, nicht Cachebox-kompatibel). Sortierung nach Entfernung (Standort, sonst gewählter
Cache), Name, Code, D, T, Datum, Favoritenpunkte; Filter: Status dreistufig, Typen (alle), D/T; Suche nach Name, Code,
Owner. Gewählter Cache (wie Cachebox-Slider): Leiste über Caches/Karte/Loggen/Mehr mit D/T/Größe, Entfernung und
Richtung, Kontextmenü Details/Auf der Karte; die Karte springt bei neuer Auswahl dorthin (ohne Animation, sonst
verwirft MapKit Kachelanfragen) und wechselt bei Bedarf auf eine Karte, die den Ort abdeckt; ohne passende Karte
Hinweis. Website-Kachel „Cacheliste“ ist seit 11.11.2026 kein
„Coming Soon“ mehr. Im Simulator geprüft mit einer erfundenen 300-Cache-Pocket-Query und Testcaches in Hamburg/Harz;
Import-Benchmark (Mac, Release): 1000 Caches mit 5000 Logs 0,46 s, 5000 Caches 2,2 s, Liste laden 6 ms.
Nicht geprüft: echte geocaching.com-Dateien, Import auf echtem Gerät (Dateien in iCloud Drive), iPad.

Caches auf der Karte (seit 11.11.2026, Website-Kachel „Offline-Karte“ kein „Coming Soon“ mehr): alle Caches der
gefilterten Liste wie Cachebox `MapViewCacheList` – unter z13 kleine Sprites ohne Rahmen, z13–14 Rahmen 20 pt,
ab z15 32 pt; gewählter Cache immer groß mit rotem Rahmen und obenauf, dazu seine Wegpunkte; Final-/korrigierte
Position und „Solved“-Icon. Tipp öffnet MapKit-Callout mit `CacheBubble` (Auswählen, Info → Details). Beim Start
kommen Karte, Theme, Stil, Mitte und Zoom wieder; die gemerkte Auswahl verschiebt die Karte dann nicht.
Im Simulator geprüft (301 Caches, Lasttest 5117 Caches bei z9 alle sichtbar). Nicht geprüft: Flüssigkeit mit
tausenden sichtbaren Annotationen auf echtem Gerät. Nicht übernommen: Startwegpunkt von Multi/Mystery (Modell hat
keinen), Cachebox-Optionen „eigene Funde ausblenden“, „alle Wegpunkte“, „Originalposition“, Namen/D/T-Sterne an
den Symbolen, Distanzkreis, Wegpunkt-Auswahl.

Eigene Position, GPS/Free und Infofeld (seit 11.11.2026, wie Cachebox): Pfeil in Blickrichtung, Knopf GPS (grüne
LED, Karte folgt) / Free (LED aus, nach Verschieben mit einem Finger; Tipp springt zur Position), Infofeld mit
Kompass, Entfernung zum gewählten Cache, Tempo und Koordinaten der Kartenmitte, Pfeile am Rand zur Position und
zum Cache. Abweichungen: nur Free/GPS (WP, Lock, Car fehlen), Wählen eines Caches im GPS-Modus bewegt die Karte nicht,
„Auf der Karte“ schaltet auf Free; ohne Standort-Freigabe Free. Im Simulator geprüft (fester Ort und simulierte
Route, Zoomen/Drehen im GPS-Modus, Start im GPS-Modus, Hoch-/Querformat, Dunkelmodus, ohne Freigabe). Nicht geprüft:
echter Kompass (roter Pfeil, `headingOrientation` im Querformat), echtes Gerät, Akkuverbrauch mit
`kCLDistanceFilterNone`, VoiceOver.

Lizenz-Hinweis: Elevate ist CC BY-NC-SA 4.0 (kommerziell nur BY-ND) – nicht ungefragt in eine verteilte App packen;
OAM-Karten und Themes lädt in Cachebox der Nutzer selbst.

Knöpfe und Kompass (seit 11.11.2026, wie Cachebox; Website-Kachel „Kompass & Navigation“ kein „Coming Soon“ mehr):
Die Tab-Leiste ist durch die fünf Cachebox-Knöpfe ersetzt
(Bilder der Android-Version, Verhalten von `GestureButton`; Belegung siehe `MainButton.functions`, nicht gebaute
Funktionen ausgegraut). Kompass mit Infokasten (Name/Symbol, Ziel-Koordinaten + GC-Code, eigene Position + Höhe,
Richtung zum Ziel, S/D/T mit Cachebox-Sternen, zuletzt gefunden, Attribute), Entfernung + Genauigkeit, Rose dreht mit
der Richtung, Pfeil rot/türkis wie auf der Karte, Sonne/Mond; Optionen über Knopf-Menü › Ansicht. Abweichungen:
keine Minikarte (erster Schritt), keine Satellitenbalken (iOS liefert keine) und keine Wegpunktbeschreibung (keine
Wegpunktauswahl), Ziel = `CacheSummary.target`; Kompass verkleinert sich unter das Entfernungsfeld statt es zu
überlappen; Querformat mit Kasten links (Cachebox nur Hochformat); Kontextmenü der Wegpunkte/Logs/Spoiler = das der
Beschreibung; Tag/Nacht und Beenden entfallen, „Mehr“ steht für About/Credits. Im Simulator geprüft (Antippen,
zweites Antippen, Wischen in alle Richtungen, Langdruck, Menüs mit Untermenüs, Hinweis/Notiz/Teilen/Kartendownload
aus dem Menü, Filter-Rot, Tastatur, Quer-/Hochformat, Dunkelmodus, Sonne/Mond mit Standort Sydney). Nicht geprüft:
echter Kompass, Taschenlampe (Simulator hat keine), Navigieren (öffnet Apple Karten), VoiceOver, iPad. Die Knopf-
und Kompassbilder sind Bitmaps (88 × 76 bzw. 400 px) und auf @3x leicht weich.

Zoomen ohne schwarze Kacheln (seit 11.11.2026, wie Cachebox): im Simulator geprüft mit künstlich auf 1,5 s
verlangsamtem Rendern (rein/raus über 3 Stufen, Theme-Wechsel, Dunkelmodus). Nicht geprüft: Speicher und
Flüssigkeit auf echtem Gerät (Cache bis ca. 150 MB bei @3x), iPad.

Offen (Phase 2): Minikarte im Kompass, Theme-ZIPs direkt lesen, mehrere Karten gleichzeitig (MultiMapDataStore), Hillshading,
Nachtmodus, Kachel-Cache auf Platte, Kartenrotation mit
aufrechten Labels, Pixel-Vergleich gegen Java-AWT-Rendering, SVG `<use>`/Gradienten/`<pattern>` (betrifft z. B.
Elevates `s_mall.svg`), Test auf echtem Gerät.
