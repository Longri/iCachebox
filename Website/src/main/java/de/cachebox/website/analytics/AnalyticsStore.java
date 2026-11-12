package de.cachebox.website.analytics;

import jakarta.annotation.PreDestroy;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/** Tagesaggregate, keine Einzelereignisse. Ein Prozess besitzt die eingebettete Datenbank. */
@Service
public class AnalyticsStore {
    public static final ZoneId ZONE = ZoneId.of("Europe/Berlin");
    public static final Set<String> PUBLIC_PATHS = Set.of("", "funktionen", "coming-soon", "karten", "anleitung", "projekt");
    private static final Set<String> DIMENSIONS = Set.of("visit_day", "page", "country", "referrer", "device");
    private final Connection connection;
    private LocalDate lastPruned;

    public AnalyticsStore(@Value("${website.analytics.directory:./data}") String directory) throws Exception {
        Path path = Path.of(directory).toAbsolutePath().normalize();
        Files.createDirectories(path);
        connection = DriverManager.getConnection("jdbc:h2:file:" + path.resolve("analytics") + ";DB_CLOSE_ON_EXIT=FALSE", "sa", "");
        try (var statement = connection.createStatement()) {
            statement.execute("""
                    CREATE TABLE IF NOT EXISTS daily_stats (
                        visit_day DATE NOT NULL, page VARCHAR(40) NOT NULL, country VARCHAR(2) NOT NULL,
                        referrer VARCHAR(180) NOT NULL, device VARCHAR(20) NOT NULL, bot BOOLEAN NOT NULL,
                        views BIGINT NOT NULL, visits BIGINT NOT NULL,
                        PRIMARY KEY (visit_day, page, country, referrer, device, bot))
                    """);
        }
        prune(LocalDate.now(ZONE));
    }

    public synchronized void record(String path, VisitorInfo info, boolean firstInSession) throws SQLException {
        record(LocalDate.now(ZONE), path, info, firstInSession);
    }

    synchronized void record(LocalDate day, String path, VisitorInfo info, boolean firstInSession) throws SQLException {
        if (!PUBLIC_PATHS.contains(path)) return;
        prune(LocalDate.now(ZONE));
        try (var statement = connection.prepareStatement("""
                MERGE INTO daily_stats AS target
                USING (VALUES (CAST(? AS DATE), ?, ?, ?, ?, CAST(? AS BOOLEAN), CAST(? AS BIGINT)))
                    AS source(visit_day, page, country, referrer, device, bot, visits)
                ON target.visit_day=source.visit_day AND target.page=source.page AND target.country=source.country
                    AND target.referrer=source.referrer AND target.device=source.device AND target.bot=source.bot
                WHEN MATCHED THEN UPDATE SET views=target.views+1, visits=target.visits+source.visits
                WHEN NOT MATCHED THEN INSERT VALUES
                    (source.visit_day, source.page, source.country, source.referrer, source.device, source.bot, 1, source.visits)
                """)) {
            statement.setObject(1, day);
            statement.setString(2, path.isEmpty() ? "/" : "/" + path);
            statement.setString(3, info.country());
            statement.setString(4, info.referrer());
            statement.setString(5, info.device());
            statement.setBoolean(6, info.bot());
            statement.setLong(7, firstInSession ? 1 : 0);
            statement.executeUpdate();
        }
    }

    public synchronized List<Count> counts(String dimension, LocalDate from, LocalDate to, boolean includeBots) throws SQLException {
        if (!DIMENSIONS.contains(dimension)) throw new IllegalArgumentException("Ungültige Auswertung");
        prune(LocalDate.now(ZONE));
        String sql = "SELECT " + dimension + ", SUM(views), SUM(visits) FROM daily_stats WHERE visit_day BETWEEN ? AND ?"
                + (includeBots ? "" : " AND bot=FALSE") + " GROUP BY " + dimension
                + (dimension.equals("visit_day") ? " ORDER BY 1" : " ORDER BY 2 DESC, 1 LIMIT 100");
        List<Count> counts = new ArrayList<>();
        try (var statement = connection.prepareStatement(sql)) {
            statement.setObject(1, from);
            statement.setObject(2, to);
            try (var rows = statement.executeQuery()) {
                while (rows.next()) counts.add(new Count(rows.getString(1), rows.getLong(2), rows.getLong(3)));
            }
        }
        return counts;
    }

    private void prune(LocalDate today) throws SQLException {
        if (today.equals(lastPruned)) return;
        try (var statement = connection.prepareStatement("DELETE FROM daily_stats WHERE visit_day < ?")) {
            statement.setObject(1, today.minusDays(399));
            statement.executeUpdate();
        }
        lastPruned = today;
    }

    public record Count(String label, long views, long visits) { }

    @PreDestroy
    public synchronized void close() throws SQLException { connection.close(); }
}
