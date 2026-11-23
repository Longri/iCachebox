package de.cachebox.website.tickets;

import de.cachebox.website.tickets.TicketModels.Actor;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class TicketAttachmentController {
    private final TicketStore store;
    public TicketAttachmentController(TicketStore store) { this.store = store; }

    @GetMapping("/ticket-attachments/{id}")
    ResponseEntity<byte[]> image(@PathVariable String id) {
        Actor actor = Actor.current();
        var file = store.attachment(actor, id);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).header("X-Content-Type-Options", "nosniff")
                .header("Content-Security-Policy", "default-src 'none'; sandbox")
                .header(HttpHeaders.CONTENT_DISPOSITION, "inline")
                .contentType(MediaType.parseMediaType(file.mediaType())).body(store.image(actor, id));
    }
}
