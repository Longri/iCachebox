package de.cachebox.website.tickets;

import java.net.URI;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class TicketSyncSettings {
    public static final String REPOSITORY = "Longri/iCachebox";
    final boolean enabled;
    final String token;
    final String websiteUrl;

    public TicketSyncSettings(@Value("${website.tickets.github.enabled:false}") boolean enabled,
            @Value("${website.tickets.github.token:}") String token,
            @Value("${website.tickets.public-url:}") String websiteUrl) {
        this.enabled = enabled;
        this.token = token;
        this.websiteUrl = websiteUrl.replaceAll("/+$", "");
        if (!this.websiteUrl.isBlank()) {
            try {
                URI uri = URI.create(this.websiteUrl);
                if (!"https".equals(uri.getScheme()) || uri.getHost() == null || uri.getUserInfo() != null
                        || uri.getQuery() != null || uri.getFragment() != null) throw new IllegalArgumentException();
            } catch (IllegalArgumentException ex) {
                throw new IllegalArgumentException("TICKETS_PUBLIC_URL muss die öffentliche HTTPS-Adresse der Website enthalten.");
            }
        }
    }

    public boolean configured() { return enabled && !token.isBlank(); }
}
