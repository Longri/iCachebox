package de.cachebox.website.features;

import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

/** Gemeinsamer Umsetzungsstand für Funktionsseite und öffentliche Priorisierung. */
public final class FeatureCatalog {
    private FeatureCatalog() { }

    public record Feature(String id, String text, boolean done) { }
    public record Section(String icon, String title, String description, List<Feature> features) { }

    // IDs bleiben bei Textänderungen und Umgruppierungen erhalten: Stimmen gehören zur Funktion.
    public static final List<Section> SECTIONS = List.of(
            new Section("cacheListIcon.png", "Cacheliste",
                    "GPX-Dateien und Pocket Queries importieren, in mehreren Listen verwalten, nach Entfernung sortieren, filtern und durchsuchen. Der gewählte Cache bleibt in allen Ansichten im Blick.", List.of(
                    new Feature("cacheliste-01", "GPX-Dateien und Pocket Queries (GPX oder ZIP) importieren, auch über „Teilen“", true),
                    new Feature("cacheliste-02", "Mehrere Cache-Listen (Datenbanken) anlegen, wechseln, umbenennen und löschen", true),
                    new Feature("cacheliste-03", "Cachetyp, Name, GC-Code, Größe, Schwierigkeit und Gelände in der Liste anzeigen", true),
                    new Feature("cacheliste-04", "Entfernung und Richtung zum Cache anzeigen", true),
                    new Feature("cacheliste-05", "Nach Entfernung sortieren", true),
                    new Feature("cacheliste-06", "Automatisch nach Entfernung sortieren und den nächsten Cache wählen", false),
                    new Feature("cacheliste-07", "Liste auf Caches im Umkreis von 5 km beschränken", false),
                    new Feature("cacheliste-08", "Nach Name, GC-Code und Owner suchen", true),
                    new Feature("cacheliste-09", "Nach Status, Typ, Schwierigkeit und Gelände filtern, Filter zurücksetzen", true),
                    new Feature("cacheliste-10", "Nach Größe, Favoritenpunkten, Bewertung, Attributen, GPX-Datei, Notiz, Trackables und korrigierten Koordinaten filtern", false),
                    new Feature("cacheliste-11", "Filtervorlagen „Alle Caches“ und „Alle zu findenden“", true),
                    new Feature("cacheliste-12", "Weitere Filtervorlagen (Schnelle Caches, Anfänger, Highlights, TB ablegen …) und eigene Vorlagen speichern", false),
                    new Feature("cacheliste-13", "Cache als Favorit markieren", true),
                    new Feature("cacheliste-14", "Favoriten für alle gefilterten Caches setzen oder zurücksetzen", false),
                    new Feature("cacheliste-15", "Einzelne Caches sowie gefundene, archivierte oder alle angezeigten löschen", true),
                    new Feature("cacheliste-16", "Cache neu anlegen und bearbeiten", false),
                    new Feature("cacheliste-17", "Cache merken und später wieder aufrufen", false),
                    new Feature("cacheliste-18", "Verlauf der zuletzt gewählten Caches, Verlauf löschen", false),
                    new Feature("cacheliste-19", "GPX-Dateien exportieren", false),
                    new Feature("cacheliste-20", "Datenbank ins Programm kopieren oder hinauskopieren", false),
                    new Feature("cacheliste-21", "GSAK-Datenbank importieren", false),
                    new Feature("cacheliste-22", "Beschreibungs- und Spoilerbilder beim Import vorladen", false),
                    new Feature("cacheliste-23", "Alte Logs beim Import löschen und Datenbank komprimieren", false))),
            new Section("map.png", "Offline-Karte",
                    "Mapsforge-Vektorkarten mit frei wählbarem Theme, Freizeitkarten für ganz Europa direkt in der App laden. Alle Caches der Liste liegen auf der Karte, ein Tipp öffnet ihre Info-Blase. Dein Standort als Pfeil in Blickrichtung, im GPS-Modus folgt dir die Karte.", List.of(
                    new Feature("karte-01", "Mapsforge-Vektorkarten (.map) offline anzeigen", true),
                    new Feature("karte-02", "Online-Karten wählen: Mapnik, OSM Cycle Map, ESRI-Satellitenbilder", false),
                    new Feature("karte-03", "Zusätzliche Kartenebenen über die Grundkarte legen", false),
                    new Feature("karte-04", "Sprache der Kartenbeschriftung wählen (iCachebox folgt der Gerätesprache)", false),
                    new Feature("karte-05", "Karten von Freizeitkarte in der App herunterladen, nach Region mit Dateigröße", true),
                    new Feature("karte-06", "Karten von OpenAndroMaps und mapsforge.org herunterladen", false),
                    new Feature("karte-07", "Karten-Downloads aus dem Browser an die App übergeben", false),
                    new Feature("karte-08", "Theme wählen: interne Themes, Freizeitkarte, Elevate und andere", true),
                    new Feature("karte-09", "Freizeitkarte-Theme herunterladen", true),
                    new Feature("karte-10", "Themes von OpenAndroMaps (Elevate) herunterladen", false),
                    new Feature("karte-11", "Kartenstile wählen, z. B. Wandern, Rad, Mountainbike und Stadt", true),
                    new Feature("karte-12", "Theme-Overlays ein- oder ausblenden, z. B. Einrichtungen, Grenzen, Routen, öffentlicher Verkehr, Unterkünfte und Wegzeichen", true),
                    new Feature("karte-13", "Eigene Themes für Tag, Nacht, Auto-Tag und Auto-Nacht", false),
                    new Feature("karte-14", "Caches mit Typ-Symbol auf der Karte, Tipp öffnet die Info-Blase", true),
                    new Feature("karte-15", "Wegpunkte, Final und korrigierte Position des gewählten Caches anzeigen", true),
                    new Feature("karte-16", "Wegpunkte aller Caches anzeigen", false),
                    new Feature("karte-17", "Kartenanzeige einstellen: Funde ausblenden, Originalposition, Namen, D/T, Infofeld, Luftlinie, Genauigkeitskreis, Fadenkreuz, Entfernung zur Mitte, Distanzkreis", false),
                    new Feature("karte-18", "Eigene Position als Pfeil in Blickrichtung mit Genauigkeitskreis", true),
                    new Feature("karte-19", "Zwischen GPS-Nachführung und freiem Kartenausschnitt wechseln", true),
                    new Feature("karte-20", "Weitere Kartenmodi: Wegpunkt, Sperren und Auto (dynamischer Zoom)", false),
                    new Feature("karte-21", "Infofeld mit Kompass, Entfernung zum Cache, Tempo und Koordinaten", true),
                    new Feature("karte-22", "Karte zoomen und Maßstab anzeigen", true),
                    new Feature("karte-23", "Gewählten Cache auf der Karte zeigen", true),
                    new Feature("karte-24", "Karte nach Kompass ausrichten", false),
                    new Feature("karte-25", "Wegpunkt in der Kartenmitte anlegen", false),
                    new Feature("karte-26", "Ort oder Adresse suchen und auf der Karte anzeigen", false),
                    new Feature("karte-27", "Live-Karte: Caches beim Verschieben über die Geocaching-API nachladen", false),
                    new Feature("karte-28", "Route zum Ziel berechnen und als Track anzeigen", false))),
            new Section("compass.png", "Kompass & Navigation",
                    "Der Kompass wie in Cachebox: Pfeil und Entfernung zum gewählten Cache, dazu Koordinaten, Schwierigkeit, Gelände und Attribute, auf Wunsch Sonne und Mond. Die Route dorthin plant Apple Karten.", List.of(
                    new Feature("navigation-01", "Kompassansicht mit Pfeil und Entfernung zum Ziel", true),
                    new Feature("navigation-02", "Name, Symbol, GC-Code und Zielkoordinaten anzeigen", true),
                    new Feature("navigation-03", "Eigene Koordinaten, Höhe, Genauigkeit und Richtung zum Ziel anzeigen", true),
                    new Feature("navigation-04", "GPS-Satelliten anzeigen (iOS liefert dazu keine Daten)", false),
                    new Feature("navigation-05", "Schwierigkeit, Gelände, Größe, Attribute und letzten Fund anzeigen", true),
                    new Feature("navigation-06", "Sonne und Mond anzeigen", true),
                    new Feature("navigation-07", "Angezeigte Elemente des Kompasses wählen", true),
                    new Feature("navigation-08", "Minikarte im Kompass", false),
                    new Feature("navigation-09", "Beschreibung des Ziel-Wegpunkts anzeigen", false),
                    new Feature("navigation-10", "Externe Navigation zum Ziel aufrufen (Apple Karten)", true),
                    new Feature("navigation-11", "Navigations-App wählen (Cachebox: Google Maps, OsmAnd, Waze …)", false),
                    new Feature("navigation-12", "Ton bei Annäherung an den Cache, bei GPS-Verlust und -Empfang", false),
                    new Feature("navigation-13", "Mein Parkplatz: Parkposition speichern, als Ziel wählen und löschen", false))),
            new Section("fieldnoteListIcon.png", "Loggen unterwegs",
                    "Funde, DNFs und Notizen als Entwurf festhalten und später in Ruhe hochladen.", List.of(
                    new Feature("loggen-01", "Log-Entwürfe anlegen: Gefunden, Nicht gefunden, Notiz, Wartung, Event, Webcam", false),
                    new Feature("loggen-02", "Owner-Logs: aktivieren, deaktivieren, Wartung durchgeführt", false),
                    new Feature("loggen-03", "Schnell-Entwurf mit einem Tipp", false),
                    new Feature("loggen-04", "Entwürfe bearbeiten, Textvorlagen mit Platzhaltern", false),
                    new Feature("loggen-05", "Entwürfe als Feldnotiz oder direkt als Log hochladen, Logbild hochladen", false),
                    new Feature("loggen-06", "Entwürfe als hochgeladen markieren und löschen", false))),
            new Section("dayGcLiveIcon.png", "Geocaching Live",
                    "Caches über die offizielle Geocaching-API laden und aktuell halten.", List.of(
                    new Feature("geocaching-live-01", "Geocaching-Konto verbinden und API-Zugriff autorisieren", false),
                    new Feature("geocaching-live-02", "Cache-Status prüfen und Cache-Daten aktualisieren", false),
                    new Feature("geocaching-live-03", "Caches um GPS-Position, Kartenmitte oder Koordinaten importieren", false),
                    new Feature("geocaching-live-04", "Suchradius, maximale Anzahl, Veröffentlichungsdatum und Importkategorie festlegen", false),
                    new Feature("geocaching-live-05", "Nur verfügbare Caches, eigene und gefundene ausschließen", false),
                    new Feature("geocaching-live-06", "Online nach Titel, Owner oder GC-Code suchen", false),
                    new Feature("geocaching-live-07", "Pocket Queries von geocaching.com laden", false),
                    new Feature("geocaching-live-08", "Logs, Logs von Freunden und Logbilder nachladen", false),
                    new Feature("geocaching-live-09", "Beobachtungs-, Favoriten-, Ignorier- und Bookmark-Listen", false),
                    new Feature("geocaching-live-10", "Korrigierte Koordinaten und Notiz hochladen", false),
                    new Feature("geocaching-live-11", "Owner per E-Mail oder Nachricht kontaktieren", false),
                    new Feature("geocaching-live-12", "Lab-Caches laden", false),
                    new Feature("geocaching-live-13", "GCVote-Bewertungen importieren", false))),
            new Section("solverIcon.png", "Solver",
                    "Formeln und Variablen für Multis und Mysteries rechnen, ohne Zettel und Stift.", List.of(
                    new Feature("solver-01", "Solver: Formeln mit Variablen und Funktionen, fehlende Variablen einfügen", false),
                    new Feature("solver-02", "Solver 2: Zeilen bearbeiten, Ergebnis als Wegpunkt oder Kartenmitte", false))),
            new Section("trackListIcon.png", "Tracks",
                    "Wege aufzeichnen, GPX-Tracks laden und auf der Karte anzeigen.", List.of(
                    new Feature("tracks-01", "Track aufzeichnen: Start, Pause, Stopp, Punktabstand, Start mit der App", false),
                    new Feature("tracks-02", "GPX-Tracks laden, auch automatisch beim Start", false),
                    new Feature("tracks-03", "Tracks erzeugen: Punkt zu Punkt, Projektion, Kreis", false),
                    new Feature("tracks-04", "Trackliste: auf der Karte zeigen, umbenennen, speichern, entfernen, löschen", false))),
            new Section("tb.png", "Trackables",
                    "Travelbugs und Coins verwalten: entdecken, mitnehmen, ablegen.", List.of(
                    new Feature("trackables-01", "Eigenes Trackable-Inventar laden und aktualisieren", false),
                    new Feature("trackables-02", "Trackable per Code suchen und Details anzeigen", false),
                    new Feature("trackables-03", "Trackables loggen: entdeckt, besucht, abgelegt, mitgenommen, Notiz – auch für alle auf einmal", false))),
            new Section("bigTraditional.png", "Cache-Details & Wegpunkte",
                    "Beschreibung, Hinweise und zusätzliche Informationen zum ausgewählten Cache.", List.of(
                    new Feature("cache-details-01", "Cachebeschreibung mit Bildern und Links anzeigen", true),
                    new Feature("cache-details-02", "Attribute als Symbole, Tipp zeigt die Bedeutung", true),
                    new Feature("cache-details-03", "Trackables im Cache anzeigen", true),
                    new Feature("cache-details-04", "Listing im Browser öffnen", true),
                    new Feature("cache-details-05", "Logbuch und Karte auf geocaching.com öffnen", false),
                    new Feature("cache-details-06", "Hinweis anzeigen", true),
                    new Feature("cache-details-07", "Hinweis ver- und entschlüsseln (ROT13)", false),
                    new Feature("cache-details-08", "Wegpunkte mit Koordinaten, Kommentar und Entfernung anzeigen", true),
                    new Feature("cache-details-09", "Korrigierte Koordinaten anzeigen", true),
                    new Feature("cache-details-10", "Wegpunkt als Ziel auswählen", false),
                    new Feature("cache-details-11", "Wegpunkte anlegen, bearbeiten und löschen, auch per Projektion oder von der GPS-Position", false),
                    new Feature("cache-details-12", "Logs mit Logtyp, Verfasser, Datum und Text lesen", true),
                    new Feature("cache-details-13", "Logtext kopieren, Log im Browser öffnen, Finder anschreiben", false),
                    new Feature("cache-details-14", "Persönliche Notiz bearbeiten (bleibt beim Import erhalten)", true),
                    new Feature("cache-details-15", "Cache teilen", true),
                    new Feature("cache-details-16", "Kurzklick-Reaktion der Liste umschalten", false))),
            new Section("fieldnoteListIcon.png", "Fotos, Spoiler & Aufnahmen",
                    "Bilder zum Cache ansehen und Aufnahmen unterwegs starten.", List.of(
                    new Feature("aufnahmen-01", "Spoilerbilder als Vorschau und im Vollbild anzeigen, zoomen", false),
                    new Feature("aufnahmen-02", "Spoiler und Logbilder nachladen", false),
                    new Feature("aufnahmen-03", "Bilder in einer anderen App öffnen", false),
                    new Feature("aufnahmen-04", "Foto aufnehmen", false),
                    new Feature("aufnahmen-05", "Video aufnehmen", false),
                    new Feature("aufnahmen-06", "Sprachaufzeichnung starten", false))),
            new Section("cb.png", "Bedienung & Informationen",
                    "Schnell zwischen Ansichten wechseln und den Gerätestatus im Blick behalten.", List.of(
                    new Feature("bedienung-01", "Fünf Knöpfe: Tippen, Wischgesten und Langdruck wie in Cachebox", true),
                    new Feature("bedienung-02", "Kontextmenü je Ansicht", true),
                    new Feature("bedienung-03", "Gewählter Cache oben in allen Ansichten, mit Zusatzknöpfen und Cache-Info", true),
                    new Feature("bedienung-04", "Zusatzknöpfe selbst belegen", false),
                    new Feature("bedienung-05", "Taschenlampe", true),
                    new Feature("bedienung-06", "App-Version anzeigen", true),
                    new Feature("bedienung-07", "Anzahl gefundener Caches und Credits anzeigen", false),
                    new Feature("bedienung-08", "Tag- und Nachtskin umschalten", false),
                    new Feature("bedienung-09", "Einstellungen: Textvorlagen, Karte, GPS, Töne, Skin, Auto-Modus", false),
                    new Feature("bedienung-10", "Sprache wählen (Cachebox: acht Sprachen, iCachebox nur Deutsch)", false),
                    new Feature("bedienung-11", "Englische Maßeinheiten (Meilen, Fuß)", false),
                    new Feature("bedienung-12", "Hilfe in der App", false))));

    public static Set<String> openIds() {
        return SECTIONS.stream().flatMap(section -> section.features().stream())
                .filter(feature -> !feature.done()).map(Feature::id).collect(Collectors.toUnmodifiableSet());
    }
}
