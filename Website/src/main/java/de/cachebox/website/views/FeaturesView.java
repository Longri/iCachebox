package de.cachebox.website.views;

import com.vaadin.flow.component.checkbox.Checkbox;
import com.vaadin.flow.component.html.Div;
import com.vaadin.flow.component.html.Span;
import com.vaadin.flow.server.auth.AnonymousAllowed;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import com.vaadin.flow.router.RouterLink;
import de.cachebox.website.MainLayout;
import java.util.Arrays;

@AnonymousAllowed
@Route(value = "funktionen", layout = MainLayout.class)
@PageTitle("Funktionen – iCachebox")
public class FeaturesView extends Page {

    public FeaturesView() {
        super("Was iCachebox kann",
                "iCachebox ist dein Werkzeugkasten für die Dosensuche: Alles, was du unterwegs brauchst, "
                        + "liegt auf dem Gerät – auch dort, wo es kein Netz gibt. "
                        + "Die Checklisten zählen die Funktionen von Cachebox für Android auf; abgehakt ist, "
                        + "was iCachebox schon kann (Stand: 12. November 2026).");

        card("cacheListIcon.png", "Cacheliste",
                "GPX-Dateien und Pocket Queries importieren, in mehreren Listen verwalten, nach Entfernung "
                        + "sortieren, filtern und durchsuchen. Der gewählte Cache bleibt in allen Ansichten im Blick.",
                checklist(
                        done("GPX-Dateien und Pocket Queries (GPX oder ZIP) importieren, auch über „Teilen“"),
                        done("Mehrere Cache-Listen (Datenbanken) anlegen, wechseln, umbenennen und löschen"),
                        done("Cachetyp, Name, GC-Code, Größe, Schwierigkeit und Gelände in der Liste anzeigen"),
                        done("Entfernung und Richtung zum Cache anzeigen"),
                        done("Nach Entfernung sortieren"),
                        todo("Automatisch nach Entfernung sortieren und den nächsten Cache wählen"),
                        todo("Liste auf Caches im Umkreis von 5 km beschränken"),
                        done("Nach Name, GC-Code und Owner suchen"),
                        done("Nach Status, Typ, Schwierigkeit und Gelände filtern, Filter zurücksetzen"),
                        todo("Nach Größe, Favoritenpunkten, Bewertung, Attributen, GPX-Datei, Notiz, "
                                + "Trackables und korrigierten Koordinaten filtern"),
                        done("Filtervorlagen „Alle Caches“ und „Alle zu findenden“"),
                        todo("Weitere Filtervorlagen (Schnelle Caches, Anfänger, Highlights, TB ablegen …) "
                                + "und eigene Vorlagen speichern"),
                        done("Cache als Favorit markieren"),
                        todo("Favoriten für alle gefilterten Caches setzen oder zurücksetzen"),
                        done("Einzelne Caches sowie gefundene, archivierte oder alle angezeigten löschen"),
                        todo("Cache neu anlegen und bearbeiten"),
                        todo("Cache merken und später wieder aufrufen"),
                        todo("Verlauf der zuletzt gewählten Caches, Verlauf löschen"),
                        todo("GPX-Dateien exportieren"),
                        todo("Datenbank ins Programm kopieren oder hinauskopieren"),
                        todo("GSAK-Datenbank importieren"),
                        todo("Beschreibungs- und Spoilerbilder beim Import vorladen"),
                        todo("Alte Logs beim Import löschen und Datenbank komprimieren")),
                manual());
        card("map.png", "Offline-Karte",
                "Mapsforge-Vektorkarten mit frei wählbarem Theme, Freizeitkarten für ganz Europa direkt in der App "
                        + "laden. Alle Caches der Liste liegen auf der Karte, ein Tipp öffnet ihre Info-Blase. "
                        + "Dein Standort als Pfeil in Blickrichtung, im GPS-Modus folgt dir die Karte.",
                checklist(
                        done("Mapsforge-Vektorkarten (.map) offline anzeigen"),
                        todo("Online-Karten wählen: Mapnik, OSM Cycle Map, ESRI-Satellitenbilder"),
                        todo("Zusätzliche Kartenebenen über die Grundkarte legen"),
                        todo("Sprache der Kartenbeschriftung wählen (iCachebox folgt der Gerätesprache)"),
                        done("Karten von Freizeitkarte in der App herunterladen, nach Region mit Dateigröße"),
                        todo("Karten von OpenAndroMaps und mapsforge.org herunterladen"),
                        todo("Karten-Downloads aus dem Browser an die App übergeben"),
                        done("Theme wählen: interne Themes, Freizeitkarte, Elevate und andere"),
                        done("Freizeitkarte-Theme herunterladen"),
                        todo("Themes von OpenAndroMaps (Elevate) herunterladen"),
                        done("Kartenstile wählen, z. B. Wandern, Rad, Mountainbike und Stadt"),
                        done("Theme-Overlays ein- oder ausblenden, z. B. Einrichtungen, Grenzen, Routen, "
                                + "öffentlicher Verkehr, Unterkünfte und Wegzeichen"),
                        todo("Eigene Themes für Tag, Nacht, Auto-Tag und Auto-Nacht"),
                        done("Caches mit Typ-Symbol auf der Karte, Tipp öffnet die Info-Blase"),
                        done("Wegpunkte, Final und korrigierte Position des gewählten Caches anzeigen"),
                        todo("Wegpunkte aller Caches anzeigen"),
                        todo("Kartenanzeige einstellen: Funde ausblenden, Originalposition, Namen, D/T, Infofeld, "
                                + "Luftlinie, Genauigkeitskreis, Fadenkreuz, Entfernung zur Mitte, Distanzkreis"),
                        done("Eigene Position als Pfeil in Blickrichtung mit Genauigkeitskreis"),
                        done("Zwischen GPS-Nachführung und freiem Kartenausschnitt wechseln"),
                        todo("Weitere Kartenmodi: Wegpunkt, Sperren und Auto (dynamischer Zoom)"),
                        done("Infofeld mit Kompass, Entfernung zum Cache, Tempo und Koordinaten"),
                        done("Karte zoomen und Maßstab anzeigen"),
                        done("Gewählten Cache auf der Karte zeigen"),
                        todo("Karte nach Kompass ausrichten"),
                        todo("Wegpunkt in der Kartenmitte anlegen"),
                        todo("Ort oder Adresse suchen und auf der Karte anzeigen"),
                        todo("Live-Karte: Caches beim Verschieben über die Geocaching-API nachladen"),
                        todo("Route zum Ziel berechnen und als Track anzeigen")),
                manual());
        card("compass.png", "Kompass & Navigation",
                "Der Kompass wie in Cachebox: Pfeil und Entfernung zum gewählten Cache, dazu Koordinaten, "
                        + "Schwierigkeit, Gelände und Attribute, auf Wunsch Sonne und Mond. Die Route dorthin "
                        + "plant Apple Karten.",
                checklist(
                        done("Kompassansicht mit Pfeil und Entfernung zum Ziel"),
                        done("Name, Symbol, GC-Code und Zielkoordinaten anzeigen"),
                        done("Eigene Koordinaten, Höhe, Genauigkeit und Richtung zum Ziel anzeigen"),
                        todo("GPS-Satelliten anzeigen (iOS liefert dazu keine Daten)"),
                        done("Schwierigkeit, Gelände, Größe, Attribute und letzten Fund anzeigen"),
                        done("Sonne und Mond anzeigen"),
                        done("Angezeigte Elemente des Kompasses wählen"),
                        todo("Minikarte im Kompass"),
                        todo("Beschreibung des Ziel-Wegpunkts anzeigen"),
                        done("Externe Navigation zum Ziel aufrufen (Apple Karten)"),
                        todo("Navigations-App wählen (Cachebox: Google Maps, OsmAnd, Waze …)"),
                        todo("Ton bei Annäherung an den Cache, bei GPS-Verlust und -Empfang"),
                        todo("Mein Parkplatz: Parkposition speichern, als Ziel wählen und löschen")),
                manual());
        comingSoon(card("fieldnoteListIcon.png", "Loggen unterwegs",
                "Funde, DNFs und Notizen als Entwurf festhalten und später in Ruhe hochladen.",
                checklist(
                        todo("Log-Entwürfe anlegen: Gefunden, Nicht gefunden, Notiz, Wartung, Event, Webcam"),
                        todo("Owner-Logs: aktivieren, deaktivieren, Wartung durchgeführt"),
                        todo("Schnell-Entwurf mit einem Tipp"),
                        todo("Entwürfe bearbeiten, Textvorlagen mit Platzhaltern"),
                        todo("Entwürfe als Feldnotiz oder direkt als Log hochladen, Logbild hochladen"),
                        todo("Entwürfe als hochgeladen markieren und löschen"))));
        comingSoon(card("dayGcLiveIcon.png", "Geocaching Live",
                "Caches über die offizielle Geocaching-API laden und aktuell halten.",
                checklist(
                        todo("Geocaching-Konto verbinden und API-Zugriff autorisieren"),
                        todo("Cache-Status prüfen und Cache-Daten aktualisieren"),
                        todo("Caches um GPS-Position, Kartenmitte oder Koordinaten importieren"),
                        todo("Suchradius, maximale Anzahl, Veröffentlichungsdatum und Importkategorie festlegen"),
                        todo("Nur verfügbare Caches, eigene und gefundene ausschließen"),
                        todo("Online nach Titel, Owner oder GC-Code suchen"),
                        todo("Pocket Queries von geocaching.com laden"),
                        todo("Logs, Logs von Freunden und Logbilder nachladen"),
                        todo("Beobachtungs-, Favoriten-, Ignorier- und Bookmark-Listen"),
                        todo("Korrigierte Koordinaten und Notiz hochladen"),
                        todo("Owner per E-Mail oder Nachricht kontaktieren"),
                        todo("Lab-Caches laden"),
                        todo("GCVote-Bewertungen importieren"))));
        comingSoon(card("solverIcon.png", "Solver",
                "Formeln und Variablen für Multis und Mysteries rechnen, ohne Zettel und Stift.",
                checklist(
                        todo("Solver: Formeln mit Variablen und Funktionen, fehlende Variablen einfügen"),
                        todo("Solver 2: Zeilen bearbeiten, Ergebnis als Wegpunkt oder Kartenmitte"))));
        comingSoon(card("trackListIcon.png", "Tracks",
                "Wege aufzeichnen, GPX-Tracks laden und auf der Karte anzeigen.",
                checklist(
                        todo("Track aufzeichnen: Start, Pause, Stopp, Punktabstand, Start mit der App"),
                        todo("GPX-Tracks laden, auch automatisch beim Start"),
                        todo("Tracks erzeugen: Punkt zu Punkt, Projektion, Kreis"),
                        todo("Trackliste: auf der Karte zeigen, umbenennen, speichern, entfernen, löschen"))));
        comingSoon(card("tb.png", "Trackables",
                "Travelbugs und Coins verwalten: entdecken, mitnehmen, ablegen.",
                checklist(
                        todo("Eigenes Trackable-Inventar laden und aktualisieren"),
                        todo("Trackable per Code suchen und Details anzeigen"),
                        todo("Trackables loggen: entdeckt, besucht, abgelegt, mitgenommen, Notiz – "
                                + "auch für alle auf einmal"))));

        card("bigTraditional.png", "Cache-Details & Wegpunkte",
                "Beschreibung, Hinweise und zusätzliche Informationen zum ausgewählten Cache.",
                checklist(
                        done("Cachebeschreibung mit Bildern und Links anzeigen"),
                        done("Attribute als Symbole, Tipp zeigt die Bedeutung"),
                        done("Trackables im Cache anzeigen"),
                        done("Listing im Browser öffnen"),
                        todo("Logbuch und Karte auf geocaching.com öffnen"),
                        done("Hinweis anzeigen"),
                        todo("Hinweis ver- und entschlüsseln (ROT13)"),
                        done("Wegpunkte mit Koordinaten, Kommentar und Entfernung anzeigen"),
                        done("Korrigierte Koordinaten anzeigen"),
                        todo("Wegpunkt als Ziel auswählen"),
                        todo("Wegpunkte anlegen, bearbeiten und löschen, auch per Projektion "
                                + "oder von der GPS-Position"),
                        done("Logs mit Logtyp, Verfasser, Datum und Text lesen"),
                        todo("Logtext kopieren, Log im Browser öffnen, Finder anschreiben"),
                        done("Persönliche Notiz bearbeiten (bleibt beim Import erhalten)"),
                        done("Cache teilen"),
                        todo("Kurzklick-Reaktion der Liste umschalten")));
        card("fieldnoteListIcon.png", "Fotos, Spoiler & Aufnahmen",
                "Bilder zum Cache ansehen und Aufnahmen unterwegs starten.",
                checklist(
                        todo("Spoilerbilder als Vorschau und im Vollbild anzeigen, zoomen"),
                        todo("Spoiler und Logbilder nachladen"),
                        todo("Bilder in einer anderen App öffnen"),
                        todo("Foto aufnehmen"),
                        todo("Video aufnehmen"),
                        todo("Sprachaufzeichnung starten")));
        card("cb.png", "Bedienung & Informationen",
                "Schnell zwischen Ansichten wechseln und den Gerätestatus im Blick behalten.",
                checklist(
                        done("Fünf Knöpfe: Tippen, Wischgesten und Langdruck wie in Cachebox"),
                        done("Kontextmenü je Ansicht"),
                        done("Gewählter Cache oben in allen Ansichten, mit Zusatzknöpfen und Cache-Info"),
                        todo("Zusatzknöpfe selbst belegen"),
                        done("Taschenlampe"),
                        done("App-Version anzeigen"),
                        todo("Anzahl gefundener Caches und Credits anzeigen"),
                        todo("Tag- und Nachtskin umschalten"),
                        todo("Einstellungen: Textvorlagen, Karte, GPS, Töne, Skin, Auto-Modus"),
                        todo("Sprache wählen (Cachebox: acht Sprachen, iCachebox nur Deutsch)"),
                        todo("Englische Maßeinheiten (Meilen, Fuß)"),
                        todo("Hilfe in der App")));
    }

    /** Eine Funktion von Cachebox für Android und ob iCachebox sie schon hat. */
    private record Feature(String text, boolean done) {
    }

    private static Feature done(String text) {
        return new Feature(text, true);
    }

    private static Feature todo(String text) {
        return new Feature(text, false);
    }

    /** Checkliste der Cachebox-Funktionen, abgehakt = in iCachebox umgesetzt; darüber „x von y umgesetzt“. */
    private static Div checklist(Feature... features) {
        Div list = new Div();
        list.addClassName("feature-checklist");
        long doneCount = Arrays.stream(features).filter(Feature::done).count();
        Span count = new Span(doneCount + " von " + features.length + " umgesetzt");
        count.addClassName("feature-count");
        list.add(count);
        for (Feature feature : features) {
            Checkbox checkbox = new Checkbox(feature.text());
            checkbox.setValue(feature.done());
            checkbox.setReadOnly(true);
            list.add(checkbox);
        }
        return list;
    }

    private static RouterLink manual() {
        return new RouterLink("Zur Anleitung", ManualView.class);
    }
}
