package de.cachebox.website.views;

import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.checkbox.Checkbox;
import com.vaadin.flow.component.combobox.ComboBox;
import com.vaadin.flow.component.html.Div;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.html.Span;
import com.vaadin.flow.component.textfield.TextArea;
import com.vaadin.flow.component.textfield.TextField;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import com.vaadin.flow.router.RouterLink;
import de.cachebox.website.MainLayout;
import de.cachebox.website.tickets.*;
import de.cachebox.website.tickets.TicketModels.*;
import jakarta.annotation.security.RolesAllowed;

@RolesAllowed({"USER", "ADMIN"})
@Route(value = "tickets/neu", layout = MainLayout.class)
@PageTitle("Neues Ticket | iCachebox")
public class TicketCreateView extends Page {
    public TicketCreateView(TicketStore store) {
        super("Neues Ticket", "Was funktioniert nicht – oder welche Funktion wünschst du dir?");
        addClassName("tickets");
        ComboBox<Kind> kind = new ComboBox<>("Typ"); kind.setItems(Kind.values()); kind.setValue(Kind.BUG); kind.setRequired(true);
        TextField title = new TextField("Titel"); title.setRequired(true); title.setMaxLength(200);
        TextArea body = new TextArea("Beschreibung"); body.setRequired(true); body.setMinHeight("220px"); body.setMaxLength(20000);
        body.setHelperText("Was hast du erwartet? Was ist passiert? Bei Fehlern helfen Schritte zum Nachstellen sowie Gerät und App-Version.");
        Checkbox share = new Checkbox("Titel, Beschreibung, Benutzername und alle späteren öffentlichen Antworten dürfen im öffentlichen GitHub-Repository Longri/iCachebox erscheinen.");
        Span feedback = new Span(); feedback.getElement().setAttribute("role", "status");
        Button create = new Button("Ticket erstellen", e -> {
            try {
                Ticket ticket = store.create(Actor.current(), title.getValue(), body.getValue(), kind.getValue(), share.getValue());
                getUI().ifPresent(ui -> ui.navigate(TicketDetailView.class, ticket.id()));
            } catch (TicketException ex) { feedback.setText(ex.getMessage()); }
        });
        Div form = new Div(kind, title, body, share,
                new Paragraph("Screenshots kannst du nach dem Erstellen hinzufügen. Sie bleiben auf dieser Website geschützt, auch bei GitHub-Veröffentlichung."),
                create, feedback, new RouterLink("Zurück zu meinen Tickets", TicketsView.class));
        form.addClassNames("card", "ticket-form"); add(form);
    }
}
