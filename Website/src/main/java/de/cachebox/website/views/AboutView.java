package de.cachebox.website.views;

import com.vaadin.flow.server.auth.AnonymousAllowed;
import com.vaadin.flow.component.html.Anchor;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import de.cachebox.website.MainLayout;

@AnonymousAllowed
@Route(value = "projekt", layout = MainLayout.class)
@PageTitle("Projekt – iCachebox")
public class AboutView extends Page {

    public AboutView() {
        super("Von Cachern für Cacher",
                "iCachebox bringt Cachebox aufs iPhone – als nativer Neubau in Swift und wie das Original "
                        + "als Open-Source-Projekt. Die Android-App gibt es seit Jahren.");

        card("cb-ios.png", "iCachebox für iOS",
                "In Entwicklung: Als Prototyp laufen die Kartenanzeige mit Mapsforge-Karten und Themes, der "
                        + "Kartendownload, der GPX-Import mit mehreren Listen, die Cacheliste und die Cache-Details. "
                        + "Log-Entwürfe sind im Aufbau. Noch nicht im App Store.",
                link("iCachebox auf GitHub", MainLayout.GITHUB_URL));
        card("cb.png", "Cachebox für Android",
                "Das Original auf Basis von libGDX, erhältlich im Play Store.",
                link("Zum Play Store", MainLayout.PLAYSTORE_URL),
                link("Quellcode auf GitHub", MainLayout.ANDROID_GITHUB_URL));
        card("bigMystery.png", "Mitmachen",
                "Fehler melden, Ideen einbringen oder mitentwickeln – der Quellcode liegt offen.",
                link("iCachebox auf GitHub", MainLayout.GITHUB_URL));
    }

    private static Anchor link(String text, String url) {
        Anchor anchor = new Anchor(url, text);
        anchor.setTarget("_blank");
        return anchor;
    }
}
