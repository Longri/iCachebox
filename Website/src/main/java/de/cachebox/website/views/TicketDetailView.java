package de.cachebox.website.views;

import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.checkbox.Checkbox;
import com.vaadin.flow.component.combobox.ComboBox;
import com.vaadin.flow.component.details.Details;
import com.vaadin.flow.component.html.*;
import com.vaadin.flow.component.textfield.TextArea;
import com.vaadin.flow.component.textfield.TextField;
import com.vaadin.flow.component.upload.Upload;
import com.vaadin.flow.router.*;
import com.vaadin.flow.server.streams.UploadEvent;
import com.vaadin.flow.server.streams.UploadHandler;
import de.cachebox.website.MainLayout;
import de.cachebox.website.tickets.*;
import de.cachebox.website.tickets.TicketModels.*;
import jakarta.annotation.security.RolesAllowed;
import java.io.IOException;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import org.springframework.security.access.AccessDeniedException;

@RolesAllowed({"USER", "ADMIN"})
@Route(value = "tickets", layout = MainLayout.class)
@PageTitle("Ticket | iCachebox")
public class TicketDetailView extends Div implements HasUrlParameter<Long> {
    private final TicketStore store;
    private final TicketImages images;
    private final Actor actor;
    private final Div screenshots = new Div();
    private final Span feedback = new Span();
    private long id;

    public TicketDetailView(TicketStore store, TicketImages images) {
        this.store = store; this.images = images; this.actor = Actor.current();
        addClassNames("page", "tickets", "ticket-detail");
        feedback.getElement().setAttribute("role", "status");
    }

    @Override public void setParameter(BeforeEvent event, Long parameter) {
        this.id = parameter;
        try { render(); }
        catch (AccessDeniedException ex) { event.rerouteToError(NotFoundException.class, "Ticket nicht verfügbar."); }
    }

