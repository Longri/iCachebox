package de.cachebox.website.oauth;

import jakarta.servlet.http.HttpSession;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

/** One short-lived authorization per browser session; no credentials in cookies or persistent storage. */
@Service
public class GroundspeakAuthorization {
    private static final String PENDING = GroundspeakAuthorization.class.getName() + ".pending";
    private static final String RESULT = GroundspeakAuthorization.class.getName() + ".result";
    private static final SecureRandom RANDOM = new SecureRandom();
    private final GroundspeakSettings settings;
    private final GroundspeakClient client;
    private final Clock clock;

    @Autowired
    public GroundspeakAuthorization(GroundspeakSettings settings, GroundspeakClient client) {
        this(settings, client, Clock.systemUTC());
    }

    GroundspeakAuthorization(GroundspeakSettings settings, GroundspeakClient client, Clock clock) {
        this.settings = settings;
        this.client = client;
        this.clock = clock;
    }

    public URI start(HttpSession session) {
        if (!settings.configured()) {
            throw new GroundspeakException("Der Geocaching-Zugang ist auf diesem Server noch nicht eingerichtet.");
        }
        String state = randomValue();
        String verifier = randomValue();
        synchronized (session) {
            session.removeAttribute(RESULT);
            session.setAttribute(PENDING, new Pending(state, verifier, clock.instant()));
        }
        return URI.create(settings.authorizeEndpoint() + "?" + OAuthParameters.form(Map.of(
                "client_id", settings.clientId, "response_type", "code", "scope", "*",
                "redirect_uri", settings.redirectUri.toString(), "state", state,
                "code_challenge", challenge(verifier), "code_challenge_method", "S256")));
    }

    public void complete(HttpSession session, String state, String code, String error) {
        Pending pending;
        synchronized (session) {
            pending = (Pending) session.getAttribute(PENDING);
            if (pending == null || expired(pending.createdAt, Duration.ofMinutes(10))
                    || state == null || !MessageDigest.isEqual(pending.state.getBytes(StandardCharsets.UTF_8),
                            state.getBytes(StandardCharsets.UTF_8))) {
                throw new GroundspeakException("Die Anmeldung ist abgelaufen oder gehört zu einer anderen Browsersitzung. "
                        + "Bitte die Anmeldung hier erneut starten.");
            }
            // Claim before contacting the provider, so concurrent/repeated callbacks cannot reuse a code.
            session.removeAttribute(PENDING);
        }
        if (error != null) {
            throw new GroundspeakException("Die Freigabe bei Geocaching.com wurde abgebrochen oder abgelehnt. "
                    + "Du kannst die Anmeldung erneut starten.");
        }
        if (code == null || code.isBlank()) {
            throw new GroundspeakException("Geocaching.com hat keinen Autorisierungscode zurückgegeben. Bitte erneut starten.");
        }
        var tokens = client.exchangeCode(code, pending.verifier);
        session.setAttribute(RESULT, new Result(tokens.access, tokens.refresh, tokens.expiresAt, null, clock.instant()));
    }

    public void failure(HttpSession session, String message) {
        session.setAttribute(RESULT, new Result(null, null, null, message, clock.instant()));
    }

    /** A result is transferred once to the Vaadin UI, never via a redirect URL. */
    public Result takeResult(HttpSession session) {
        if (session == null) return null;
        synchronized (session) {
            Result result = (Result) session.getAttribute(RESULT);
            session.removeAttribute(RESULT);
            return result == null || expired(result.createdAt, Duration.ofMinutes(5)) ? null : result;
        }
    }

    private boolean expired(Instant createdAt, Duration lifetime) {
        Instant now = clock.instant();
        return createdAt.isAfter(now) || !createdAt.plus(lifetime).isAfter(now);
    }

    static String randomValue() {
        byte[] bytes = new byte[32];
        RANDOM.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    static String challenge(String verifier) {
        try {
            return Base64.getUrlEncoder().withoutPadding().encodeToString(
                    MessageDigest.getInstance("SHA-256").digest(verifier.getBytes(StandardCharsets.US_ASCII)));
        } catch (NoSuchAlgorithmException ex) {
            throw new IllegalStateException("SHA-256 nicht verfügbar.");
        }
    }

    private static final class Pending {
        final String state;
        final String verifier;
        final Instant createdAt;

        Pending(String state, String verifier, Instant createdAt) {
            this.state = state;
            this.verifier = verifier;
            this.createdAt = createdAt;
        }
    }

    public static final class Result {
        private final String accessToken;
        private final String refreshToken;
        private final Instant expiresAt;
        private final String error;
        private final Instant createdAt;

        Result(String accessToken, String refreshToken, Instant expiresAt, String error, Instant createdAt) {
            this.accessToken = accessToken;
            this.refreshToken = refreshToken;
            this.expiresAt = expiresAt;
            this.error = error;
            this.createdAt = createdAt;
        }

        public String accessToken() { return accessToken; }
        public String refreshToken() { return refreshToken; }
        public Instant expiresAt() { return expiresAt; }
        public String error() { return error; }
    }
}
