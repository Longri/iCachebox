package de.cachebox.website.views;

import com.vaadin.flow.component.html.Div;
import com.vaadin.flow.component.html.H1;
import com.vaadin.flow.component.html.Image;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import com.vaadin.flow.router.RouterLink;
import de.cachebox.website.MainLayout;

/** Startseite: das Logo „Cachebox – too many secrets." vor den Bäumen, wie der Splash-Screen der App. */
@Route(value = "", layout = MainLayout.class)
@PageTitle("iCachebox – Cachebox für iOS")
public class StartView extends Div {

    public StartView() {
        addClassName("start");

        Image logo = new Image("images/cachebox-logo.png", "Cachebox – too many secrets.");
        logo.addClassName("start-logo");
        // Das Logo ist die Überschrift der Seite
        H1 heading = new H1(logo);

        Paragraph claim = new Paragraph("Geocaching ohne Netz. Mit deinen Caches, deinen Karten – iCachebox bringt Cachebox aufs iPhone.");
        claim.addClassName("start-claim");

        RouterLink features = new RouterLink("Was iCachebox kann", FeaturesView.class);
        features.addClassNames("button", "button-primary");
        RouterLink maps = new RouterLink("Offline-Karten", MapsView.class);
        maps.addClassName("button");
        RouterLink manual = new RouterLink("Anleitung", ManualView.class);
        manual.addClassName("button");
        Div actions = new Div(features, maps, manual);
        actions.addClassName("start-actions");

        Div types = new Div(
                cacheType("bigTraditional.png", "Traditional"),
                cacheType("bigMulti.png", "Multi"),
                cacheType("bigMystery.png", "Mystery"),
                cacheType("bigEarth.png", "Earthcache"));
        types.addClassName("start-types");

        add(heading, claim, actions, types);
    }

    private Image cacheType(String file, String alt) {
        return new Image("images/" + file, alt);
    }
}
