package de.cachebox.website.views;

import com.vaadin.flow.component.html.Div;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.markdown.Markdown;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import de.cachebox.website.MainLayout;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

/**
 * Die Anleitung der App. Quelle ist {@code docs/anleitung/README.md} im Repository (auch auf GitHub lesbar);
 * der Maven-Build kopiert sie samt Bildern in den Classpath (siehe pom.xml, Ausführung "anleitung").
 */
@Route(value = "anleitung", layout = MainLayout.class)
@PageTitle("Anleitung – iCachebox")
public class ManualView extends Div {

    static final String SOURCE = "/anleitung/README.md";

    public ManualView() {
        addClassNames("page", "manual");
        String text = load();
        if (text == null) {
            add(new Paragraph("Die Anleitung konnte nicht geladen werden."));
            return;
        }
        // Bilder liegen neben der Markdown-Datei ("bilder/…"); die Website liefert sie unter /anleitung/bilder aus
        Markdown markdown = new Markdown(text.replace("](bilder/", "](anleitung/bilder/"));
        markdown.addClassName("manual-text");
        add(markdown);
    }

    private static String load() {
        try (InputStream in = ManualView.class.getResourceAsStream(SOURCE)) {
            return in == null ? null : new String(in.readAllBytes(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            return null;
        }
    }
}
