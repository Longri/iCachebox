package de.cachebox.website.tickets;

import de.cachebox.website.tickets.GithubTicketClient.*;
import de.cachebox.website.tickets.TicketModels.*;
import java.nio.file.Path;
import java.time.Instant;
import java.util.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class GithubTicketSyncTest {
    @TempDir Path directory;
    TicketStore store;
    final GithubTicketClient github = mock(GithubTicketClient.class);
    final TicketSyncSettings settings = new TicketSyncSettings(true, "test-token", "https://website.example");
    final Actor owner = new Actor("alice", false), admin = new Actor("Longri", true);
    GithubTicketSync sync;
    final Map<Long, Issue> remote = new LinkedHashMap<>();
    final List<Comment> comments = new ArrayList<>();

    @BeforeEach void setup() throws Exception {
        store = new TicketStore(directory.toString()); sync = new GithubTicketSync(store, github, settings);
        when(github.issues()).thenAnswer(i -> List.copyOf(remote.values()));
        when(github.comments(anyLong())).thenAnswer(i -> List.copyOf(comments));
        when(github.create(anyString(), anyString())).thenAnswer(i -> {
            Issue issue = new Issue(remote.size()+1L,i.getArgument(0),i.getArgument(1),false,Kind.BUG);
            remote.put(issue.number(),issue); return issue;
        });
        when(github.update(anyLong(), anyString(), anyString(), anyBoolean())).thenAnswer(i -> {
            Issue issue = new Issue(i.getArgument(0),i.getArgument(1),i.getArgument(2),i.getArgument(3),Kind.BUG);
            remote.put(issue.number(),issue); return issue;
        });
        when(github.comment(anyLong(), anyString())).thenAnswer(i -> {
            Comment comment = new Comment(comments.size()+100L,i.getArgument(1),"Longri",Instant.now()); comments.add(comment); return comment;
        });
    }
    @AfterEach void close() throws Exception { store.close(); }
    Ticket create(boolean share) { return store.create(owner, "Ein neues Ticket", "Beschreibung des Fehlers mit Details.", Kind.BUG, share); }

    @Test void repeatedSyncCreatesOneIssueAndOneCommentAndNeverExportsNotesOrPrivateTickets() {
        Ticket ticket = create(true); create(false);
        store.reply(owner, ticket.id(), "Zusätzliche Angaben", false);
        store.reply(admin, ticket.id(), "INTERN-NIEMALS-EXPORTIEREN", true);
        sync.synchronize(admin); sync.synchronize(admin);
        verify(github, times(1)).create(anyString(), anyString());
        verify(github, times(1)).comment(eq(1L), anyString());
        assertThat(remote.get(1L).body()).contains("Beschreibung des Fehlers", "https://website.example/tickets/")
                .doesNotContain("INTERN-NIEMALS-EXPORTIEREN");
        assertThat(comments.getFirst().body()).contains("Zusätzliche Angaben").doesNotContain("INTERN-NIEMALS-EXPORTIEREN");
        assertThat(store.messages(owner, ticket.id())).extracting(Message::body).containsExactly("Zusätzliche Angaben");
        assertThat(store.get(owner,ticket.id()).githubNumber()).isEqualTo(1);
    }

    @Test void markersRecoverIssueAndCommentAfterLostResponseWithoutCreatingDuplicates() {
        Ticket ticket = create(true);
        store.reply(owner,ticket.id(),"Antwort von der Website",false);
        Message message=store.messages(owner,ticket.id()).getFirst();
        remote.put(42L,new Issue(42,ticket.title(),sync.exportBody(ticket),false,Kind.BUG));
        comments.add(new Comment(100,"**Website · alice**\n\nAntwort von der Website\n\n<!-- icb-message:"+message.uid()+" -->","Longri",Instant.now()));
        sync.synchronize(admin); sync.synchronize(admin);
        verify(github,never()).create(anyString(),anyString()); verify(github,never()).comment(anyLong(),anyString());
        assertThat(store.get(owner,ticket.id()).githubNumber()).isEqualTo(42);
        assertThat(store.messages(owner,ticket.id())).hasSize(1);
    }

    @Test void titleDescriptionAndClosedStatusMoveBothWaysWithoutChangingManualRank() {
        Ticket ticket=create(true); Ticket next=create(false);
        store.move(admin,next.id(),ticket.id(),true);
        sync.synchronize(admin);
        Issue issue=remote.get(1L);
        remote.put(1L,new Issue(1,"Auf GitHub geändert",issue.body().replace("Beschreibung des Fehlers mit Details.","Neue Beschreibung direkt von GitHub."),true,Kind.BUG));
        comments.add(new Comment(200,"Rückfrage direkt von GitHub","Longri",Instant.now()));
        sync.synchronize(admin);
        Ticket imported=store.get(owner,ticket.id());
        assertThat(imported.title()).isEqualTo("Auf GitHub geändert");
        assertThat(imported.body()).isEqualTo("Neue Beschreibung direkt von GitHub.");
        assertThat(imported.status()).isEqualTo(Status.DONE);
        assertThat(store.list(admin)).extracting(Ticket::id).containsExactly(next.id(),ticket.id());
        store.edit(owner,ticket.id(),imported.revision(),"Website übernimmt wieder","Neue Beschreibung von der Website.",Kind.BUG);
        store.status(admin,ticket.id(),Status.IN_PROGRESS);
        sync.synchronize(admin);
        assertThat(remote.get(1L).title()).isEqualTo("Website übernimmt wieder");
        assertThat(remote.get(1L).closed()).isFalse();
        assertThat(store.get(owner,ticket.id()).status()).isEqualTo(Status.IN_PROGRESS);
        assertThat(store.messages(owner,ticket.id())).extracting(Message::body).containsExactly("Rückfrage direkt von GitHub");
    }

    @Test void simultaneousChangesWaitForExplicitResolutionAndStaleResolutionIsRejected() {
        Ticket ticket=create(true); sync.synchronize(admin);
        Issue initial=remote.get(1L);
        store.edit(owner,ticket.id(),ticket.revision(),"Website-Titel","Website-Beschreibung unverändert.",Kind.BUG);
        remote.put(1L,new Issue(1,"GitHub-Titel",initial.body(),false,Kind.BUG));
        sync.synchronize(admin);
        Ticket conflict=store.get(admin,ticket.id());
        assertThat(conflict.conflict()).isTrue();
        assertThat(conflict.title()).isEqualTo("Website-Titel");
        assertThat(remote.get(1L).title()).isEqualTo("GitHub-Titel");
        assertThatThrownBy(() -> store.resolve(owner,ticket.id(),true,conflict.revision(),initial.body())).isInstanceOf(org.springframework.security.access.AccessDeniedException.class);
        assertThatThrownBy(() -> store.resolve(admin,ticket.id(),true,0,initial.body())).isInstanceOf(TicketException.class);
        store.resolve(admin,ticket.id(),false,conflict.revision(),initial.body()); sync.synchronize(admin);
        assertThat(remote.get(1L).title()).isEqualTo("Website-Titel");
        assertThat(store.get(admin,ticket.id()).conflict()).isFalse();
    }

    @Test void unrelatedFieldEditsMergeAndExternalIssuesAreImportedOnceForAdminOnly() {
        Ticket ticket=create(true); sync.synchronize(admin);
        Issue initial=remote.get(1L);
        store.edit(owner,ticket.id(),ticket.revision(),"Lokaler Titel",ticket.body(),Kind.BUG);
        remote.put(1L,new Issue(1,initial.title(),initial.body().replace(ticket.body(),"Andere Beschreibung von GitHub."),false,Kind.BUG));
        remote.put(9L,new Issue(9,"Externes GitHub-Issue","Nur im Adminbereich importieren.",false,Kind.FEATURE));
        sync.synchronize(admin); sync.synchronize(admin);
        assertThat(store.get(owner,ticket.id()).title()).isEqualTo("Lokaler Titel");
        assertThat(store.get(owner,ticket.id()).body()).isEqualTo("Andere Beschreibung von GitHub.");
        assertThat(store.get(owner,ticket.id()).conflict()).isFalse();
        assertThat(store.list(owner)).hasSize(1);
        assertThat(store.list(admin)).hasSize(2);
    }

    @Test void editsToGithubCommentsReturnToWebsiteWithoutEchoOrDuplicates() {
        Ticket ticket=create(true); store.reply(owner,ticket.id(),"Ursprüngliche Antwort",false); sync.synchronize(admin);
        Comment original=comments.getFirst();
        comments.set(0,new Comment(original.id(),original.body().replace("Ursprüngliche Antwort","Auf GitHub geändert"),original.author(),original.createdAt()));
        sync.synchronize(admin); sync.synchronize(admin);
        assertThat(store.messages(owner,ticket.id())).extracting(Message::body).containsExactly("Auf GitHub geändert");
        verify(github,times(1)).comment(eq(1L),anyString());
    }
}
