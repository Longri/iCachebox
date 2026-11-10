package de.cachebox.website.views;

import com.vaadin.flow.component.html.Anchor;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import de.cachebox.website.MainLayout;

@Route(value = "karten", layout = MainLayout.class)
@PageTitle("Offline-Karten – iCachebox")
public class MapsView extends Page {

    public MapsView() {
        super("Karten, die im Wald funktionieren",
                "iCachebox zeichnet Mapsforge-Vektorkarten direkt auf dem Gerät. Einmal geladen, "
                        + "brauchst du unterwegs keine Verbindung mehr.");

        card("mapsforge_logo.png", "Mapsforge",
                "Kompakte .map-Dateien, scharf in jeder Zoomstufe. Auf iOS rendert ein eigener, "
                        + "nativer Swift-Port von Mapsforge.",
                link("mapsforge.org", "https://mapsforge.org"));
        card("osm_logo.png", "OpenStreetMap",
                "Die Kartendaten stammen von OpenStreetMap – frei, weltweit und oft genauer als jede Wanderkarte.",
                link("openstreetmap.org", "https://www.openstreetmap.org"));
        card("navigate.png", "Themes & Stile",
                "Render-Themes wie Elevate bringen eigene Stile mit: Wandern, Stadt, Rad oder MTB. "
                        + "Einzelne Ebenen schaltest du im Stilmenü an und aus.",
                link("OpenAndroMaps", "https://www.openandromaps.org"));
        card("satellite.png", "Deine Karten",
                "Karten und Themes lädst du selbst und wählst sie in der App aus – "
                        + "dieselben Dateien wie in Cachebox für Android.");
    }

    private static Anchor link(String text, String url) {
        Anchor anchor = new Anchor(url, text);
        anchor.setTarget("_blank");
        return anchor;
    }
}
