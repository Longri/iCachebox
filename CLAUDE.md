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
- `App/` – iOS-App (Xcode-Projekt, synchronisierter Ordner `App/iCacheBox/`), `MKTileOverlay` mit Mapsforge-Kacheln
- `TestData/` – Testdaten (nicht im Git):
  - `bremen.map`, `expected-bremen-tiles.json` aus `/Users/Shared/LongriShare/@Work/MapsforgeKit/resources/`
    (erzeugt mit mapsforge 0.21.0, Java-Referenz dort)
  - `Hamburg_oam.osm.map` – OpenAndroMaps V5 (ftp.gwdg.de/pub/misc/openstreetmap/openandromaps/mapsV5/germany/Hamburg.zip)
  - `elevate/` – Elevate 5.7 (openandromaps.org/wp-content/users/tobias/Elevate.zip); Tests dazu laufen nur, wenn vorhanden
- `App/BundledMaps/` – Ordnerreferenz, wird komplett ins App-Bundle kopiert; die App bietet alle `*.map` und
  Theme-XMLs in Unterordnern zur Auswahl an (Inhalt außer README nicht im Git)

## Befehle

```bash
cd Packages/Mapsforge && swift test                     # Leser-Referenztests + Rendertests
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
Kachel ihre Labels, das Ergebnis hängt also von der Render-Reihenfolge ab.

Lizenz-Hinweis: Elevate ist CC BY-NC-SA 4.0 (kommerziell nur BY-ND) – nicht ungefragt in eine verteilte App packen;
OAM-Karten und Themes lädt in Cachebox der Nutzer selbst.

Offen (Phase 2): Theme-ZIPs direkt lesen, mehrere Karten gleichzeitig (MultiMapDataStore), Hillshading,
Nachtmodus, Kachel-Cache auf Platte, PNG-Kodierung vermeiden (eigener MKOverlayRenderer), Kartenrotation mit
aufrechten Labels, Pixel-Vergleich gegen Java-AWT-Rendering, SVG `<use>`/Gradienten/`<pattern>` (betrifft z. B.
Elevates `s_mall.svg`), Test auf echtem Gerät.
