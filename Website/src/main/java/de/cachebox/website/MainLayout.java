package de.cachebox.website;

import com.vaadin.flow.server.auth.AnonymousAllowed;
import com.vaadin.flow.component.Component;
import com.vaadin.flow.component.HasElement;
import com.vaadin.flow.component.dependency.StyleSheet;
import com.vaadin.flow.component.html.Anchor;
import com.vaadin.flow.component.html.Div;
import com.vaadin.flow.component.html.Footer;
import com.vaadin.flow.component.html.Header;
import com.vaadin.flow.component.html.Image;
import com.vaadin.flow.component.html.Main;
import com.vaadin.flow.component.html.Nav;
import com.vaadin.flow.component.html.Span;
import com.vaadin.flow.router.HighlightConditions;
import com.vaadin.flow.router.RouterLayout;
import com.vaadin.flow.router.RouterLink;
import de.cachebox.website.views.AboutView;
import de.cachebox.website.views.FeaturesView;
import de.cachebox.website.views.ManualView;
import de.cachebox.website.views.MapsView;
import de.cachebox.website.views.StartView;

/**
 * Rahmen aller Seiten: Kopfzeile mit Navigation, Inhalt, Fußzeile.
 * Das Bäume-Hintergrundbild kommt aus styles/site.css und liegt hinter allen Seiten.
 * <p>
 * Neue Seite hinzufügen: View-Klasse mit {@code @Route(value = "...", layout = MainLayout.class)}
 * anlegen und hier in {@link #createNav()} verlinken.
 */
@AnonymousAllowed
@StyleSheet("context://styles/site.css")
public class MainLayout extends Div implements RouterLayout {

    /** Quellcode von iCachebox (iOS) – um den geht es auf dieser Website. */
    public static final String GITHUB_URL = "https://github.com/Longri/iCachebox";
    /** Quellcode der Android-Version. */
    public static final String ANDROID_GITHUB_URL = "https://github.com/Ging-Buh/cachebox";
    public static final String PLAYSTORE_URL = "https://play.google.com/store/apps/details?id=de.droidcachebox";

    private final Main content = new Main();

    public MainLayout() {
        addClassName("site");
        content.addClassName("site-content");
        add(createHeader(), content, createFooter());
    }

    @Override
    public void showRouterLayoutContent(HasElement view) {
        content.getElement().removeAllChildren();
        if (view != null) {
            content.getElement().appendChild(view.getElement());
        }
    }

    private Component createHeader() {
        Image icon = new Image("images/cb-ios.png", "");
        RouterLink home = new RouterLink(StartView.class);
        home.addClassName("site-brand");
        home.add(icon, new Span("iCachebox"));
        home.getElement().setAttribute("aria-label", "iCachebox Startseite");

        Header header = new Header(home, createNav());
        header.addClassName("site-header");
        return header;
    }

    private Component createNav() {
        Nav nav = new Nav(
                navLink("Start", StartView.class),
                navLink("Funktionen", FeaturesView.class),
                navLink("Offline-Karten", MapsView.class),
                navLink("Anleitung", ManualView.class),
                navLink("Projekt", AboutView.class));
        nav.addClassName("site-nav");
        return nav;
    }

    private RouterLink navLink(String text, Class<? extends Component> target) {
        RouterLink link = new RouterLink(text, target);
        link.setHighlightCondition(HighlightConditions.sameLocation());
        return link;
    }

    private Component createFooter() {
        Anchor github = new Anchor(GITHUB_URL, "iCachebox auf GitHub");
        github.setTarget("_blank");
        Anchor android = new Anchor(ANDROID_GITHUB_URL, "Cachebox für Android");
        android.setTarget("_blank");
        Footer footer = new Footer(
                new Span("Cachebox – too many secrets."),
                github,
                android,
                new Span("Kartendaten © OpenStreetMap-Mitwirkende"));
        footer.addClassName("site-footer");
        return footer;
    }
}
