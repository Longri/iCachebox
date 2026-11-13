package de.cachebox.website.oauth;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

@Component
public class GroundspeakClient {
    private static final int MAX_RESPONSE_BYTES = 65536;
    private final GroundspeakSettings settings;
    private final HttpClient http;
    private final URI endpoint;
    private final JsonMapper json = new JsonMapper();

    @Autowired
    public GroundspeakClient(GroundspeakSettings settings) {
        this(settings, HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10))
                .followRedirects(HttpClient.Redirect.NEVER).build(), settings.tokenEndpoint());
    }

    GroundspeakClient(GroundspeakSettings settings, HttpClient http, URI endpoint) {
        this.settings = settings;
        this.http = http;
        this.endpoint = endpoint;
    }

    Tokens exchangeCode(String code, String verifier) {
        var parameters = Map.of("client_id", settings.clientId, "client_secret", settings.clientSecret,
                "grant_type", "authorization_code", "redirect_uri", settings.redirectUri.toString(),
                "code", code, "code_verifier", verifier);
        HttpRequest request = HttpRequest.newBuilder(endpoint).timeout(Duration.ofSeconds(20))
                .header("Content-Type", "application/x-www-form-urlencoded")
                .header("Accept", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(OAuthParameters.form(parameters))).build();
        String body = send(request);
        try {
            JsonNode data = json.readTree(body);
            String access = requiredText(data, "access_token");
            String refresh = requiredText(data, "refresh_token");
            if (!"bearer".equalsIgnoreCase(requiredText(data, "token_type"))
                    || !data.path("expires_in").isIntegralNumber() || !data.path("expires_in").canConvertToLong()) {
                throw invalidResponse();
            }
            long seconds = data.path("expires_in").asLong();
            if (seconds <= 0 || seconds > 315360000L) throw invalidResponse();
            return new Tokens(access, refresh, Instant.now().plusSeconds(seconds));
        } catch (GroundspeakException ex) {
            throw ex;
        } catch (RuntimeException ex) {
            throw invalidResponse();
        }
    }

    private String send(HttpRequest request) {
        try {
            var response = http.send(request, HttpResponse.BodyHandlers.ofInputStream());
            try (var input = response.body()) {
                if (response.statusCode() != 200) {
                    throw new GroundspeakException("Geocaching.com hat die Autorisierung abgelehnt. "
                            + "Bitte erneut versuchen; falls der Fehler bleibt, muss die Serverkonfiguration geprüft werden.");
                }
                byte[] body = input.readNBytes(MAX_RESPONSE_BYTES + 1);
                if (body.length > MAX_RESPONSE_BYTES) throw invalidResponse();
                return new String(body, StandardCharsets.UTF_8);
            }
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            throw new GroundspeakException("Die Verbindung zu Geocaching.com wurde unterbrochen. Bitte erneut versuchen.");
        } catch (IOException ex) {
            throw new GroundspeakException("Geocaching.com ist gerade nicht erreichbar. Bitte später erneut versuchen.");
        }
    }

    private static String requiredText(JsonNode data, String name) {
        JsonNode node = data.path(name);
        if (!node.isString() || node.asString().isBlank()) throw invalidResponse();
        return node.asString();
    }

    private static GroundspeakException invalidResponse() {
        return new GroundspeakException("Geocaching.com hat keine gültigen Zugangsdaten zurückgegeben. Bitte erneut versuchen.");
    }

    // No generated toString(): these objects contain credentials.
    static final class Tokens {
        final String access;
        final String refresh;
        final Instant expiresAt;

        Tokens(String access, String refresh, Instant expiresAt) {
            this.access = access;
            this.refresh = refresh;
            this.expiresAt = expiresAt;
        }
    }
}
