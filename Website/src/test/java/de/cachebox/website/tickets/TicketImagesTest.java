package de.cachebox.website.tickets;

import de.cachebox.website.tickets.TicketModels.*;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.nio.file.Path;
import javax.imageio.ImageIO;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.security.access.AccessDeniedException;
import static org.assertj.core.api.Assertions.*;

class TicketImagesTest {
    @TempDir Path directory;
    TicketStore store;
    @AfterEach void close() throws Exception { if (store != null) store.close(); }

    @Test void verifiesActualImageContentAndRejectsOversizedOrForeignUploads() throws Exception {
        store = new TicketStore(directory.toString());
        var actor = new Actor("alice", false);
        var ticket = store.create(actor, "Bildproblem", "Die Anzeige enthält einen Fehler.", Kind.BUG, false);
        var images = new TicketImages(store);
        var buffer = new ByteArrayOutputStream();
        ImageIO.write(new BufferedImage(20, 20, BufferedImage.TYPE_INT_RGB), "png", buffer);
        images.upload(actor, ticket.id(), "../Screenshot.png", new ByteArrayInputStream(buffer.toByteArray()));
        var attachment = store.attachments(actor, ticket.id()).getFirst();
        assertThat(attachment.name()).doesNotContain("/", "\\");
        assertThat(attachment.mediaType()).isEqualTo("image/png");
        assertThat(ImageIO.read(new ByteArrayInputStream(store.image(actor, attachment.id()))).getWidth()).isEqualTo(20);
        assertThatThrownBy(() -> images.upload(actor, ticket.id(), "fake.png", new ByteArrayInputStream("<svg onload='alert(1)'/>".getBytes())))
                .isInstanceOf(TicketException.class);
        assertThatThrownBy(() -> images.upload(actor, ticket.id(), "large.png", new ByteArrayInputStream(new byte[TicketImages.MAX_BYTES+1])))
                .isInstanceOf(TicketException.class).hasMessageContaining("8 MB");
        assertThatThrownBy(() -> images.upload(new Actor("bob", false), ticket.id(), "file.png", new ByteArrayInputStream(buffer.toByteArray())))
                .isInstanceOf(AccessDeniedException.class);
    }
}
