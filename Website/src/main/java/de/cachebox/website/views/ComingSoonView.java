package de.cachebox.website.views;

import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.button.ButtonVariant;
import com.vaadin.flow.component.checkbox.Checkbox;
import com.vaadin.flow.component.combobox.ComboBox;
import com.vaadin.flow.component.html.Div;
import com.vaadin.flow.component.html.H1;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.html.Span;
import com.vaadin.flow.component.textfield.TextField;
import com.vaadin.flow.data.value.ValueChangeMode;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import com.vaadin.flow.server.auth.AnonymousAllowed;
import de.cachebox.website.MainLayout;
import de.cachebox.website.features.FeatureCatalog;
import de.cachebox.website.features.FeatureCatalog.Feature;
import de.cachebox.website.features.FeatureVoteStore;
import de.cachebox.website.features.VotingIdentity;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import org.slf4j.LoggerFactory;

@AnonymousAllowed
@Route(value = "coming-soon", layout = MainLayout.class)
@PageTitle("Coming Soon! – iCachebox")
public class ComingSoonView extends Div {
    private final FeatureVoteStore store;
    private final String voter;
    private final Set<String> selected = new LinkedHashSet<>();
    private final Map<String, Checkbox> checkboxes = new HashMap<>();
    private final Div ranking = new Div();
    private final Span count = new Span();
    private final Paragraph status = new Paragraph();
    private final Paragraph selection = new Paragraph();
    private final TextField search = new TextField("Funktion suchen");
    private final ComboBox<String> category = new ComboBox<>("Themenkarte");
    private final Button save = new Button("Auswahl speichern", event -> save());
    private Map<String, Long> totals = Map.of();
    private boolean available;

    public ComingSoonView(FeatureVoteStore store) {
        this.store = store;
        voter = VotingIdentity.current();
        addClassNames("page", "roadmap");
        Paragraph intro = new Paragraph("Was soll iCachebox als Nächstes können? Wähle bis zu drei offene Funktionen. "
                + "Jede Auswahl zählt eine Stimme. Die beliebtesten Wünsche stehen oben; bei Gleichstand teilen sie sich den Rang. "
                + "Das Ranking hilft bei der Planung und ist keine Terminzusage.");
        intro.addClassName("page-lead");
        save.addThemeVariants(ButtonVariant.PRIMARY);
        status.getElement().setAttribute("role", "status");
        status.getElement().setAttribute("aria-live", "polite");
        selection.addClassName("roadmap-selection");
        Div actions = new Div(count, save, new Button("Ranking aktualisieren", event -> refresh()));
        actions.addClassName("roadmap-actions");
        Div ballot = new Div(actions, selection, status);
        ballot.addClassName("roadmap-ballot");
        search.setClearButtonVisible(true);
        search.setValueChangeMode(ValueChangeMode.EAGER);
        search.addValueChangeListener(event -> renderRanking());
        category.setItems(FeatureCatalog.SECTIONS.stream()
                .filter(section -> section.features().stream().anyMatch(feature -> !feature.done()))
                .map(FeatureCatalog.Section::title).toList());
        category.setClearButtonVisible(true);
        category.setPlaceholder("Alle Themen");
        category.addValueChangeListener(event -> renderRanking());
        Div filters = new Div(search, category);
        filters.addClassName("roadmap-filters");
        ranking.addClassName("roadmap-ranking");
        add(new H1("Coming Soon!"), intro, ballot, filters, ranking,
                new Paragraph("Du kannst deine Auswahl jederzeit ändern oder mit leerer Auswahl zurückziehen. "
                        + "Sie wird diesem Browser über ein Cookie für ein Jahr zugeordnet. Gespeichert werden eine zufällige "
                        + "Kennung und die ausgewählten Funktionen, keine IP-Adresse. Ohne Anmeldung gilt die Begrenzung je Browser, "
                        + "nicht je Person. Erledigte Funktionen verschwinden automatisch aus der Abstimmung."));
        try {
            selected.addAll(store.choices(voter));
            totals = store.totals();
            available = true;
            status.setText(selected.isEmpty() ? "Wähle deine Favoriten und speichere die Auswahl."
                    : "Deine gespeicherte Auswahl ist markiert.");
        } catch (SQLException ex) {
            failure(ex);
        }
        renderRanking();
    }