    private void render() {
        Ticket ticket = store.get(actor, id);
        removeAll();
        add(new RouterLink("← Zur Ticketübersicht", TicketsView.class), new H1("#" + id + " · " + ticket.title()),
                new Paragraph(ticket.kind() + " · " + ticket.status() + " · " + (ticket.owner().isEmpty() ? "Aus GitHub" : ticket.owner())));
        Div description = new Div(new Paragraph(ticket.body())); description.addClassNames("card", "ticket-prose"); add(description);

        TextField title = new TextField("Titel"); title.setValue(ticket.title()); title.setMaxLength(200);
        TextArea body = new TextArea("Beschreibung"); body.setValue(ticket.body()); body.setMaxLength(20000); body.setMinHeight("200px");
        ComboBox<Kind> kind = new ComboBox<>("Typ"); kind.setItems(Kind.values()); kind.setValue(ticket.kind());
        Div editor = new Div(title, body, kind, new Button("Änderungen speichern", e -> act(() ->
                store.edit(actor, id, ticket.revision(), title.getValue(), body.getValue(), kind.getValue()))));
        editor.addClassName("ticket-form"); add(new Details("Titel und Beschreibung bearbeiten", editor));
        if (actor.admin()) {
            ComboBox<Status> status = new ComboBox<>("Bearbeitungsstatus"); status.setItems(Status.values()); status.setValue(ticket.status());
            status.addValueChangeListener(e -> { if (e.getValue() != null) act(() -> store.status(actor, id, e.getValue())); });
            add(status);
        }
        if (ticket.githubNumber() > 0) {
            Anchor github = new Anchor("https://github.com/Longri/iCachebox/issues/" + ticket.githubNumber(), "GitHub-Issue #" + ticket.githubNumber());
            github.setTarget("_blank"); github.getElement().setAttribute("rel", "noopener noreferrer"); add(github);
        } else if (ticket.shareGithub()) add(new Paragraph("Zur Veröffentlichung und Synchronisation mit GitHub freigegeben."));
        else if (actor.username().equals(ticket.owner())) {
            Checkbox consent = new Checkbox("Titel, Beschreibung, Benutzername und alle öffentlichen Antworten dürfen auf GitHub öffentlich erscheinen. Screenshots bleiben geschützt.");
            Button allow = new Button("Für GitHub freigeben", e -> { if (consent.getValue()) act(() -> store.allowGithub(actor, id)); });
            allow.setEnabled(false); consent.addValueChangeListener(e -> allow.setEnabled(e.getValue()));
            add(new Details("Optional auf GitHub veröffentlichen", new Div(consent, allow)));
        }

        if (actor.admin() && ticket.conflict()) {
            Conflict remote = store.conflictDetails(actor, id);
            Div conflict = new Div(new H2("Gleichzeitige Änderungen prüfen"), new Paragraph(
                    "Website und GitHub wurden seit dem letzten Abgleich unterschiedlich geändert. Deine Website-Version steht oben. Wähle, welche Fassung übernommen werden soll."),
                    new H3("GitHub: " + remote.title()), new Paragraph(remote.closed() ? "Geschlossen" : "Offen"), new Paragraph(remote.body()),
                    new Button("Website-Version übernehmen", e -> act(() -> store.resolve(actor, id, false, ticket.revision(), remote.body()))),
                    new Button("GitHub-Version übernehmen", e -> act(() -> store.resolve(actor, id, true, ticket.revision(), remote.body()))));
            conflict.addClassNames("card", "ticket-conflict", "ticket-prose"); add(conflict);
        }

        add(new H2("Screenshots"), new Paragraph("Bis zu zehn PNG- oder JPEG-Bilder, je höchstens 8 MB. Nur du und der Administrator können sie öffnen."));
        screenshots.addClassName("ticket-screenshots"); renderScreenshots(); add(screenshots);
        Upload upload = new Upload(new UploadHandler() {
            @Override public long getFileSizeMax() { return TicketImages.MAX_BYTES; }
            @Override public long getRequestSizeMax() { return TicketImages.MAX_BYTES + 65536L; }
            @Override public long getFileCountMax() { return 10; }
            @Override public void handleUploadRequest(UploadEvent event) throws IOException {
                try (var input = event.getInputStream()) { images.upload(Actor.current(), id, event.getFileName(), input); }
                catch (TicketException | AccessDeniedException ex) { event.reject(ex.getMessage()); }
            }
        });
        upload.setMaxFiles(10); upload.setMaxFileSize(TicketImages.MAX_BYTES); upload.setAcceptedFileTypes("image/png", "image/jpeg");
        upload.setDropAllowed(true); upload.setUploadButton(new Button("Screenshots auswählen"));
        upload.setDropLabel(new Span("Bilder hierher ziehen"));
        // UploadHandler uses browser completion events, rather than the deprecated Receiver events.
        upload.getElement().addEventListener("upload-success", e -> { renderScreenshots(); feedback.setText("Screenshot gespeichert."); });
        upload.getElement().addEventListener("upload-error", e -> feedback.setText("Der Screenshot konnte nicht gespeichert werden. Bitte Dateityp, Größe und die Anzahl der Bilder prüfen."));
        upload.addFileRejectedListener(e -> feedback.setText("Bitte höchstens zehn PNG- oder JPEG-Bilder mit je maximal 8 MB auswählen."));
        Div paste = new Div(new Span("Screenshot aus der Zwischenablage: diesen Bereich anklicken und einfügen (⌘V / Strg+V)."), upload);
        paste.addClassName("ticket-paste"); paste.getElement().setAttribute("tabindex", "0");
        paste.getElement().setAttribute("role", "group"); paste.getElement().setAttribute("aria-label", "Screenshots hinzufügen");
        paste.getElement().executeJs("""
                const upload = $0;
                this.addEventListener('click', e => { if (e.target === this) this.focus(); });
                this.addEventListener('paste', e => {
                    const files = Array.from(e.clipboardData?.files || []).filter(f => ['image/png','image/jpeg'].includes(f.type));
                    if (files.length) { e.preventDefault(); upload.uploadFiles(files); }
                });
                """, upload.getElement());
        add(paste, new H2("Verlauf"));
        for (Message message : store.messages(actor, id)) {
            String date = DateTimeFormatter.ofPattern("dd.MM.yyyy HH:mm").withZone(ZoneId.of("Europe/Berlin")).format(message.createdAt());
            Div entry = new Div(new H3((message.internal() ? "Interne Notiz · " : "") + message.author() + " · " + date), new Paragraph(message.body()));
            entry.addClassNames("card", "ticket-message", "ticket-prose"); if (message.internal()) entry.addClassName("ticket-note"); add(entry);
        }
        TextArea reply = new TextArea(actor.admin() ? "Antwort oder interne Notiz" : "Weitere Informationen");
        reply.setWidthFull(); reply.setMaxLength(20000); reply.setMinHeight("160px");
        Button answer = new Button(actor.admin() ? "Antwort senden" : "Informationen ergänzen", e -> act(() -> store.reply(actor, id, reply.getValue(), false)));
        Div compose = new Div(reply, answer);
        if (actor.admin()) compose.add(new Button("Als interne Notiz speichern", e -> act(() -> store.reply(actor, id, reply.getValue(), true))),
                new Paragraph("Interne Notizen sind nur für Administratoren sichtbar und werden niemals an GitHub übertragen."));
        compose.addClassNames("card", "ticket-form"); add(compose, feedback);
    }

    private void renderScreenshots() {
        screenshots.removeAll();
        for (Attachment file : store.attachments(actor, id)) {
            String url = "ticket-attachments/" + file.id();
            Image image = new Image(url, file.name()); image.getElement().setAttribute("loading", "lazy");
            Anchor link = new Anchor(url, image); link.setTarget("_blank"); link.getElement().setAttribute("rel", "noopener");
            screenshots.add(new Div(link, new Span(file.name())));
        }
    }
    private void act(Runnable work) {
        try { work.run(); render(); feedback.setText("Gespeichert."); }
        catch (TicketException ex) { feedback.setText(ex.getMessage()); }
    }
}
