package de.cachebox.website.tickets;

import de.cachebox.website.tickets.GithubTicketClient.*;
import de.cachebox.website.tickets.TicketModels.*;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.locks.ReentrantLock;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

@Service
public class GithubTicketSync {
    private final TicketStore store;
    private final GithubTicketClient github;
    private final TicketSyncSettings settings;
    private final ReentrantLock lock = new ReentrantLock();
    private volatile String summary = "Noch kein GitHub-Abgleich ausgeführt.";

    public GithubTicketSync(TicketStore store, GithubTicketClient github, TicketSyncSettings settings) {
        this.store = store; this.github = github; this.settings = settings;
    }

    public String summary(Actor actor) { actor.requireAdmin(); return settings.configured() ? summary : "GitHub-Synchronisation noch nicht eingerichtet."; }
    public boolean configured() { return settings.configured(); }
    public void checkConnection(Actor actor) { actor.requireAdmin(); github.checkConnection(); }
    public void synchronize(Actor actor) { actor.requireAdmin(); synchronize(); }

    @Scheduled(fixedDelayString = "${website.tickets.github.interval-ms:120000}", initialDelayString = "${website.tickets.github.interval-ms:120000}")
    public void scheduled() {
        if (!settings.configured()) return;
        try { synchronize(); }
        catch (TicketException ex) { summary = ex.getMessage(); }
        catch (RuntimeException ex) { summary = "Der GitHub-Abgleich konnte nicht abgeschlossen werden. Bitte die Konfiguration prüfen."; }
    }

    private void synchronize() {
        if (!settings.configured()) throw new TicketException("Die GitHub-Synchronisation ist auf dem Server noch nicht eingerichtet.");
        if (!lock.tryLock()) throw new TicketException("Ein GitHub-Abgleich läuft bereits.");
        try {
            List<Issue> remote = github.issues(); // A complete list is needed for retry-safe creation.
            Set<Long> handled = new HashSet<>();
            int conflicts = 0;
            for (SyncState state : store.syncTickets()) {
                Ticket ticket = state.ticket();
                Issue issue = remote.stream().filter(i -> ticket.githubNumber() > 0
                        ? i.number() == ticket.githubNumber() : i.body().endsWith(marker(ticket))).findFirst().orElse(null);
                if (issue == null) {
                    if (ticket.githubNumber() > 0) throw new TicketException("Ein verknüpftes GitHub-Issue ist nicht mehr erreichbar. Es wird nicht erneut angelegt.");
                    issue = github.create(ticket.title(), exportBody(ticket));
                    if (ticket.status().closed()) issue = github.update(issue.number(), issue.title(), issue.body(), true);
                    store.link(ticket.id(), issue.number());
                    store.acknowledge(ticket, issue.title(), issue.body(), issue.closed(), ticket.body(), false);
                } else {
                    store.link(ticket.id(), issue.number());
                    if (ticket.conflict()) {
                        store.conflict(ticket.id(), issue.title(), issue.body(), issue.closed());
                        conflicts++;
                    } else {
                        String localBody = exportBody(ticket);
                        boolean newLink = state.baseTitle() == null;
                        boolean collision = newLink
                                ? !ticket.title().equals(issue.title()) || !localBody.equals(issue.body()) || ticket.status().closed() != issue.closed()
                                : conflict(ticket.title(), issue.title(), state.baseTitle())
                                    || conflict(localBody, issue.body(), state.baseBody())
                                    || conflict(ticket.status().closed(), issue.closed(), state.baseClosed());
                        if (collision) {
                            store.conflict(ticket.id(), issue.title(), issue.body(), issue.closed());
                            conflicts++;
                        } else {
                            String title = newLink ? ticket.title() : merge(ticket.title(), issue.title(), state.baseTitle());
                            String body = newLink ? localBody : merge(localBody, issue.body(), state.baseBody());
                            boolean closed = newLink ? ticket.status().closed() : merge(ticket.status().closed(), issue.closed(), state.baseClosed());
                            if (!title.equals(issue.title()) || !body.equals(issue.body()) || closed != issue.closed()) {
                                issue = github.update(issue.number(), title, body, closed);
                            }
                            boolean applyRemote = !ticket.title().equals(issue.title()) || !localBody.equals(issue.body()) || ticket.status().closed() != issue.closed();
                            store.acknowledge(ticket, issue.title(), issue.body(), issue.closed(), localBody(ticket, issue.body()), applyRemote);
                        }
                    }
                }
                handled.add(issue.number());
                comments(ticket, issue.number());
            }
            for (Issue issue : remote) if (!handled.contains(issue.number())) {
                Ticket ticket = store.importIssue(issue.number(), issue.title(), issue.body(), issue.closed(), issue.kind());
                comments(ticket, issue.number());
            }
            String time = java.time.format.DateTimeFormatter.ofPattern("dd.MM.yyyy HH:mm 'Uhr'")
                    .withZone(java.time.ZoneId.of("Europe/Berlin")).format(Instant.now());
            summary = "Abgleich abgeschlossen: " + time + (conflicts == 0 ? "." : " · " + conflicts + " Konflikt(e) bitte prüfen.");
        } catch (TicketException ex) { summary = ex.getMessage(); throw ex; }
        finally { lock.unlock(); }
    }

