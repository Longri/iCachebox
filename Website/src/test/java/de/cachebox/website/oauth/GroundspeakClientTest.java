package de.cachebox.website.oauth;

import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;
import java.net.URI;
import java.net.http.HttpClient;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;

class GroundspeakClientTest {
    HttpServer server;
    URI endpoint;
    final AtomicReference<String> requestBody = new AtomicReference<>();
    final AtomicReference<String> contentType = new AtomicReference<>();
    final AtomicReference<String> method = new AtomicReference<>();
    final AtomicReference<String> query = new AtomicReference<>();
    String response = "{\"access_token\":\"test-access\",\"refresh_token\":\"test-refresh\",\"token_type\":\"bearer\",\"expires_in\":3599}";
    int status = 200;

    @BeforeEach
    void startProvider() throws Exception {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        endpoint = URI.create("http://127.0.0.1:" + server.getAddress().getPort() + "/token");
        server.createContext("/token", exchange -> {
            requestBody.set(new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8));
            method.set(exchange.getRequestMethod());
            query.set(exchange.getRequestURI().getRawQuery());
            contentType.set(exchange.getRequestHeaders().getFirst("Content-Type"));
            exchange.getResponseHeaders().add("Location", endpoint.resolve("/must-not-follow").toString());
            byte[] bytes = response.getBytes(StandardCharsets.UTF_8);
            exchange.sendResponseHeaders(status, bytes.length);
            exchange.getResponseBody().write(bytes);
            exchange.close();
        });
        server.start();
    }

    @AfterEach
    void stopProvider() { if (server != null) server.stop(0); }

    GroundspeakClient client() {
        return new GroundspeakClient(new GroundspeakSettings("client +&", "secret +&",
                GroundspeakAuthorizationTest.CALLBACK, false), HttpClient.newHttpClient(), endpoint);
    }

    @Test
    void sendsFormPostAndParsesBothTokensAndExpiry() {
        Instant before = Instant.now();
        var tokens = client().exchangeCode("code +&", "verifier +&");
        assertThat(method.get()).isEqualTo("POST");
        assertThat(query.get()).isNull();
        assertThat(contentType.get()).isEqualTo("application/x-www-form-urlencoded");
        var parameters = GroundspeakAuthorizationTest.parameters(URI.create("https://test.example/?" + requestBody.get()));
        assertThat(parameters).containsEntry("client_id", "client +&").containsEntry("client_secret", "secret +&")
                .containsEntry("grant_type", "authorization_code").containsEntry("code", "code +&")
                .containsEntry("code_verifier", "verifier +&").containsEntry("redirect_uri", GroundspeakAuthorizationTest.CALLBACK);
        assertThat(tokens.access).isEqualTo("test-access");
        assertThat(tokens.refresh).isEqualTo("test-refresh");
        assertThat(tokens.expiresAt).isBetween(before.plusSeconds(3599), Instant.now().plusSeconds(3599));
    }

    @Test
    void rejectsProviderFailuresWithoutRevealingResponseSecrets() {
        status = 400;
        response = "provider-error-with-secret +& and authorization-code";
        assertThatThrownBy(() -> client().exchangeCode("authorization-code", "verifier"))
                .isInstanceOf(GroundspeakException.class).hasMessageContaining("abgelehnt")
                .hasMessageNotContaining("secret").hasMessageNotContaining("authorization-code");
    }

    @Test
    void rejectsRedirectInsteadOfForwardingPartnerCredentials() {
        status = 302;
        assertThatThrownBy(() -> client().exchangeCode("code", "verifier"))
                .isInstanceOf(GroundspeakException.class).hasMessageContaining("abgelehnt");
    }

    @Test
    void rejectsMalformedIncompleteAndOversizedResponses() {
        for (String invalid : new String[]{"not json", "null", "{}", "{\"access_token\":\"test-access\"}",
                response.replace("3599", "0"), response.replace("3599", "\"3599\""),
                response.replace("bearer", "unknown"), response.replace("test-refresh", ""), "x".repeat(65537)}) {
            response = invalid;
            assertThatThrownBy(() -> client().exchangeCode("code", "verifier"))
                    .isInstanceOf(GroundspeakException.class).hasMessageContaining("keine gültigen Zugangsdaten");
        }
    }
}
