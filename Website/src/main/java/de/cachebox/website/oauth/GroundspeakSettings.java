package de.cachebox.website.oauth;

import java.net.URI;
import java.util.Set;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/** Partner credentials stay on the server, outside the source tree and browser. */
@Component
public class GroundspeakSettings {
    final String clientId;
    final String clientSecret;
    final URI redirectUri;
    final boolean staging;

    public GroundspeakSettings(@Value("${website.groundspeak.client-id:}") String clientId,
            @Value("${website.groundspeak.client-secret:}") String clientSecret,
            @Value("${website.groundspeak.redirect-uri:}") String redirectUri,
            @Value("${website.groundspeak.staging:false}") boolean staging) {
        this.clientId = clientId;
        this.clientSecret = clientSecret;
        this.staging = staging;
        this.redirectUri = redirectUri.isBlank() ? null : validateRedirectUri(redirectUri);
    }

    private static URI validateRedirectUri(String value) {
        URI uri;
        try {
            uri = URI.create(value);
        } catch (IllegalArgumentException ex) {
            throw new IllegalArgumentException("GROUNDSPEAK_REDIRECT_URI ist keine gültige URL.");
        }
        boolean https = "https".equals(uri.getScheme());
        boolean localHttp = "http".equals(uri.getScheme()) && uri.getHost() != null
                && Set.of("localhost", "127.0.0.1", "[::1]").contains(uri.getHost());
        if ((!https && !localHttp) || uri.getHost() == null || uri.getUserInfo() != null
                || uri.getRawQuery() != null || uri.getRawFragment() != null
                || !uri.getPath().endsWith("/oauth/groundspeak/callback")) {
            throw new IllegalArgumentException("GROUNDSPEAK_REDIRECT_URI muss eine HTTPS-Callback-URL "
                    + "mit /oauth/groundspeak/callback sein (HTTP nur auf localhost).");
        }
        return uri;
    }

    public boolean configured() {
        return !clientId.isBlank() && !clientSecret.isBlank() && redirectUri != null;
    }

    URI authorizeEndpoint() {
        return URI.create("https://" + (staging ? "staging" : "www") + ".geocaching.com/oauth/authorize.aspx");
    }

    URI tokenEndpoint() {
        return URI.create("https://oauth" + (staging ? "-staging" : "") + ".geocaching.com/token");
    }
}
