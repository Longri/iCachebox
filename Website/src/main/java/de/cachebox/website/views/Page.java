package de.cachebox.website.views;

import com.vaadin.flow.component.Component;
import com.vaadin.flow.component.html.Div;
import com.vaadin.flow.component.html.H1;
import com.vaadin.flow.component.html.H2;
import com.vaadin.flow.component.html.Image;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.html.Span;

/** Basis der Inhaltsseiten: Titel, Einleitung und Karten mit Icon aus der App. */
abstract class Page extends Div {

    private final Div cards = new Div();

    protected Page(String title, String intro) {
        addClassName("page");
        Paragraph lead = new Paragraph(intro);
        lead.addClassName("page-lead");
        cards.addClassName("cards");
        add(new H1(title), lead, cards);
    }

    /** Karte mit Icon (Datei aus META-INF/resources/images), Überschrift und Text. */
    protected Div card(String iconFile, String title, String text, Component... more) {
        Image icon = new Image("images/" + iconFile, "");
        icon.addClassName("card-icon");
        Div card = new Div(icon, new H2(title), new Paragraph(text));
        card.add(more);
        card.addClassName("card");
        cards.add(card);
        return card;
    }

    /** Legt den roten Streifen „Coming Soon!" über eine Karte. Zum Entfernen den Aufruf um card(...) weglassen. */
    protected Div comingSoon(Div card) {
        Span ribbon = new Span("Coming Soon!");
        ribbon.addClassName("ribbon");
        card.addClassName("card-soon");
        card.add(ribbon);
        return card;
    }
}
