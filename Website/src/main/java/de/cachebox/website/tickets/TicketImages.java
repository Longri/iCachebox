package de.cachebox.website.tickets;

import de.cachebox.website.tickets.TicketModels.Actor;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import javax.imageio.ImageIO;
import org.springframework.stereotype.Service;

@Service
public class TicketImages {
    public static final int MAX_BYTES = 8 * 1024 * 1024;
    private final TicketStore store;
    public TicketImages(TicketStore store) { this.store = store; }

    public void upload(Actor actor, long ticketId, String filename, InputStream input) {
        store.get(actor, ticketId);
        try {
            byte[] bytes = input.readNBytes(MAX_BYTES + 1);
            if (bytes.length > MAX_BYTES) throw new TicketException("Ein Screenshot darf höchstens 8 MB groß sein.");
            // Inspect dimensions before decoding; filenames and the claimed MIME type are untrusted.
            try (var imageInput = ImageIO.createImageInputStream(new ByteArrayInputStream(bytes))) {
                var readers = ImageIO.getImageReaders(imageInput);
                if (!readers.hasNext()) throw invalidImage();
                var reader = readers.next();
                try {
                    String format = reader.getFormatName().toLowerCase(java.util.Locale.ROOT);
                    if (!format.equals("png") && !format.equals("jpeg")) throw invalidImage();
                    reader.setInput(imageInput, true, true);
                    int width = reader.getWidth(0), height = reader.getHeight(0);
                    if (width < 1 || height < 1 || (long) width * height > 24000000L) {
                        throw new TicketException("Der Screenshot darf höchstens 24 Megapixel enthalten.");
                    }
                    var image = reader.read(0);
                    var output = new ByteArrayOutputStream();
                    if (!ImageIO.write(image, format, output) || output.size() > MAX_BYTES) {
                        throw new TicketException("Der aufbereitete Screenshot ist zu groß. Bitte das Bild verkleinern.");
                    }
                    String name = filename == null ? "Screenshot" : filename.replaceAll("[\\\\/\\p{Cntrl}]", "_");
                    if (name.length() > 180) name = name.substring(0, 180);
                    store.attach(actor, ticketId, name, format.equals("png") ? "image/png" : "image/jpeg", output.toByteArray());
                } finally { reader.dispose(); }
            }
        } catch (IOException | IllegalArgumentException ex) { throw invalidImage(); }
    }

    private static TicketException invalidImage() { return new TicketException("Bitte einen gültigen PNG- oder JPEG-Screenshot hochladen."); }
}