    private void comments(Ticket ticket, long number) {
        List<Comment> remote = new ArrayList<>(github.comments(number));
        List<Message> local = store.syncMessages(ticket.id());
        for (Message message : local) if (message.githubId() == 0) {
            String marker = messageMarker(message);
            Comment existing = remote.stream().filter(c -> c.body().endsWith(marker)).findFirst().orElse(null);
            if (existing == null) {
                existing = github.comment(number, messagePrefix(message) + message.body() + "\n\n" + marker);
                remote.add(existing);
            }
            store.linkMessage(message.id(), existing.id(), existing.body());
        }
        List<Message> linked = store.syncMessages(ticket.id());
        for (Comment comment : remote) {
            Message known = linked.stream().filter(m -> m.githubId() == comment.id()).findFirst().orElse(null);
            String display = comment.body();
            if (known != null && display.startsWith(messagePrefix(known))) display = display.substring(messagePrefix(known).length());
            if (known != null && display.endsWith("\n\n" + messageMarker(known))) {
                display = display.substring(0, display.length() - ("\n\n" + messageMarker(known)).length());
            }
            store.importComment(ticket.id(), comment.id(), comment.author(), comment.body(), display, comment.createdAt());
        }
    }

    String exportBody(Ticket ticket) {
        if (ticket.fromGithub()) return ticket.body();
        String website = settings.websiteUrl.isBlank() ? "Geschütztes Ticket #" + ticket.id()
                : "[Ticket #" + ticket.id() + "](" + settings.websiteUrl + "/tickets/" + ticket.id() + ")";
        return ticket.body() + metaMarker(ticket) + "\n\n**Typ:** " + ticket.kind() + "\n\n**Website:** " + website
                + " · Anmeldung erforderlich; Screenshots bleiben geschützt.\n\n" + marker(ticket);
    }

    static String localBody(Ticket ticket, String remoteBody) {
        if (ticket.fromGithub()) return remoteBody;
        int at = remoteBody.indexOf(metaMarker(ticket));
        return at < 0 ? remoteBody : remoteBody.substring(0, at);
    }
    private static String metaMarker(Ticket ticket) { return "\n\n<!-- icb-ticket-meta:" + ticket.uid() + " -->"; }
    private static String marker(Ticket ticket) { return "<!-- icb-ticket:" + ticket.uid() + " -->"; }
    private static String messageMarker(Message message) { return "<!-- icb-message:" + message.uid() + " -->"; }
    private static String messagePrefix(Message message) { return "**Website · " + message.author() + "**\n\n"; }
    private static <T> boolean conflict(T local, T remote, T base) {
        return !Objects.equals(local, base) && !Objects.equals(remote, base) && !Objects.equals(local, remote);
    }
    private static <T> T merge(T local, T remote, T base) { return Objects.equals(local, base) ? remote : local; }
}