    private void save() {
        try {
            store.save(voter, selected);
            totals = store.totals();
            available = true;
            renderRanking();
            status.setText(selected.isEmpty() ? "Deine Stimmen wurden zurückgezogen."
                    : "Gespeichert. Deine Auswahl ist im Ranking berücksichtigt.");
        } catch (SQLException ex) {
            failure(ex);
            updateBallot();
        }
    }

    private void refresh() {
        try {
            // Bei einem anfänglichen Lesefehler erst den gespeicherten Stimmzettel wiederherstellen.
            if (!available) {
                selected.clear();
                selected.addAll(store.choices(voter));
            }
            totals = store.totals();
            available = true;
            status.setText("Ranking aktualisiert. Änderungen an deiner Auswahl bitte speichern.");
        } catch (SQLException ex) {
            failure(ex);
        }
        renderRanking();
    }

    private void renderRanking() {
        ranking.removeAll();
        checkboxes.clear();
        List<RankedFeature> features = new ArrayList<>();
        for (var section : FeatureCatalog.SECTIONS) {
            for (var feature : section.features()) {
                if (!feature.done()) features.add(new RankedFeature(section.title(), feature,
                        totals.getOrDefault(feature.id(), 0L)));
            }
        }
        // Stabile Katalogreihenfolge bei gleicher Stimmenzahl.
        features.sort(Comparator.comparingLong(RankedFeature::votes).reversed());
        String query = search.getValue().strip().toLowerCase(Locale.GERMAN);
        int rank = 0;
        long previousVotes = -1;
        for (int index = 0; index < features.size(); index++) {
            var item = features.get(index);
            if (item.votes() != previousVotes) rank = index + 1;
            previousVotes = item.votes();
            if (category.getValue() != null && !category.getValue().equals(item.category())) continue;
            if (!(item.feature().text() + " " + item.category()).toLowerCase(Locale.GERMAN).contains(query)) continue;
            Checkbox checkbox = new Checkbox(item.feature().text());
            checkbox.setValue(selected.contains(item.feature().id()));
            checkbox.addValueChangeListener(event -> {
                if (!event.isFromClient()) return;
                String id = item.feature().id();
                if (event.getValue()) {
                    if (selected.size() >= FeatureVoteStore.MAX_CHOICES) {
                        checkbox.setValue(false);
                        status.setText("Du hast schon drei Funktionen ausgewählt. Wähle zuerst eine davon ab.");
                        return;
                    }
                    selected.add(id);
                } else {
                    selected.remove(id);
                }
                status.setText("Auswahl geändert – bitte speichern.");
                updateBallot();
            });
            checkboxes.put(item.feature().id(), checkbox);
            Span position = new Span(item.votes() == 0 ? "–" : "#" + rank);
            position.addClassName("roadmap-position");
            Span topic = new Span(item.category());
            topic.addClassName("roadmap-topic");
            Span votes = new Span(item.votes() + (item.votes() == 1 ? " Stimme" : " Stimmen"));
            votes.addClassName("roadmap-votes");
            Div detail = new Div(topic, checkbox);
            detail.addClassName("roadmap-detail");
            Div row = new Div(position, detail, votes);
            row.addClassName("roadmap-row");
            ranking.add(row);
        }
        if (ranking.getComponentCount() == 0) ranking.add(new Paragraph("Keine offenen Funktionen für diese Suche."));
        updateBallot();
    }

    private void updateBallot() {
        count.setText(selected.size() + " von 3 ausgewählt");
        checkboxes.forEach((id, checkbox) -> checkbox.setEnabled(available
                && (selected.contains(id) || selected.size() < FeatureVoteStore.MAX_CHOICES)));
        save.setEnabled(available);
        List<String> labels = FeatureCatalog.SECTIONS.stream().flatMap(section -> section.features().stream())
                .filter(feature -> selected.contains(feature.id())).map(Feature::text).toList();
        selection.setText(labels.isEmpty() ? "Noch keine Funktion ausgewählt."
                : "Deine Auswahl: " + String.join(" · ", labels));
    }

    private void failure(SQLException ex) {
        available = false;
        status.setText("Die Abstimmung ist gerade nicht verfügbar. Bitte versuche es mit „Ranking aktualisieren“ erneut.");
        LoggerFactory.getLogger(getClass()).error("Funktionsabstimmung nicht verfügbar (SQLState {}).", ex.getSQLState());
    }

    private record RankedFeature(String category, Feature feature, long votes) { }
}
