package de.cachebox.website.tickets;

import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;
import java.net.URI;
import java.net.http.HttpClient;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.*;
import static org.assertj.core.api.Assertions.*;

class GithubTicketClientTest {
    HttpServer server;
    GithubTicketClient client;
    final AtomicReference<String> authorization = new AtomicReference<>(), method = new AtomicReference<>(), body = new AtomicReference<>();
    final List<String> calls = new ArrayList<>();
    int status = 200;
    String response = issue(1);
    boolean pagination;

    @BeforeEach void setup() throws Exception {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", exchange -> {
            authorization.set(exchange.getRequestHeaders().getFirst("Authorization"));
            method.set(exchange.getRequestMethod());
            body.set(new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8));
            String path = exchange.getRequestURI().toString(); calls.add(path);
            String result = response;
            if (pagination) {
                if (path.endsWith("&page=1")) {
                    List<String> records = new ArrayList<>();
                    for (int i=1;i<=100;i++) records.add(i == 50 ? issue(i).replace("}", ",\"pull_request\":{} }") : issue(i));
                    result = "[" + String.join(",",records) + "]";
                } else result = "[" + issue(101) + "]";
            }
            byte[] bytes=result.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().add("Location","https://unrelated.example/never-send-a-token");
            exchange.sendResponseHeaders(status,bytes.length); exchange.getResponseBody().write(bytes); exchange.close();
        });
        server.start();
        var settings = new TicketSyncSettings(true,"test-token-do-not-log","https://website.example");
        client = new GithubTicketClient(settings,HttpClient.newHttpClient(),URI.create("http://127.0.0.1:"+server.getAddress().getPort()+"/"));
    }
    @AfterEach void close() { if(server != null) server.stop(0); }

    @Test void postsJsonOnlyToConfiguredRepositoryAndPatchesState() {
        var created=client.create("Ein Titel", "Beschreibung mit Umlauten: äöü");
        assertThat(created.number()).isEqualTo(1);
        assertThat(authorization.get()).isEqualTo("Bearer test-token-do-not-log");
        assertThat(method.get()).isEqualTo("POST");
        assertThat(calls).containsExactly("/repos/Longri/iCachebox/issues");
        assertThat(body.get()).contains("Beschreibung mit Umlauten: äöü").doesNotContain("test-token-do-not-log");
        client.update(1,"Änderung","Beschreibung",true);
        assertThat(method.get()).isEqualTo("PATCH");
        assertThat(body.get()).contains("\"state\":\"closed\"");
    }

    @Test void paginatesUsingRawPageSizeAndExcludesPullRequests() {
        pagination=true;
        var issues=client.issues();
        assertThat(issues).hasSize(100);
        assertThat(issues).extracting(GithubTicketClient.Issue::number).doesNotContain(50L).contains(101L);
        assertThat(calls).hasSize(2);
        assertThat(calls.get(1)).contains("page=2");
    }

    @Test void rejectsRedirectAndProviderErrorsWithoutLeakingProviderBodies() {
        for(int error:new int[]{302,401,403,429,500}) {
            status=error; response="sensitive-provider-body-test-token-do-not-log";
            assertThatThrownBy(() -> client.create("Titel","Beschreibung")).isInstanceOf(TicketException.class)
                    .hasMessageNotContaining("sensitive-provider-body").hasMessageNotContaining("test-token-do-not-log");
        }
        assertThat(calls).allSatisfy(call -> assertThat(call).startsWith("/repos/Longri/iCachebox/"));
    }

    private static String issue(int number) {
        return "{\"number\":"+number+",\"title\":\"Titel\",\"body\":\"Beschreibung\",\"state\":\"open\",\"labels\":[]}";
    }
}
