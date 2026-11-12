package de.cachebox.website.views;

import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.checkbox.Checkbox;
import com.vaadin.flow.component.combobox.ComboBox;
import com.vaadin.flow.component.grid.Grid;
import com.vaadin.flow.component.html.Div;
import com.vaadin.flow.component.html.H1;
import com.vaadin.flow.component.html.H2;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.html.Span;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import com.vaadin.flow.spring.security.AuthenticationContext;
import de.cachebox.website.MainLayout;
import de.cachebox.website.analytics.AnalyticsStore;
import de.cachebox.website.analytics.AnalyticsStore.Count;
import de.cachebox.website.analytics.CountryLookup;
import jakarta.annotation.security.RolesAllowed;
import java.sql.SQLException;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Locale;

@Route(value = "admin", layout = MainLayout.class)
@PageTitle("Website-Statistik | iCachebox")
@RolesAllowed("ADMIN")
public class AdminView extends Div {
    private final AnalyticsStore store;
    private final Div results = new Div();
    private final ComboBox<Integer> period = new ComboBox<>("Zeitraum");
    private final Checkbox bots = new Checkbox("Erkannte Bots einschließen");

    public AdminView(AnalyticsStore store, CountryLookup countries, AuthenticationContext auth) {
        this.store = store;
        addClassNames("page", "analytics");
        period.setItems(7, 30, 90, 365);
        period.setItemLabelGenerator(days -> "Letzte " + days + " Tage");
        period.setValue(30);
        period.setAllowCustomValue(false);
        period.setRequired(true);
        period.addValueChangeListener(e -> refresh());
        bots.addValueChangeListener(e -> refresh());
        Div controls = new Div(period, bots, new Button("Aktualisieren", e -> refresh()),
                new Button("Abmelden", e -> auth.logout()));
        controls.addClassName("analytics-controls");
        add(new H1("Website-Statistik"), new Paragraph("Aufrufe und Besuche der öffentlichen Seiten · Zeitzone Europa/Berlin"), controls);
        if (!countries.available()) add(new Paragraph("Ländererkennung noch nicht eingerichtet: GEOIP_DATABASE in der .env auf eine lokale GeoLite2-Country.mmdb setzen. Bis dahin: Unbekannt."));
        add(results, new Paragraph("Ein Aufruf zählt eine angezeigte öffentliche Seite, einschließlich Navigation und Neuladen. "
                + "Ein Besuch beginnt beim ersten öffentlichen Aufruf einer Sitzung (30 Minuten Inaktivität). Besuche sind keine eindeutigen Personen. "
                + "Anmeldung, Statistikbereich, Bilder und interne Vaadin-Anfragen werden nicht gezählt. "
                + "Bot- und Geräteerkennung sind Schätzungen anhand des Browsertyps; Bots ohne JavaScript werden meist nicht erfasst. "
                + "Herkunft zeigt nur die verweisende Domain, sofern der Browser sie übermittelt. "
                + "Länder sind ungefähre IP-Zuordnungen. Es werden nur Tagesaggregate für 400 Tage gespeichert, keine IP-Adressen oder zusätzlichen Tracking-Cookies."));
        refresh();
    }

    private void refresh() {
        results.removeAll();
        LocalDate today = LocalDate.now(AnalyticsStore.ZONE);
        int days = period.getValue() == null ? 30 : period.getValue();
        LocalDate from = today.minusDays(days - 1L);
        try {
            List<Count> daily = store.counts("visit_day", from, today, bots.getValue());
            long views = daily.stream().mapToLong(Count::views).sum();
            long visits = daily.stream().mapToLong(Count::visits).sum();
            long todayViews = daily.stream().filter(c -> c.label().equals(today.toString())).mapToLong(Count::views).sum();
            Div metrics = new Div(metric("Aufrufe im Zeitraum", views), metric("Besuche im Zeitraum", visits), metric("Aufrufe heute", todayViews));
            metrics.addClassName("analytics-metrics");
            results.add(metrics);
            if (views == 0) results.add(new Paragraph("Noch keine Aufrufe in diesem Zeitraum. Die Erfassung beginnt mit Inbetriebnahme dieser Version."));
            results.add(table("Aufrufe pro Tag", daily, "Tag", "visit_day"));
            Div breakdowns = new Div();
            breakdowns.addClassName("analytics-breakdowns");
            for (String dimension : List.of("page", "country", "referrer", "device")) {
                String title = switch (dimension) {
                    case "page" -> "Beliebte Seiten";
                    case "country" -> "Länder";
                    case "referrer" -> "Herkunftswebsites (Top 100)";
                    default -> "Geräte";
                };
                breakdowns.add(table(title, store.counts(dimension, from, today, bots.getValue()), title, dimension));
            }
            results.add(breakdowns);
        } catch (SQLException ex) {
            results.removeAll();
            results.add(new Paragraph("Statistik derzeit nicht verfügbar. Bitte Serverprotokoll prüfen."));
            org.slf4j.LoggerFactory.getLogger(getClass()).error("Statistik nicht lesbar (SQLState {}).", ex.getSQLState());
        }
    }

    private Div metric(String label, long count) {
        Div card = new Div(new Span(label), new H2(String.format(Locale.GERMANY, "%,d", count)));
        card.addClassName("analytics-metric");
        return card;
    }

    private Div table(String title, List<Count> rows, String label, String dimension) {
        Grid<Count> grid = new Grid<>();
        grid.addColumn(row -> switch (dimension) {
            case "country" -> "ZZ".equals(row.label()) ? "Unbekannt" : new Locale.Builder().setRegion(row.label()).build().getDisplayCountry(Locale.GERMAN);
            case "visit_day" -> LocalDate.parse(row.label()).format(DateTimeFormatter.ofPattern("dd.MM.yyyy"));
            default -> row.label();
        }).setHeader(label).setFlexGrow(1);
        grid.addColumn(Count::views).setHeader("Aufrufe").setWidth("110px").setFlexGrow(0);
        grid.addColumn(Count::visits).setHeader("Besuchsstarts").setWidth("140px").setFlexGrow(0);
        grid.setItems(rows);
        grid.setHeight("320px");
        grid.setWidthFull();
        return new Div(new H2(title), grid);
    }
}
