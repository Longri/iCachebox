package de.cachebox.website.views;

import com.vaadin.flow.component.html.Div;
import com.vaadin.flow.component.html.H1;
import com.vaadin.flow.component.html.Image;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import com.vaadin.flow.router.RouterLink;
import de.cachebox.website.MainLayout;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.boot.info.BuildProperties;

/** Startseite: das Logo „Cachebox – too many secrets." vor den Bäumen, wie der Splash-Screen der App. */
@Route(value = "", layout = MainLayout.class)
@PageTitle("iCachebox – Cachebox für iOS")
public class StartView extends Div {

    private static final DateTimeFormatter UPDATED_FORMAT =
            DateTimeFormatter.ofPattern("dd.MM.yyyy, HH:mm 'Uhr'").withZone(ZoneId.of("Europe/Berlin"));

    /**
     * @param buildProperties aus META-INF/build-info.properties (Maven-Goal {@code build-info});
     *                        fehlt beim Start aus der IDE ohne Maven, dann entfällt die Zeile „Stand“
     */
    public StartView(ObjectProvider<BuildProperties> buildProperties) {
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

        // Zeitpunkt des Builds = letzter Upload, denn deploy.sh baut direkt vor dem Hochladen
        BuildProperties build = buildProperties.getIfAvailable();
        if (build != null && build.getTime() != null) {
            Paragraph updated = new Paragraph("Stand: " + UPDATED_FORMAT.format(build.getTime()));
            updated.addClassName("start-updated");
            add(updated);
        }
    }

    private Image cacheType(String file, String alt) {
        return new Image("images/" + file, alt);
    }
}
