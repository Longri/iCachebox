package de.cachebox.website.features;

import jakarta.annotation.PreDestroy;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.Collection;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/** Ein änderbarer Stimmzettel mit höchstens drei gleichwertigen Stimmen je Browserkennung. */
@Service
public class FeatureVoteStore {
    public static final int MAX_CHOICES = 3;
    private final Connection connection;

    public FeatureVoteStore(@Value("${website.analytics.directory:./data}") String directory) throws Exception {
        Path path = Path.of(directory).toAbsolutePath().normalize();
        Files.createDirectories(path);
        connection = DriverManager.getConnection("jdbc:h2:file:" + path.resolve("feature-votes")
                + ";DB_CLOSE_ON_EXIT=FALSE", "sa", "");
        try (var statement = connection.createStatement()) {
            statement.execute("""
                    CREATE TABLE IF NOT EXISTS feature_votes (
                        voter_id VARCHAR(36) NOT NULL,
                        feature_id VARCHAR(80) NOT NULL,
                        PRIMARY KEY (voter_id, feature_id))
                    """);
            statement.execute("""
                    CREATE TABLE IF NOT EXISTS wish_votes (
                        voter_id VARCHAR(36) NOT NULL,
                        feature_id VARCHAR(80) NOT NULL,
                        PRIMARY KEY (voter_id, feature_id))
                    """);
        }
    }

    public synchronized Set<String> wishChoices(String voter) throws SQLException {
        return choices(voter, "wish_votes", WishCatalog.openIds());
    }

    public synchronized Map<String, Long> wishTotals() throws SQLException {
        return totals("wish_votes", WishCatalog.openIds());
    }

    public synchronized void saveWishes(String voter, Collection<String> choices) throws SQLException {
        save(voter, choices, "wish_votes", WishCatalog.openIds());
    }

    public synchronized Set<String> choices(String voter) throws SQLException {
        return choices(voter, "feature_votes", FeatureCatalog.openIds());
    }

    private Set<String> choices(String voter, String table, Set<String> open) throws SQLException {
        validateVoter(voter);
        Set<String> result = new HashSet<>();
        try (var query = connection.prepareStatement("SELECT feature_id FROM " + table + " WHERE voter_id=?")) {
            query.setString(1, voter);
            try (var rows = query.executeQuery()) {
                while (rows.next()) result.add(rows.getString(1));
            }
        }
        result.retainAll(open);
        return Set.copyOf(result);
    }

    public synchronized Map<String, Long> totals() throws SQLException {
        return totals("feature_votes", FeatureCatalog.openIds());
    }

    private Map<String, Long> totals(String table, Set<String> open) throws SQLException {
        Map<String, Long> result = new HashMap<>();
        try (var query = connection.createStatement();
             var rows = query.executeQuery("SELECT feature_id, COUNT(*) FROM " + table + " GROUP BY feature_id")) {
            while (rows.next()) {
                String id = rows.getString(1);
                if (open.contains(id)) result.put(id, rows.getLong(2));
            }
        }
        return Map.copyOf(result);
    }

    public synchronized void save(String voter, Collection<String> choices) throws SQLException {
        save(voter, choices, "feature_votes", FeatureCatalog.openIds());
    }

    // table wird ausschließlich durch die festen Tabellennamen der öffentlichen Methoden bestimmt.
    private void save(String voter, Collection<String> choices, String table, Set<String> open) throws SQLException {
        validateVoter(voter);
        Set<String> unique = Set.copyOf(choices);
        if (unique.size() > MAX_CHOICES || !open.containsAll(unique)) {
            throw new IllegalArgumentException("Bitte höchstens drei offene Funktionen auswählen.");
        }
        connection.setAutoCommit(false);
        try {
            try (var delete = connection.prepareStatement("DELETE FROM " + table + " WHERE voter_id=?")) {
                delete.setString(1, voter);
                delete.executeUpdate();
            }
            try (var insert = connection.prepareStatement("INSERT INTO " + table + " VALUES (?, ?)")) {
                for (String feature : unique) {
                    insert.setString(1, voter);
                    insert.setString(2, feature);
                    insert.addBatch();
                }
                insert.executeBatch();
            }
            connection.commit();
        } catch (SQLException ex) {
            connection.rollback();
            throw ex;
        } finally {
            connection.setAutoCommit(true);
        }
    }

    private static void validateVoter(String voter) {
        if (voter == null || !UUID.fromString(voter).toString().equals(voter)) {
            throw new IllegalArgumentException("Ungültige Browserkennung.");
        }
    }

    @PreDestroy
    public synchronized void close() throws SQLException {
        connection.close();
    }
}
