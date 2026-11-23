package de.cachebox.website.views;

import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.combobox.ComboBox;
import com.vaadin.flow.component.grid.Grid;
import com.vaadin.flow.component.grid.dnd.GridDropLocation;
import com.vaadin.flow.component.grid.dnd.GridDropMode;
import com.vaadin.flow.component.html.Div;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.html.Span;
import com.vaadin.flow.component.textfield.TextField;
import com.vaadin.flow.data.value.ValueChangeMode;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import com.vaadin.flow.router.RouterLink;
import com.vaadin.flow.spring.security.AuthenticationContext;
import de.cachebox.website.MainLayout;
import de.cachebox.website.tickets.*;
import de.cachebox.website.tickets.TicketModels.*;
import jakarta.annotation.security.RolesAllowed;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.CompletableFuture;

@RolesAllowed({"USER", "ADMIN"})
@Route(value = "tickets", layout = MainLayout.class)
@PageTitle("Tickets | iCachebox")
public class TicketsView extends Page {
    private final TicketStore store;
    private final Actor actor;
    private final Grid<Ticket> grid = new Grid<>();
    private final TextField search = new TextField("Tickets durchsuchen");
    private final ComboBox<Kind> kind = new ComboBox<>("Typ");
    private final ComboBox<Status> status = new ComboBox<>("Status");
    private final Span feedback = new Span();
    private Ticket dragged;

    public TicketsView(TicketStore store, GithubTicketSync sync, AuthenticationContext authentication) {
        super(Actor.current().admin() ? "Tickets – deine Arbeitsliste" : "Meine Tickets",
                Actor.current().admin() ? "Fehler, Wünsche und Rückfragen an einem Ort. Ziehe Tickets nach oben oder unten, um deine Abarbeitung festzulegen."
                        : "Melde Fehler, schlage Funktionen vor und ergänze Informationen zu deinen Tickets.");
        this.store = store; this.actor = Actor.current();
        addClassName("tickets");
        RouterLink create = new RouterLink("Neues Ticket", TicketCreateView.class); create.addClassNames("button", "button-primary");
        Div actions = new Div(create, new Span("Angemeldet als " + actor.username()), new Button("Abmelden", e -> authentication.logout()));
        actions.addClassName("ticket-controls");
        search.setValueChangeMode(ValueChangeMode.LAZY); search.setClearButtonVisible(true); search.addValueChangeListener(e -> refresh());
        kind.setItems(Kind.values()); kind.setClearButtonVisible(true); kind.addValueChangeListener(e -> refresh());
        status.setItems(Status.values()); status.setClearButtonVisible(true); status.addValueChangeListener(e -> refresh());
        Div filters = new Div(search, kind, status, new Button("Aktualisieren", e -> refresh())); filters.addClassName("ticket-controls");
        grid.addComponentColumn(ticket -> new RouterLink("#" + ticket.id() + " · " + ticket.title(), TicketDetailView.class, ticket.id()))
                .setHeader("Ticket").setFlexGrow(3).setAutoWidth(true);
        grid.addColumn(Ticket::kind).setHeader("Typ").setAutoWidth(true).setFlexGrow(0);
        grid.addColumn(Ticket::status).setHeader("Status").setAutoWidth(true).setFlexGrow(0);
        if (actor.admin()) {
            grid.addColumn(t -> t.owner().isEmpty() ? "GitHub" : t.owner()).setHeader("Von").setAutoWidth(true);
            grid.addComponentColumn(t -> new Div(new Button("↑", e -> step(t, -1)), new Button("↓", e -> step(t, 1))))
                    .setHeader("Reihenfolge").setWidth("130px").setFlexGrow(0);
            grid.setRowsDraggable(true); grid.setDropMode(GridDropMode.BETWEEN);
            grid.addDragStartListener(e -> dragged = e.getDraggedItems().getFirst());
            grid.addDragEndListener(e -> dragged = null);
            grid.addDropListener(e -> e.getDropTargetItem().ifPresent(target -> {
                if (dragged != null) act(() -> store.move(actor, dragged.id(), target.id(), e.getDropLocation() == GridDropLocation.ABOVE));
            }));
            grid.addColumn(t -> t.conflict() ? "GitHub-Konflikt prüfen" : t.githubNumber() > 0 ? "GitHub #" + t.githubNumber() : t.shareGithub() ? "Zum Abgleich freigegeben" : "Nur Website")
                    .setHeader("GitHub").setAutoWidth(true);
        }
        grid.setWidthFull(); grid.setHeight("560px");
        feedback.getElement().setAttribute("role", "status");
        add(actions, filters, grid, feedback);
        if (actor.admin()) {
            Span syncStatus = new Span(sync.summary(actor));
            Button synchronize = new Button("GitHub jetzt abgleichen");
            synchronize.setEnabled(sync.configured());
            synchronize.addClickListener(e -> {
                synchronize.setEnabled(false);
                var ui = getUI().orElseThrow();
                ui.setPollInterval(1000);
                CompletableFuture.runAsync(() -> {
                    String result;
                    try { sync.synchronize(actor); result = sync.summary(actor); }
                    catch (TicketException ex) { result = ex.getMessage(); }
                    catch (RuntimeException ex) { result = "Der Abgleich konnte nicht abgeschlossen werden. Bitte erneut versuchen."; }
                    String text = result;
                    ui.access(() -> { syncStatus.setText(text); synchronize.setEnabled(sync.configured()); ui.setPollInterval(-1); refresh(); });
                });
            });
            add(new Div(new Paragraph("Interne Notizen und diese Reihenfolge werden niemals an GitHub übertragen."), synchronize, syncStatus));
        }
        refresh();
    }

    private void refresh() {
        try {
            String query = search.getValue().strip().toLowerCase(Locale.ROOT);
            List<Ticket> items = store.list(actor).stream().filter(t -> kind.getValue() == null || t.kind() == kind.getValue())
                    .filter(t -> status.getValue() == null || t.status() == status.getValue())
                    .filter(t -> (t.title() + " " + t.body() + " " + t.id()).toLowerCase(Locale.ROOT).contains(query)).toList();
            grid.setItems(items);
            feedback.setText(items.size() + " Ticket(s)" + (actor.admin() ? " · Reihenfolge wird sofort gespeichert." : ""));
        } catch (TicketException ex) { feedback.setText(ex.getMessage()); }
    }

    private void step(Ticket ticket, int direction) {
        List<Ticket> all = store.list(actor);
        int index = java.util.stream.IntStream.range(0, all.size()).filter(i -> all.get(i).id() == ticket.id()).findFirst().orElse(-1);
        int target = index + direction;
        if (index >= 0 && target >= 0 && target < all.size()) act(() -> store.move(actor, ticket.id(), all.get(target).id(), direction < 0));
    }
    private void act(Runnable work) { try { work.run(); refresh(); } catch (TicketException ex) { feedback.setText(ex.getMessage()); } }
}
