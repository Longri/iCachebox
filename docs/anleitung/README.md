# iCacheBox – Anleitung

iCacheBox ist Cachebox für das iPhone: deine Geocaches und Offline-Karten auf dem Gerät, auch dort, wo es kein Netz gibt.
Diese Anleitung beschreibt den aktuellen Prototyp (Stand November 2026). Was noch fehlt, steht am Ende.

## Überblick

Die App hat unten fünf Bereiche:

| Bereich | Wofür |
| --- | --- |
| **Caches** | Die Caches der geöffneten Liste, sortiert nach Entfernung. Hier importierst du GPX-Dateien und verwaltest deine Listen. |
| **Cache** | Alles zum gewählten Cache: Beschreibung, Wegpunkte, Logs, Hinweis und deine Notiz. |
| **Karte** | Die Offline-Karte mit frei wählbarem Design. |
| **Loggen** | Log-Entwürfe (noch im Aufbau). |
| **Mehr** | Geocaching-Konto, GPX-Import, Karten und Themes, Einstellungen. |

Der gewählte Cache steht als Leiste über den Bereichen. Ein Tipp darauf öffnet seine Details.

## Erste Schritte

1. Lade eine GPX-Datei oder Pocket Query auf dein iPhone, zum Beispiel aus einer Mail oder über die Dateien-App.
2. Öffne **Caches** und tippe auf **GPX importieren**. iCacheBox legt dabei deine erste Liste „Meine Caches“ an.
3. Erlaube beim ersten Mal den Zugriff auf deinen Standort. Dann sortiert die App die Caches nach Entfernung und zeigt
   Richtung und Abstand zu jedem Cache.
4. Lade unter **Mehr › Karten und Themes** eine Offline-Karte deiner Gegend.

## Caches importieren

![Importieren](bilder/import.png)

iCacheBox liest GPX-Dateien, wie sie geocaching.com, GSAK, c:geo und Opencaching erzeugen
(GPX 1.0 und 1.1 mit Groundspeak-Erweiterung), und Pocket Queries als ZIP-Datei.

So importierst du:

1. Tippe in **Caches** oben rechts auf **⋯ › GPX importieren** oder gehe zu **Mehr › GPX importieren**.
2. Wähle unter **Importieren in** die Liste, in die die Caches sollen: die geöffnete, eine andere oder eine
   **Neue Liste** mit eigenem Namen.
3. Tippe auf **Dateien wählen** und wähle eine oder mehrere Dateien aus. Mehrere Dateien auf einmal sind kein
   Problem.

Oben erscheint dann eine Anzeige mit dem Fortschritt, am Ende mit einer Zusammenfassung, zum Beispiel
„301 neue Caches, 159 Wegpunkte, 780 Logs“. Mit **Abbrechen** hältst du einen langen Import an; was bis dahin
gelesen ist, bleibt in der Liste.

**Schneller Weg:** Eine GPX- oder ZIP-Datei lässt sich auch direkt aus Dateien, Mail oder Safari öffnen:
**Teilen › iCacheBox**. Sie landet dann in der geöffneten Liste.

**Pocket Queries:** Eine Pocket Query besteht aus zwei Dateien, den Caches (`1234567.gpx`) und den zusätzlichen
Wegpunkten (`1234567-wpts.gpx`). Importiere einfach die ZIP-Datei; iCacheBox ordnet Parkplätze, Stationen und
Finals ihren Caches zu.

**Erneut importieren:** Importierst du einen Cache, der schon in der Liste ist, aktualisiert iCacheBox ihn mit den
neuen Daten (Beschreibung, Status, Logs). Erhalten bleiben deine Notiz, deine Favoriten-Markierung, korrigierte
Koordinaten und die Markierung „gefunden“. Eine leere Beschreibung in der neuen Datei überschreibt die alte nicht.

## Listen verwalten

![Listen wechseln](bilder/listenmenue.png)

Wie in Cachebox ist jede Liste eine eigene Datenbank, zum Beispiel eine für zu Hause und eine für den Urlaub.

- **Liste wechseln:** Tippe in **Caches** auf den Namen der Liste oben in der Mitte und wähle eine andere.
  iCacheBox merkt sich je Liste den zuletzt gewählten Cache.
- **Listen verwalten:** Im selben Menü öffnet **Listen verwalten** die Übersicht mit Anzahl der Caches,
  Speicherbedarf und letztem Import.
- **Neue Liste:** In der Übersicht mit **+**.
- **Umbenennen oder löschen:** Eine Liste nach links wischen oder lange drücken. Löschen entfernt die Liste mit
  allen Caches, Notizen und Markierungen; das lässt sich nicht rückgängig machen.

![Listen verwalten](bilder/listen.png)

## Die Cacheliste

![Cacheliste](bilder/liste.png)

Jede Zeile zeigt:

- links das Symbol des Cache-Typs, darauf ein grüner Haken für gefunden, ein Stern für Favorit, ein Stift für
  korrigierte Koordinaten und ein Verbotszeichen, wenn der Cache deaktiviert oder archiviert ist;
- den Namen (rot, wenn der Cache nicht verfügbar ist, durchgestrichen, wenn er archiviert ist);
- GC-Code, Schwierigkeit (D), Gelände (T) und Größe (M = Micro, S = Small, R = Regular, L = Large, V = virtuell,
  O = andere);
- falls vorhanden Trackables, Favoritenpunkte und zusätzliche Wegpunkte;
- rechts die Entfernung und einen Pfeil in Richtung des Caches.

Über der Liste steht, wie viele Caches du siehst, zum Beispiel „200 von 301 Caches · nach Entfernung“.

