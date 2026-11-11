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
  - Caches: `CacheListModel.swift` (Listen in `Documents/Lists`, Sortierung, Filter, Import), `CacheListView.swift`,
    `CacheListsView.swift`, `CacheFilterView.swift`, `ImportView.swift`, `CacheDetailView.swift`, `HTMLView.swift`
    (WKWebView ohne JavaScript), `LocationModel.swift`, `CachePresentation.swift` (Cachetyp-/Wegpunkt-Icons
    aus Cachebox, `Assets.xcassets/Cachebox`, Namen wie die Sprites dort; Rechte noch ungeklärt, siehe UI-KONZEPT.md),
    `CacheAttributes.swift` (Attribut-Icons wie Cachebox `DescriptionViewControl`: zutreffende zuerst, dann nicht
    zutreffende, Tipp zeigt Text; `Assets.xcassets/Attributes` = `att_<Cachebox-Ordinal>_1/_0`, GC 71/72 → 68/71;
    fehlt ein `_0`-Icon, wird das `_1`-Icon durchgestrichen, Cachebox lässt es weg)
  - Gewählter Cache: `AppState` (Auswahl je Liste, `mapFocus`; `CacheListModel.onOpen` stellt die Auswahl nach jedem
    Öffnen/Import wieder her), `SelectedCacheBar` in `RootView.swift`, Marker und Zentrieren in `ContentView.swift`
    (`MapModel.focus`, wählt eine Karte, die den Ort abdeckt) und `MapsforgeMapView.swift` (`MapMarker`, `MapCenterRequest`)
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
Richtung, Kontextmenü Details/Auf der Karte; auf der Karte Marker für Cache und Wegpunkte mit Koordinaten, die Karte
springt bei neuer Auswahl dorthin (ohne Animation, sonst verwirft MapKit Kachelanfragen) und wechselt bei Bedarf auf
eine Karte, die den Ort abdeckt; ohne passende Karte Hinweis. Website-Kachel „Cacheliste“ ist seit 11.11.2026 kein
„Coming Soon“ mehr. Im Simulator geprüft mit einer erfundenen 300-Cache-Pocket-Query und Testcaches in Hamburg/Harz;
Import-Benchmark (Mac, Release): 1000 Caches mit 5000 Logs 0,46 s, 5000 Caches 2,2 s, Liste laden 6 ms.
Nicht geprüft: echte geocaching.com-Dateien, Import auf echtem Gerät (Dateien in iCloud Drive), iPad.
Offen: alle Caches der Liste auf der Karte und Auswahl per Tipp auf der Karte (Kachel „Offline-Karte“).

Lizenz-Hinweis: Elevate ist CC BY-NC-SA 4.0 (kommerziell nur BY-ND) – nicht ungefragt in eine verteilte App packen;
OAM-Karten und Themes lädt in Cachebox der Nutzer selbst.

Offen (Phase 2): Theme-ZIPs direkt lesen, mehrere Karten gleichzeitig (MultiMapDataStore), Hillshading,
Nachtmodus, Kachel-Cache auf Platte, PNG-Kodierung vermeiden (eigener MKOverlayRenderer), Kartenrotation mit
aufrechten Labels, Pixel-Vergleich gegen Java-AWT-Rendering, SVG `<use>`/Gradienten/`<pattern>` (betrifft z. B.
Elevates `s_mall.svg`), Test auf echtem Gerät.
