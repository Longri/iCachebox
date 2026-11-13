package de.cachebox.website.views;

import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.button.ButtonVariant;
import com.vaadin.flow.component.checkbox.Checkbox;
import com.vaadin.flow.component.details.Details;
import com.vaadin.flow.component.html.H2;
import com.vaadin.flow.component.html.UnorderedList;
import com.vaadin.flow.component.html.ListItem;
import com.vaadin.flow.router.RouterLink;
import com.vaadin.flow.component.html.Div;
import com.vaadin.flow.component.html.H1;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.html.Span;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import com.vaadin.flow.server.auth.AnonymousAllowed;
import de.cachebox.website.MainLayout;
import de.cachebox.website.features.FeatureCatalog;
import de.cachebox.website.features.WishCatalog;
import de.cachebox.website.features.WishCatalog.Wish;
import de.cachebox.website.features.FeatureVoteStore;
import de.cachebox.website.features.VotingIdentity;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
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
    private final Div archive = new Div();
    private final Button save = new Button("Auswahl speichern", event -> save());
    private Map<String, Long> totals = Map.of();
    private boolean available;

    public ComingSoonView(FeatureVoteStore store) {
        this.store = store;
        voter = VotingIdentity.current();
        addClassNames("page", "roadmap");
        Paragraph intro = new Paragraph("Was würde deine nächste Cachetour besser machen? Wähle bis zu drei Wünsche. "
                + "Jeder Wunsch erhält eine gleichwertige Stimme. Details kannst du bei Bedarf aufklappen. "
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
        ranking.addClassName("roadmap-ranking");
        Div essentials = new Div(new H2("Für den Start fest eingeplant"),
                new Paragraph("Caches direkt von geocaching.com laden und Funde, DNFs oder Notizen festhalten: "
                        + "Diese Grundlagen sind vor der Veröffentlichung geplant und brauchen keine Stimmen. "
                        + "Sie sind noch nicht umgesetzt."));
        essentials.addClassName("roadmap-essentials");
        Div round = new Div(new H2("Neue Runde: Was ist dir am wichtigsten?"),
                new Paragraph("Wir stimmen jetzt über übersichtliche Funktionspakete ab. Frühere Stimmen für "
                        + "Einzelfunktionen bleiben separat erhalten und werden nicht auf Pakete übertragen."));
        add(new H1("Coming Soon!"), intro, essentials, round, ballot, ranking,
                new Details("Alle offenen Funktionen im Detail", technicalOverview()), archive,
                new Paragraph("Du kannst deine Auswahl jederzeit ändern oder mit leerer Auswahl zurückziehen. "
                        + "Sie wird diesem Browser über ein Cookie für ein Jahr zugeordnet. Gespeichert werden eine zufällige "
                        + "Kennung und die ausgewählten Wünsche, keine IP-Adresse. Ohne Anmeldung gilt die Begrenzung je Browser, "
                        + "nicht je Person. Vollständig umgesetzte Pakete verschwinden aus der Abstimmung."));
        try {
            selected.addAll(store.wishChoices(voter));
            totals = store.wishTotals();
            renderArchive();
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
            store.saveWishes(voter, selected);
            totals = store.wishTotals();
            renderArchive();
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
                selected.addAll(store.wishChoices(voter));
            }
            totals = store.wishTotals();
            renderArchive();
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
        for (Wish wish : WishCatalog.openWishes()) {
            features.add(new RankedFeature(wish, totals.getOrDefault(wish.id(), 0L)));
        }
        // Stabile Katalogreihenfolge bei gleicher Stimmenzahl.
        features.sort(Comparator.comparingLong(RankedFeature::votes).reversed());
        int rank = 0;
        long previousVotes = -1;
        for (int index = 0; index < features.size(); index++) {
            var item = features.get(index);
            if (item.votes() != previousVotes) rank = index + 1;
            previousVotes = item.votes();
            Checkbox checkbox = new Checkbox(item.wish().title());
            checkbox.setValue(selected.contains(item.wish().id()));
            checkbox.addValueChangeListener(event -> {
                if (!event.isFromClient()) return;
                String id = item.wish().id();
                if (event.getValue()) {
                    if (selected.size() >= FeatureVoteStore.MAX_CHOICES) {
                        checkbox.setValue(false);
                        status.setText("Du hast schon drei Wünsche ausgewählt. Wähle zuerst einen davon ab.");
                        return;
                    }
                    selected.add(id);
                } else {
                    selected.remove(id);
                }
                status.setText("Auswahl geändert – bitte speichern.");
                updateBallot();
            });
            checkboxes.put(item.wish().id(), checkbox);
            Span position = new Span(item.votes() == 0 ? "–" : "#" + rank);
            position.addClassName("roadmap-position");
            Span votes = new Span(item.votes() + (item.votes() == 1 ? " Stimme" : " Stimmen"));
            votes.addClassName("roadmap-votes");
            Paragraph benefit = new Paragraph(item.wish().benefit());
            UnorderedList included = new UnorderedList();
            item.wish().openFeatures().forEach(feature -> included.add(new ListItem(feature.text())));
            Div detail = new Div(checkbox, benefit, new Details("Details anzeigen", included));
            detail.addClassName("roadmap-detail");
            Div row = new Div(position, detail, votes);
            row.addClassName("roadmap-row");
            ranking.add(row);
        }
        if (ranking.getComponentCount() == 0) ranking.add(new Paragraph("Alle Wünsche sind bereits umgesetzt."));
        updateBallot();
    }

    private void updateBallot() {
        count.setText(selected.size() + " von 3 ausgewählt");
        checkboxes.forEach((id, checkbox) -> checkbox.setEnabled(available
                && (selected.contains(id) || selected.size() < FeatureVoteStore.MAX_CHOICES)));
        save.setEnabled(available);
        List<String> labels = WishCatalog.openWishes().stream()
                .filter(wish -> selected.contains(wish.id())).map(Wish::title).toList();
        selection.setText(labels.isEmpty() ? "Noch keinen Wunsch ausgewählt."
                : "Deine Auswahl: " + String.join(" · ", labels));
    }

    private Div technicalOverview() {
        Div overview = new Div(new Paragraph("Hier bleibt der vollständige technische Funktionskatalog erreichbar. "
                + "Die Abstimmung oben zeigt eine Auswahl gebündelter Wünsche."),
                new RouterLink("Bereits umgesetzte Funktionen ansehen →", FeaturesView.class));
        for (var section : FeatureCatalog.SECTIONS) {
            UnorderedList list = new UnorderedList();
            section.features().stream().filter(feature -> !feature.done())
                    .forEach(feature -> list.add(new ListItem(feature.text())));
            if (list.getComponentCount() > 0) overview.add(new Details(section.title(), list));
        }
        return overview;
    }

    private void renderArchive() throws SQLException {
        Map<String, Long> oldTotals = store.totals();
        Set<String> oldChoices = store.choices(voter);
        archive.removeAll();
        Div content = new Div(new Paragraph("Abgeschlossene Runde für Einzelfunktionen. Diese Stimmen zählen "
                + "ausschließlich für die frühere Runde, nicht für die Pakete oben. Deine frühere Auswahl ist gekennzeichnet."));
        UnorderedList list = new UnorderedList();
        FeatureCatalog.SECTIONS.stream().flatMap(section -> section.features().stream())
                .filter(feature -> oldTotals.containsKey(feature.id()) || oldChoices.contains(feature.id()))
                .sorted(Comparator.comparingLong((FeatureCatalog.Feature feature) -> oldTotals.getOrDefault(feature.id(), 0L)).reversed())
                .forEach(feature -> list.add(new ListItem(feature.text() + " · " + oldTotals.getOrDefault(feature.id(), 0L)
                        + " Stimme(n)" + (oldChoices.contains(feature.id()) ? " · Deine frühere Auswahl" : ""))));
        content.add(list);
        if (list.getComponentCount() == 0) content.add(new Paragraph("Keine früheren Stimmen vorhanden."));
        if (!oldChoices.isEmpty()) {
            content.add(new Button("Frühere Stimmen zurückziehen", event -> {
                try {
                    store.save(voter, Set.of());
                    renderArchive();
                    status.setText("Deine früheren Stimmen wurden zurückgezogen. Die neue Auswahl bleibt erhalten.");
                } catch (SQLException ex) {
                    failure(ex);
                    updateBallot();
                }
            }));
        }
        archive.add(new Details("Frühere Abstimmung ansehen", content));
    }

    private void failure(SQLException ex) {
        available = false;
        status.setText("Die Abstimmung ist gerade nicht verfügbar. Bitte versuche es mit „Ranking aktualisieren“ erneut.");
        LoggerFactory.getLogger(getClass()).error("Funktionsabstimmung nicht verfügbar (SQLState {}).", ex.getSQLState());
    }

    private record RankedFeature(Wish wish, long votes) { }
}
