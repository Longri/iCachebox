package de.cachebox.website.views;

import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import com.vaadin.flow.router.RouterLink;
import de.cachebox.website.MainLayout;

@Route(value = "funktionen", layout = MainLayout.class)
@PageTitle("Funktionen – iCachebox")
public class FeaturesView extends Page {

    public FeaturesView() {
        super("Was iCachebox kann",
                "iCachebox ist dein Werkzeugkasten für die Dosensuche: Alles, was du unterwegs brauchst, "
                        + "liegt auf dem Gerät – auch dort, wo es kein Netz gibt.");

        comingSoon(card("cacheListIcon.png", "Cacheliste",
                "GPX-Dateien und Pocket Queries importieren, in mehreren Listen verwalten, nach Entfernung "
                        + "sortieren, filtern und durchsuchen. Der gewählte Cache bleibt in allen Ansichten im Blick.",
                manual()));
        comingSoon(card("map.png", "Offline-Karte",
                "Mapsforge-Vektorkarten mit frei wählbarem Theme, Freizeitkarten für ganz Europa direkt in der App "
                        + "laden. Caches und Wegpunkte liegen bald direkt auf der Karte.",
                manual()));
        comingSoon(card("compass.png", "Kompass & Navigation",
                "Richtung und Entfernung zum Ziel – zum Cache, zum nächsten Wegpunkt oder zum geparkten Auto."));
        comingSoon(card("fieldnoteListIcon.png", "Loggen unterwegs",
                "Funde, DNFs und Notizen als Entwurf festhalten und später in Ruhe hochladen."));
        comingSoon(card("dayGcLiveIcon.png", "Geocaching Live",
                "Caches über die offizielle Geocaching-API laden und aktuell halten."));
        comingSoon(card("solverIcon.png", "Solver",
                "Formeln und Variablen für Multis und Mysteries rechnen, ohne Zettel und Stift."));
        comingSoon(card("trackListIcon.png", "Tracks",
                "Wege aufzeichnen, GPX-Tracks laden und auf der Karte anzeigen."));
        comingSoon(card("tb.png", "Trackables",
                "Travelbugs und Coins verwalten: entdecken, mitnehmen, ablegen."));
    }

    private static RouterLink manual() {
        return new RouterLink("Zur Anleitung", ManualView.class);
    }
}
