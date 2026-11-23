package de.cachebox.website.tickets;

import de.cachebox.website.tickets.TicketModels.Kind;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

@Component
public class GithubTicketClient {
    private final TicketSyncSettings settings;
    private final HttpClient http;
    private final URI api;
    private final JsonMapper json = new JsonMapper();

    @Autowired
    public GithubTicketClient(TicketSyncSettings settings) {
        this(settings, HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10))
                .followRedirects(HttpClient.Redirect.NEVER).build(), URI.create("https://api.github.com/"));
    }

    GithubTicketClient(TicketSyncSettings settings, HttpClient http, URI api) {
        this.settings = settings; this.http = http; this.api = api;
    }

    void checkConnection() { request("GET", repoPath(), null); }

    List<Issue> issues() {
        List<Issue> issues = new ArrayList<>();
        for (JsonNode node : pages(repoPath() + "/issues?state=all&sort=created&direction=asc")) {
            if (!node.has("pull_request")) issues.add(issue(node));
        }
        return issues;
    }

    Issue create(String title, String body) { return issue(request("POST", repoPath() + "/issues", Map.of("title", title, "body", body))); }
    Issue update(long number, String title, String body, boolean closed) {
        return issue(request("PATCH", repoPath() + "/issues/" + number,
                Map.of("title", title, "body", body, "state", closed ? "closed" : "open")));
    }

    List<Comment> comments(long number) {
        return pages(repoPath() + "/issues/" + number + "/comments?sort=created").stream().map(this::comment).toList();
    }

    Comment comment(long number, String body) {
        return comment(request("POST", repoPath() + "/issues/" + number + "/comments", Map.of("body", body)));
    }

    private List<JsonNode> pages(String path) {
        List<JsonNode> result = new ArrayList<>();
        for (int page = 1; page <= 100; page++) {
            JsonNode data = request("GET", path + "&per_page=100&page=" + page, null);
            if (!data.isArray()) throw invalidResponse();
            data.forEach(result::add);
            if (data.size() < 100) return result;
        }
        throw new TicketException("GitHub enthält mehr Einträge als ein vollständiger Abgleich verarbeiten kann. Es wurden keine unvollständigen Listen übernommen.");
    }

    private JsonNode request(String method, String path, Map<String, ?> data) {
        if (!settings.configured()) throw new TicketException("Die GitHub-Synchronisation ist auf dem Server noch nicht eingerichtet.");
        var request = HttpRequest.newBuilder(api.resolve(path)).timeout(Duration.ofSeconds(20))
                .header("Authorization", "Bearer " + settings.token).header("Accept", "application/vnd.github+json")
                .header("X-GitHub-Api-Version", "2026-03-10").header("User-Agent", "iCachebox-Website-Tickets");
        if (data == null) request.GET();
        else request.header("Content-Type", "application/json").method(method, HttpRequest.BodyPublishers.ofString(json.writeValueAsString(data)));
        try {
            var response = http.send(request.build(), HttpResponse.BodyHandlers.ofInputStream());
            try (var input = response.body()) {
                if (response.statusCode() == 403 || response.statusCode() == 429) {
                    throw new TicketException("GitHub hat den Zugriff begrenzt oder die Tokenberechtigung reicht nicht aus. Bitte später erneut versuchen und die Serverkonfiguration prüfen.");
                }
                if (response.statusCode() < 200 || response.statusCode() >= 300) {
                    throw new TicketException("GitHub-Abgleich fehlgeschlagen (HTTP " + response.statusCode() + "). Die lokalen Tickets bleiben gespeichert.");
                }
                byte[] bytes = input.readNBytes(4 * 1024 * 1024 + 1);
                if (bytes.length > 4 * 1024 * 1024) throw invalidResponse();
                try { return json.readTree(new String(bytes, StandardCharsets.UTF_8)); }
                catch (RuntimeException ex) { throw invalidResponse(); }
            }
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt(); throw new TicketException("Der GitHub-Abgleich wurde unterbrochen.");
        } catch (IOException ex) { throw new TicketException("GitHub ist gerade nicht erreichbar. Die lokalen Tickets bleiben gespeichert."); }
    }

    private Issue issue(JsonNode n) {
        String title = n.path("title").asString("");
        long number = n.path("number").asLong(0);
        if (number <= 0 || title.isBlank() || title.length() > 1024) throw invalidResponse();
        Kind kind = Kind.FEATURE;
        for (var label : n.path("labels")) if ("bug".equals(label.path("name").asString())) kind = Kind.BUG;
        return new Issue(number, title, n.path("body").asString(""), "closed".equals(n.path("state").asString()), kind);
    }

    private Comment comment(JsonNode n) {
        try {
            long id = n.path("id").asLong(0);
            if (id <= 0) throw invalidResponse();
            return new Comment(id, n.path("body").asString(""), n.path("user").path("login").asString("gelöscht"),
                    Instant.parse(n.path("created_at").asString()));
        } catch (RuntimeException ex) { throw invalidResponse(); }
    }

    private static String repoPath() { return "repos/" + TicketSyncSettings.REPOSITORY; }
    private static TicketException invalidResponse() { return new TicketException("GitHub hat eine unvollständige oder ungültige Antwort geliefert."); }
    record Issue(long number, String title, String body, boolean closed, Kind kind) { }
    record Comment(long id, String body, String author, Instant createdAt) { }
}
