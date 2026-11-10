![Cachebox – too many secrets.](docs/banner.jpg)

# iCachebox

iCachebox bringt [Cachebox](https://github.com/Ging-Buh/cachebox), die Geocaching-App für Android, aufs iPhone –
als nativer Neubau in Swift/SwiftUI. Mapsforge-Offlinekarten (`.map` + XML-RenderThemes) rendert ein eigener
Swift-Port von Mapsforge.

> **Stand:** Prototyp, in Entwicklung. Noch nicht im App Store.

## Was schon läuft

- Mapsforge-Kartenleser, gegen die Java-Referenz verifiziert
- RenderTheme v6 inklusive Stylemenü (Stile und Overlays), SVG-Symbole, Label-Kollision über Kachelgrenzen
- OpenAndroMaps mit Elevate-Theme (Stile Wandern, Stadt, Rad, MTB)
- iOS-App mit Karten-, Theme-, Stil- und Overlay-Auswahl
- Kartendownload (Freizeitkarte-OSM) mit Löschen
- GPX-Import (GPX 1.0/1.1, Pocket-Query-ZIPs) in mehrere Listen, Cacheliste mit Sortierung, Suche und Filter,
  Cache-Details mit Beschreibung, Wegpunkten und Logs

Im Aufbau: Caches auf der Karte, Log-Entwürfe. Die [Anleitung](docs/anleitung/README.md) beschreibt den Stand.

## Aufbau

| Ordner | Inhalt |
| --- | --- |
| [`App/`](App) | iOS-App (Xcode-Projekt, SwiftUI) |
| [`Packages/Mapsforge/`](Packages/Mapsforge) | Swift-Port von Mapsforge (LGPL-3.0): Kartenleser, Renderer, Entwickler-CLI `mfdump` |
| [`Packages/CacheboxCore/`](Packages/CacheboxCore) | Cache-Datenmodell, SQLite-Listen, GPX-Import (Apache-2.0) |
| [`docs/anleitung/`](docs/anleitung) | Anleitung der App (auch auf der Website) |
| [`Website/`](Website) | Promotion-Website (Java, Vaadin) |

## Bauen

```bash
cd Packages/Mapsforge && swift test
```

```bash
cd Packages/CacheboxCore && swift test
```

```bash
cd App && xcodebuild -project iCacheBox.xcodeproj -scheme iCacheBox -configuration Release -destination "platform=iOS Simulator,name=iPhone 17 Pro" -derivedDataPath ../.build/DerivedData build
```

Karten und Themes sind nicht im Repository: `*.map`-Dateien und Theme-Ordner nach `App/BundledMaps/` legen
(siehe README dort). Die Tests brauchen zusätzlich die Testdaten unter `TestData/`.

## Cachebox für Android

Das Original gibt es im [Play Store](https://play.google.com/store/apps/details?id=de.droidcachebox),
den Quellcode unter [Ging-Buh/cachebox](https://github.com/Ging-Buh/cachebox). Logo, Hintergrundbild und Icons
stammen von dort.

## Dank

[Mapsforge](https://mapsforge.org) · [OpenStreetMap](https://www.openstreetmap.org) ·
[OpenAndroMaps](https://www.openandromaps.org)
