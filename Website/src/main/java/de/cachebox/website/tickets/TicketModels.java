package de.cachebox.website.tickets;

import java.time.Instant;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.context.SecurityContextHolder;

public final class TicketModels {
    private TicketModels() { }

    public enum Kind {
        BUG("Fehler"), FEATURE("Featurewunsch");
        private final String label;
        Kind(String label) { this.label = label; }
        @Override public String toString() { return label; }
    }

    public enum Status {
        NEW("Neu"), QUESTION("Rückfrage"), PLANNED("Geplant"), IN_PROGRESS("In Arbeit"), DONE("Erledigt");
        private final String label;
        Status(String label) { this.label = label; }
        public boolean closed() { return this == DONE; }
        @Override public String toString() { return label; }
    }

    public record Actor(String username, boolean admin) {
        public static Actor current() {
            var auth = SecurityContextHolder.getContext().getAuthentication();
            if (auth == null || !auth.isAuthenticated() || "anonymousUser".equals(auth.getPrincipal())) {
                throw new AccessDeniedException("Bitte zuerst anmelden.");
            }
            return new Actor(auth.getName(), auth.getAuthorities().stream().anyMatch(a -> "ROLE_ADMIN".equals(a.getAuthority())));
        }
        void requireAdmin() { if (!admin) throw new AccessDeniedException("Nur für Administratoren."); }
    }

    public record Ticket(long id, String uid, String owner, String title, String body, Kind kind, Status status,
            long rank, long revision, Instant createdAt, Instant updatedAt, long githubNumber,
            boolean shareGithub, boolean conflict, boolean fromGithub) { }
    public record Message(long id, String uid, long ticketId, String author, String body, boolean internal,
            Instant createdAt, long githubId, String githubBody) { }
    public record Attachment(String id, long ticketId, String name, String mediaType, long size) { }
    public record Conflict(String title, String body, boolean closed) { }
    record SyncState(Ticket ticket, String baseTitle, String baseBody, Boolean baseClosed,
            String remoteTitle, String remoteBody, Boolean remoteClosed) { }
}
