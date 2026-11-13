package de.cachebox.website.oauth;

import java.net.URI;
import java.time.Instant;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpSession;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class GroundspeakControllerTest {
    final GroundspeakClient client = mock(GroundspeakClient.class);
    final GroundspeakSettings settings = new GroundspeakSettings("test-client", "test-secret", GroundspeakAuthorizationTest.CALLBACK, false);
    final GroundspeakAuthorization authorization = new GroundspeakAuthorization(settings, client);
    final MockHttpSession session = new MockHttpSession();
    MockMvc mvc;

    @BeforeEach
    void setup() {
        mvc = MockMvcBuilders.standaloneSetup(new GroundspeakController(authorization)).build();
    }

    @Test
    void fullRoundTripRedirectsToCleanResultUrlAndDoesNotExposeTokensInHeaders() throws Exception {
        var start = mvc.perform(get("/oauth/groundspeak/start").session(session))
                .andExpect(status().isSeeOther()).andExpect(header().string("Cache-Control", "no-store"))
                .andReturn().getResponse();
        String state = GroundspeakAuthorizationTest.parameters(URI.create(start.getHeader("Location"))).get("state");
        when(client.exchangeCode(eq("provider-code"), anyString()))
                .thenReturn(new GroundspeakClient.Tokens("test-access", "test-refresh", Instant.now().plusSeconds(3599)));
        var response = mvc.perform(get("/oauth/groundspeak/callback").session(session)
                        .param("state", state).param("code", "provider-code"))
                .andExpect(status().isSeeOther()).andExpect(redirectedUrl("/api-key"))
                .andExpect(header().string("Cache-Control", "no-store"))
                .andExpect(header().string("Referrer-Policy", "no-referrer"))
                .andExpect(content().string("")).andReturn().getResponse();
        assertThat(response.getHeaderNames()).allSatisfy(name ->
                assertThat(response.getHeader(name)).doesNotContain("test-access", "test-refresh", "test-secret", "provider-code"));
        assertThat(authorization.takeResult(session).accessToken()).isEqualTo("test-access");
    }

    @Test
    void expiredSessionAndDuplicateParametersGiveReadableErrorsWithoutContactingProvider() throws Exception {
        mvc.perform(get("/oauth/groundspeak/callback").session(session).param("state", "missing-session").param("code", "code"))
                .andExpect(status().isSeeOther()).andExpect(redirectedUrl("/api-key"));
        assertThat(authorization.takeResult(session).error()).contains("abgelaufen");
        String state = GroundspeakAuthorizationTest.parameters(authorization.start(session)).get("state");
        mvc.perform(get("/oauth/groundspeak/callback").session(session).param("state", state).param("code", "one", "two"))
                .andExpect(status().isSeeOther()).andExpect(redirectedUrl("/api-key"));
        assertThat(authorization.takeResult(session).error()).contains("ungültig");
        verifyNoInteractions(client);
    }

    @Test
    void providerDenialAndNetworkFailuresReturnToTheView() throws Exception {
        String state = GroundspeakAuthorizationTest.parameters(authorization.start(session)).get("state");
        mvc.perform(get("/oauth/groundspeak/callback").session(session).param("state", state)
                        .param("error", "access_denied").param("error_description", "<script>untrusted</script>"))
                .andExpect(status().isSeeOther()).andExpect(redirectedUrl("/api-key"));
        assertThat(authorization.takeResult(session).error()).contains("abgebrochen").doesNotContain("<script>");
        String nextState = GroundspeakAuthorizationTest.parameters(authorization.start(session)).get("state");
        when(client.exchangeCode(anyString(), anyString())).thenThrow(new GroundspeakException("Geocaching.com ist gerade nicht erreichbar."));
        mvc.perform(get("/oauth/groundspeak/callback").session(session).param("state", nextState).param("code", "code"))
                .andExpect(status().isSeeOther()).andExpect(redirectedUrl("/api-key"));
        assertThat(authorization.takeResult(session).error()).contains("nicht erreichbar");
    }

    @Test
    void missingConfigurationReturnsToTheViewAndContextPathIsPreserved() throws Exception {
        var disabled = new GroundspeakAuthorization(new GroundspeakSettings("", "", "", false), client);
        var disabledMvc = MockMvcBuilders.standaloneSetup(new GroundspeakController(disabled)).build();
        disabledMvc.perform(get("/website/oauth/groundspeak/start").contextPath("/website").session(session))
                .andExpect(status().isSeeOther()).andExpect(redirectedUrl("/website/api-key"));
        assertThat(disabled.takeResult(session).error()).contains("nicht eingerichtet");
        verifyNoInteractions(client);
    }
}
