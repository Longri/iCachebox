package de.cachebox.website.views;

import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.html.Div;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.html.Span;
import com.vaadin.flow.component.textfield.PasswordField;
import com.vaadin.flow.component.textfield.TextField;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import com.vaadin.flow.router.RouterLink;
import com.vaadin.flow.server.auth.AnonymousAllowed;
import de.cachebox.website.MainLayout;
import de.cachebox.website.tickets.TicketAccounts;
import de.cachebox.website.tickets.TicketException;

@AnonymousAllowed
@Route(value = "registrieren", layout = MainLayout.class)
@PageTitle("Konto erstellen | iCachebox")
public class RegisterView extends Page {
    public RegisterView(TicketAccounts accounts) {
        super("Dein Ticketkonto", "Erstelle ein Konto, um Fehler zu melden, Ideen einzureichen und Antworten zu lesen.");
        addClassName("tickets");
        TextField username = new TextField("Benutzername");
        username.setMaxLength(40); username.setRequired(true); username.setAutocomplete(com.vaadin.flow.component.textfield.Autocomplete.USERNAME);
        PasswordField password = new PasswordField("Passwort");
        password.setRequired(true); password.setAutocomplete(com.vaadin.flow.component.textfield.Autocomplete.NEW_PASSWORD);
        password.setHelperText("Mindestens zehn Zeichen; bitte für diese Website ein eigenes Passwort verwenden.");
        PasswordField confirmation = new PasswordField("Passwort wiederholen");
        confirmation.setRequired(true); confirmation.setAutocomplete(com.vaadin.flow.component.textfield.Autocomplete.NEW_PASSWORD);
        Span status = new Span(); status.getElement().setAttribute("role", "status");
        Button register = new Button("Konto erstellen", event -> {
            try {
                if (!password.getValue().equals(confirmation.getValue())) throw new TicketException("Die Passwörter stimmen nicht überein.");
                accounts.register(username.getValue(), password.getValue());
                password.clear(); confirmation.clear();
                getUI().ifPresent(ui -> ui.navigate(LoginView.class,
                        com.vaadin.flow.router.QueryParameters.simple(java.util.Map.of("registered", "true"))));
            } catch (TicketException ex) { status.setText(ex.getMessage()); }
        });
        Div form = new Div(username, password, confirmation, register, status,
                new RouterLink("Bereits ein Konto? Anmelden", LoginView.class));
        form.addClassNames("card", "ticket-form");
        add(form, new Paragraph("Der Benutzername wird bei deinen Antworten angezeigt. Deine Tickets sind für dich und den Administrator sichtbar. "
                + "Eine Veröffentlichung auf GitHub erfolgt nur mit deiner ausdrücklichen Freigabe."));
    }
}
