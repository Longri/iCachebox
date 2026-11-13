package de.cachebox.website.oauth;

import java.net.URI;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Arrays;
import java.util.Map;
import java.util.stream.Collectors;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.mock.web.MockHttpSession;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class GroundspeakAuthorizationTest {
    static final String CALLBACK = "https://cachebox.example/oauth/groundspeak/callback";
    static final Instant NOW = Instant.parse("2026-11-13T10:00:00Z");
    final GroundspeakSettings settings = new GroundspeakSettings("test-client", "test-secret", CALLBACK, false);
    final GroundspeakClient client = mock(GroundspeakClient.class);
    final Clock clock = Clock.fixed(NOW, ZoneOffset.UTC);
    final GroundspeakAuthorization authorization = new GroundspeakAuthorization(settings, client, clock);
    final MockHttpSession session = new MockHttpSession();

    @Test
    void authorizationUsesPkceAndKeepsTheSecretAndVerifierOnTheServer() {
        URI location = authorization.start(session);
        Map<String, String> params = parameters(location);
        assertThat(location.toString()).startsWith("https://www.geocaching.com/oauth/authorize.aspx?")
                .doesNotContain("test-secret", "code_verifier", "client_secret");
        assertThat(params).containsEntry("client_id", "test-client").containsEntry("response_type", "code")
                .containsEntry("scope", "*").containsEntry("redirect_uri", CALLBACK)
                .containsEntry("code_challenge_method", "S256");
        assertThat(params.get("state")).matches("[A-Za-z0-9_-]{43}");
        assertThat(params.get("code_challenge")).matches("[A-Za-z0-9_-]{43}");
        assertThat(GroundspeakAuthorization.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"))
                .isEqualTo("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"); // RFC 7636 Appendix B
    }

    @Test
    void validCallbackExchangesWithOriginalVerifierAndTransfersResultOnce() {
        Map<String, String> params = parameters(authorization.start(session));
        when(client.exchangeCode(eq("provider-code"), anyString()))
                .thenReturn(new GroundspeakClient.Tokens("personal-access", "personal-refresh", NOW.plusSeconds(3600)));
        authorization.complete(session, params.get("state"), "provider-code", null);
        var verifier = ArgumentCaptor.forClass(String.class);
        verify(client).exchangeCode(eq("provider-code"), verifier.capture());
        assertThat(GroundspeakAuthorization.challenge(verifier.getValue())).isEqualTo(params.get("code_challenge"));
        var result = authorization.takeResult(session);
        assertThat(result.accessToken()).isEqualTo("personal-access");
        assertThat(result.refreshToken()).isEqualTo("personal-refresh");
        assertThat(result.expiresAt()).isEqualTo(NOW.plusSeconds(3600));
        assertThat(result.error()).isNull();
        assertThat(authorization.takeResult(session)).isNull();
        assertThatThrownBy(() -> authorization.complete(session, params.get("state"), "provider-code", null))
                .isInstanceOf(GroundspeakException.class);
        verifyNoMoreInteractions(client);
    }

    @Test
    void wrongStateOtherBrowserAndExpiredAuthorizationNeverContactProvider() {
        String state = parameters(authorization.start(session)).get("state");
        assertThatThrownBy(() -> authorization.complete(session, "wrong-state", "code", null))
                .isInstanceOf(GroundspeakException.class);
        assertThatThrownBy(() -> authorization.complete(new MockHttpSession(), state, "code", null))
                .isInstanceOf(GroundspeakException.class);
        var later = new GroundspeakAuthorization(settings, client, Clock.offset(clock, Duration.ofMinutes(10)));
        assertThatThrownBy(() -> later.complete(session, state, "code", null)).isInstanceOf(GroundspeakException.class);
        verifyNoInteractions(client);
    }

    @Test
    void restartingReplacesEarlierAuthorizationAndDiscardsPreviousResult() {
        authorization.failure(session, "previous failure");
        String oldState = parameters(authorization.start(session)).get("state");
        String newState = parameters(authorization.start(session)).get("state");
        assertThat(newState).isNotEqualTo(oldState);
        assertThatThrownBy(() -> authorization.complete(session, oldState, "code", null))
                .isInstanceOf(GroundspeakException.class);
        assertThat(authorization.takeResult(session)).isNull();
        verifyNoInteractions(client);
    }

    @Test
    void denialAndMissingCodeConsumeAuthorizationWithoutSendingSecrets() {
        String state = parameters(authorization.start(session)).get("state");
        assertThatThrownBy(() -> authorization.complete(session, state, null, "untrusted-provider-message"))
                .isInstanceOf(GroundspeakException.class).hasMessageContaining("abgebrochen")
                .hasMessageNotContaining("untrusted-provider-message");
        assertThatThrownBy(() -> authorization.complete(session, state, "code", null))
                .isInstanceOf(GroundspeakException.class);
        String nextState = parameters(authorization.start(session)).get("state");
        assertThatThrownBy(() -> authorization.complete(session, nextState, "", null))
                .isInstanceOf(GroundspeakException.class).hasMessageContaining("keinen Autorisierungscode");
        verifyNoInteractions(client);
    }

    @Test
    void resultCannotBeCollectedAfterFiveMinutes() {
        authorization.failure(session, "test-error");
        var later = new GroundspeakAuthorization(settings, client, Clock.offset(clock, Duration.ofMinutes(5)));
        assertThat(later.takeResult(session)).isNull();
        assertThat(authorization.takeResult(session)).isNull();
    }

    @Test
    void missingConfigurationDisablesAuthorization() {
        var empty = new GroundspeakSettings("", "", "", false);
        assertThat(empty.configured()).isFalse();
        assertThatThrownBy(() -> new GroundspeakAuthorization(empty, client).start(session))
                .isInstanceOf(GroundspeakException.class).hasMessageContaining("nicht eingerichtet");
        verifyNoInteractions(client);
    }

    @Test
    void callbackMustBeFixedSecureAndHaveNoExtraParameters() {
        for (String invalid : new String[]{"https://cachebox.example/wrong", "http://cachebox.example/oauth/groundspeak/callback",
                "https://cachebox.example/oauth/groundspeak/callback?other=1", "https://cachebox.example/oauth/groundspeak/callback#fragment",
                "https://user:password@cachebox.example/oauth/groundspeak/callback", "http:callback", "malformed url"}) {
            assertThatThrownBy(() -> new GroundspeakSettings("key", "secret", invalid, false))
                    .isInstanceOf(IllegalArgumentException.class);
        }
        assertThat(new GroundspeakSettings("key", "secret", "http://localhost:8082/oauth/groundspeak/callback", true).configured()).isTrue();
        assertThat(new GroundspeakSettings("key", "secret", CALLBACK, true).tokenEndpoint().toString())
                .isEqualTo("https://oauth-staging.geocaching.com/token");
    }

    static Map<String, String> parameters(URI uri) {
        return Arrays.stream(uri.getRawQuery().split("&")).map(part -> part.split("=", 2))
                .collect(Collectors.toMap(p -> URLDecoder.decode(p[0], StandardCharsets.UTF_8),
                        p -> URLDecoder.decode(p[1], StandardCharsets.UTF_8)));
    }
}
