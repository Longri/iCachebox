package de.cachebox.website.views;

import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.html.Anchor;
import com.vaadin.flow.component.html.Div;
import com.vaadin.flow.component.html.H2;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.html.Span;
import com.vaadin.flow.component.textfield.TextArea;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import com.vaadin.flow.server.VaadinRequest;
import com.vaadin.flow.server.VaadinServletRequest;
import com.vaadin.flow.server.auth.AnonymousAllowed;
import de.cachebox.website.MainLayout;
import de.cachebox.website.oauth.GroundspeakAuthorization;
import de.cachebox.website.oauth.GroundspeakSettings;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;

@AnonymousAllowed
@Route(value = "api-key", layout = MainLayout.class)
@PageTitle("Geocaching-Zugang – iCachebox")
public class ApiKeyView extends Page {
    public ApiKeyView(GroundspeakSettings settings, GroundspeakAuthorization authorization) {
        super("Dein Geocaching-Zugang",
                "Verbinde dein Geocaching.com-Konto mit iCachebox und erstelle einen persönlichen Zugriffstoken.");
        addClassName("api-key");

        var request = VaadinRequest.getCurrent();
        if (request instanceof VaadinServletRequest servletRequest) {
            var result = authorization.takeResult(servletRequest.getHttpServletRequest().getSession(false));
            if (result != null) showResult(result);
        }

        Div connect = new Div(new H2("Bei Geocaching.com anmelden"), new Paragraph(
                "Die Anmeldung und Freigabe erfolgen direkt bei Geocaching.com. "
                        + "Dein Passwort wird dieser Website nicht mitgeteilt."));
        connect.addClassName("card");
        if (settings.configured()) {
            Anchor start = new Anchor("oauth/groundspeak/start", "Mit Geocaching.com verbinden");
            start.addClassNames("button", "button-primary");
            start.getElement().setAttribute("router-ignore", "");
            connect.add(start);
        } else {
            Paragraph unavailable = new Paragraph("Der Geocaching-Zugang ist noch nicht eingerichtet. "
                    + "Sobald iCachebox freigeschaltet ist, kannst du hier dein Konto verbinden.");
            unavailable.getElement().setAttribute("role", "status");
            connect.add(unavailable);
        }
        add(connect, new Paragraph("Ein persönlicher Zugriffstoken erlaubt den API-Zugriff auf dein Konto. "
                + "Die direkte Anmeldung in der iOS-App ist noch in Vorbereitung. "
                + "Diese Seite stellt keine neuen Partner-Zugangsdaten von Groundspeak aus."));
    }

    private void showResult(GroundspeakAuthorization.Result result) {
        Div output = new Div();
        output.addClassNames("card", "api-key-result");
        if (result.error() != null) {
            output.add(new H2("Anmeldung nicht abgeschlossen"), new Paragraph(result.error()));
            output.getElement().setAttribute("role", "alert");
        } else {
            output.add(new H2("Dein Zugriffstoken wurde erstellt"), new Paragraph(
                    "Behandle beide Token wie ein Passwort. Sie werden nur in dieser Browsersitzung angezeigt. "
                            + "Nach dem Neuladen sind sie nicht erneut abrufbar."));
            output.add(tokenField("Zugriffstoken (Access Token)", result.accessToken()),
                    tokenField("Erneuerungstoken (Refresh Token)", result.refreshToken()));
            String expires = DateTimeFormatter.ofPattern("dd.MM.yyyy HH:mm 'Uhr'")
                    .withZone(ZoneId.of("Europe/Berlin")).format(result.expiresAt());
            output.add(new Paragraph("Zugriffstoken gültig bis " + expires + " (Europa/Berlin). "
                    + "Für die spätere Erneuerung wird der Refresh Token benötigt."));
        }
        output.add(new Button("Anzeige schließen", event -> remove(output)));
        add(output);
    }

    private Div tokenField(String label, String token) {
        TextArea field = new TextArea(label);
        field.setValue(token);
        field.setReadOnly(true);
        field.setWidthFull();
        field.setMaxHeight("180px");
        field.getElement().setAttribute("autocomplete", "off");
        field.getElement().setAttribute("spellcheck", "false");
        Span status = new Span();
        status.getElement().setAttribute("role", "status");
        Button copy = new Button("Kopieren", event -> field.getElement().executeJs(
                "return navigator.clipboard ? navigator.clipboard.writeText($0).then(() => true).catch(() => false) : false", token)
                .then(Boolean.class, copied -> status.setText(Boolean.TRUE.equals(copied)
                        ? "Kopiert." : "Bitte den Token im Feld markieren und kopieren.")));
        return new Div(field, copy, status);
    }
}