**Cache wählen:** Antippen wählt den Cache und öffnet seine Details. Nach rechts wischen zeigt ihn auf der Karte,
nach links wischen markiert ihn als Favorit. Langes Drücken bietet außerdem **Als gefunden markieren**.

**Suchen:** Das Suchfeld findet Caches nach Name, GC-Code oder Owner.

**Sortieren:** Unter **⋯ › Sortieren** stehen Entfernung, Name, GC-Code, Schwierigkeit, Gelände, Neueste zuerst
und Favoritenpunkte zur Wahl. Ohne Standort misst iCacheBox die Entfernung vom gewählten Cache aus; der Pfeil ist
dann grau.

**Filtern:** Das Filtersymbol oben links öffnet den Filter. Es ist gefüllt, solange ein Filter aktiv ist.

![Filter](bilder/filter.png)

- **Vorlagen:** „Alle Caches“ oder „Noch zu finden“ (nicht gefunden, verfügbar, nicht archiviert).
- **Status:** Für Gefunden, Deaktiviert, Archiviert und Favoriten jeweils „Alle“, „Nur“ oder „Ohne“.
- **Schwierigkeit und Gelände:** Bereich von 1 bis 5.
- **Typen:** Nur die angehakten Cache-Typen; ohne Auswahl alle.

**Aufräumen:** Unter **⋯ › Caches löschen** entfernst du alle gefundenen, alle archivierten oder alle gerade
angezeigten Caches aus der Liste. Ein erneuter Import holt sie zurück.

## Cache-Details

![Cache-Details](bilder/details.png)

Der Bereich **Cache** zeigt den gewählten Cache. Oben schaltest du um zwischen:

- **Beschreibung:** Typ, Owner, Schwierigkeit und Gelände, Größe, Koordinaten, Versteckdatum, Region,
  Favoritenpunkte, Trackables, Attribute und die Beschreibung des Owners. Links in der Beschreibung öffnen Safari.
- **Wegpunkte:** Der Cache selbst und alle zusätzlichen Wegpunkte mit Typ, Koordinaten, Kommentar und Entfernung.
  Wegpunkte mit verborgenen Koordinaten sind als solche markiert.
- **Logs:** Die Logs aus der GPX-Datei, die neuesten zuerst.
- **Spoiler:** Spoilerbilder lädt iCacheBox noch nicht.

Die Glühbirne oben rechts zeigt den **Hinweis**. Unter **⋯** findest du außerdem: auf der Karte zeigen, als
gefunden markieren, Favorit, **Notiz bearbeiten** (deine eigene Notiz, die beim nächsten Import erhalten bleibt),
Koordinaten kopieren, im Browser öffnen und den Cache aus der Liste löschen.

## Offline-Karten

![Karten und Themes](bilder/karten.png)

iCacheBox zeichnet Mapsforge-Karten direkt auf dem iPhone, ganz ohne Netz.

**Karten laden:** Unter **Mehr › Karten und Themes** stehen die Freizeitkarten des Freizeitkarte-OSM-Projekts für
ganz Europa. Tippe auf den Pfeil neben einer Region. Große Karten (ab 100 MB) fragen vorher nach und zeigen den
nötigen Speicherplatz. Der Download läuft weiter, wenn du die App verlässt; der Stopp-Knopf hält ihn an, das
Abspielsymbol setzt ihn fort. Mit der ersten Karte lädt iCacheBox das passende Design „Standard-Design V5“ mit.

**Karte anzeigen:** Im Bereich **Karte** wählst du über das Ebenen-Symbol oben rechts die Karte, das Theme und
den Stil. Freizeitkarten bekommen automatisch ihr Design.

**Löschen:** Unter **Auf diesem Gerät** hat jede Karte und jedes Design einen roten Mülleimer. Vor dem Löschen
fragt die App nach und zeigt, wie viel Speicher frei wird.

**Quellenangabe:** Karten: FZK-Projekt (CC BY 3.0) · Kartendaten © OpenStreetMap-Mitwirkende (ODbL) ·
Höhenlinien: sonny.4lima.de.

## Fragen und Antworten

**Woher bekomme ich GPX-Dateien?**
Von geocaching.com (einzelne Caches als „GPX-Datei“, Pocket Queries mit Premium-Mitgliedschaft), aus GSAK, aus
c:geo (Export als GPX) oder von Opencaching. Auch Cachebox für Android exportiert GPX-Dateien.

**Wo liegen meine Daten?**
Nur auf dem iPhone. Jede Liste ist eine SQLite-Datei; Karten und Designs liegen ebenfalls auf dem Gerät.
Karten sind von der iCloud-Sicherung ausgenommen, weil sie sich jederzeit wieder laden lassen.

**Warum fehlt die Entfernung?**
Ohne Freigabe des Standorts misst iCacheBox vom gewählten Cache aus. Die Freigabe änderst du in den
iOS-Einstellungen unter **Datenschutz & Sicherheit › Ortungsdienste › iCacheBox**.

**Die Datei lässt sich nicht importieren.**
iCacheBox braucht GPX-Dateien mit Geocaches (Groundspeak-Erweiterung). Reine Track- oder Routendateien enthalten
keine Caches. Ist die Datei beschädigt, nennt die Fehlermeldung die Zeile, an der das Lesen scheiterte.

## Noch nicht enthalten

Im Vergleich zu Cachebox für Android fehlen noch: Laden und Aktualisieren über die Geocaching-API, Spoilerbilder,
Caches auf der Karte, Kompass und Navigation, Feldnotizen hochladen, Solver, Tracks und Trackables.
