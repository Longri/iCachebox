package de.cachebox.website.tickets;

import de.cachebox.website.tickets.TicketModels.*;
import java.nio.file.Path;
import java.util.List;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.security.access.AccessDeniedException;
import static org.assertj.core.api.Assertions.*;

class TicketStoreTest {
    @TempDir Path directory;
    TicketStore store;
    final Actor owner = new Actor("alice", false), other = new Actor("bob", false), admin = new Actor("Longri", true);
    @BeforeEach void open() throws Exception { store = new TicketStore(directory.toString()); }
    @AfterEach void close() throws Exception { store.close(); }
    Ticket create(String title) { return store.create(owner, title, "Eine ausführliche Beschreibung zum Nachstellen.", Kind.BUG, false); }

    @Test void ownersCannotReadOrChangeOtherTicketsAndNotesNeverReachNormalUsers() {
        Ticket ticket = create("Karte bleibt leer");
        store.reply(admin, ticket.id(), "Öffentliche Rückfrage", false);
        store.reply(admin, ticket.id(), "INTERN: persönliche Arbeitsnotiz", true);
        assertThat(store.list(other)).isEmpty();
        assertThatThrownBy(() -> store.get(other, ticket.id())).isInstanceOf(AccessDeniedException.class);
        assertThatThrownBy(() -> store.edit(other, ticket.id(), 0, "Fremder Titel", "Fremder Beschreibungstext", Kind.FEATURE)).isInstanceOf(AccessDeniedException.class);
        assertThat(store.messages(owner, ticket.id())).extracting(Message::body).containsExactly("Öffentliche Rückfrage");
        assertThat(store.messages(admin, ticket.id())).hasSize(2);
        assertThat(store.syncMessages(ticket.id())).extracting(Message::body).containsExactly("Öffentliche Rückfrage");
        assertThatThrownBy(() -> store.reply(owner, ticket.id(), "Interne Notiz", true)).isInstanceOf(AccessDeniedException.class);
        assertThatThrownBy(() -> store.status(owner, ticket.id(), Status.DONE)).isInstanceOf(AccessDeniedException.class);
        assertThatThrownBy(() -> store.allowGithub(admin, ticket.id())).isInstanceOf(AccessDeniedException.class);
        assertThat(store.syncTickets()).isEmpty();
        store.allowGithub(owner, ticket.id());
        assertThat(store.syncTickets()).hasSize(1);
    }

    @Test void reorderPersistsAcrossRestartAndMovingOneRowPreservesAllOthers() throws Exception {
        var a=create("Erstes Ticket"); var b=create("Zweites Ticket"); var c=create("Drittes Ticket"); var d=create("Viertes Ticket");
        store.move(admin, d.id(), b.id(), true);
        assertThat(store.list(admin)).extracting(Ticket::id).containsExactly(a.id(),d.id(),b.id(),c.id());
        store.move(admin, a.id(), c.id(), false);
        assertThatThrownBy(() -> store.move(owner, b.id(), a.id(), true)).isInstanceOf(AccessDeniedException.class);
        store.close(); store = new TicketStore(directory.toString());
        assertThat(store.list(admin)).extracting(Ticket::id).containsExactly(d.id(),b.id(),c.id(),a.id());
        assertThat(store.list(owner)).hasSize(4);
    }

    @Test void staleEditsAreRejectedAndStatusDoesNotLoseItsOwnRevision() {
        Ticket original = create("Ein bearbeitetes Ticket");
        store.edit(owner, original.id(), original.revision(), "Aktueller Titel", "Die aktualisierte Beschreibung.", Kind.FEATURE);
        assertThatThrownBy(() -> store.edit(owner, original.id(), original.revision(), "Veralteter Titel", "Diese Änderung wäre veraltet.", Kind.BUG))
                .isInstanceOf(TicketException.class).hasMessageContaining("inzwischen geändert");
        assertThat(store.get(owner, original.id()).title()).isEqualTo("Aktueller Titel");
        store.status(admin, original.id(), Status.IN_PROGRESS);
        assertThat(store.get(owner, original.id()).revision()).isEqualTo(2);
    }

    @Test void attachmentBytesAndMetadataArePrivateAndSurviveRestart() throws Exception {
        Ticket ticket = create("Ticket mit Screenshot");
        store.attach(owner, ticket.id(), "Screenshot.png", "image/png", new byte[]{1,2,3});
        Attachment attachment = store.attachments(owner, ticket.id()).getFirst();
        assertThatThrownBy(() -> store.image(other, attachment.id())).isInstanceOf(AccessDeniedException.class);
        assertThatThrownBy(() -> store.attachments(other, ticket.id())).isInstanceOf(AccessDeniedException.class);
        store.close(); store = new TicketStore(directory.toString());
        assertThat(store.image(owner, attachment.id())).containsExactly(1,2,3);
        assertThat(store.image(admin, attachment.id())).containsExactly(1,2,3);
        for (int i=0;i<9;i++) store.attach(owner, ticket.id(), "Screenshot.png", "image/png", new byte[]{1});
        assertThatThrownBy(() -> store.attach(owner, ticket.id(), "extra.png", "image/png", new byte[]{1})).isInstanceOf(TicketException.class);
    }

    @Test void importedGithubTicketsAreAdminOnlyAndImportIsIdempotent() {
        Ticket ticket = store.importIssue(41, "GitHub-Titel", "Beschreibung", false, Kind.FEATURE);
        assertThat(store.importIssue(41, "GitHub-Titel", "Beschreibung", false, Kind.FEATURE).id()).isEqualTo(ticket.id());
        assertThat(store.list(owner)).isEmpty();
        assertThat(store.list(admin)).hasSize(1);
        assertThatThrownBy(() -> store.get(owner, ticket.id())).isInstanceOf(AccessDeniedException.class);
        store.importComment(ticket.id(), 1001, "Longri", "Eine Antwort", "Eine Antwort", java.time.Instant.now());
        store.importComment(ticket.id(), 1001, "Longri", "Eine geänderte Antwort", "Eine geänderte Antwort", java.time.Instant.now());
        assertThat(store.messages(admin, ticket.id())).extracting(Message::body).containsExactly("Eine geänderte Antwort");
    }
}
