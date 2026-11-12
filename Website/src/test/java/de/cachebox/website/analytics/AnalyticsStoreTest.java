package de.cachebox.website.analytics;

import java.nio.file.Path;
import java.time.LocalDate;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import static org.assertj.core.api.Assertions.*;

class AnalyticsStoreTest {
    @TempDir Path directory;
    private final VisitorInfo visitor = new VisitorInfo("DE", "example.org", "Desktop", false);

    @Test
    void aggregatesOnlyPublicNavigationAndSurvivesRestart() throws Exception {
        LocalDate day = LocalDate.now(AnalyticsStore.ZONE);
        var store = new AnalyticsStore(directory.toString());
        try {
            store.record("", visitor, true);
            store.record("", visitor, false);
            store.record("karten", visitor, false);
            store.record("admin", visitor, true);
            store.record("login", visitor, true);
            store.record("images/cb.png", visitor, true);
            store.record("karten", new VisitorInfo("US", "Direkt / unbekannt", "Desktop", true), true);
            assertThat(store.counts("page", day, day, false)).containsExactly(
                    new AnalyticsStore.Count("/", 2, 1), new AnalyticsStore.Count("/karten", 1, 0));
            assertThat(store.counts("visit_day", day, day, true)).containsExactly(new AnalyticsStore.Count(day.toString(), 4, 2));
            assertThat(store.counts("visit_day", day.minusDays(2), day.minusDays(1), true)).isEmpty();
            assertThatThrownBy(() -> store.counts("views; DROP TABLE daily_stats", day, day, true)).isInstanceOf(IllegalArgumentException.class);
            store.record(day.minusDays(401), "", visitor, true);
        } finally { store.close(); }
        var reopened = new AnalyticsStore(directory.toString());
        try {
            assertThat(reopened.counts("country", day.minusDays(500), day, false)).containsExactly(new AnalyticsStore.Count("DE", 3, 1));
        } finally { reopened.close(); }
    }

    @Test
    void concurrentSessionsDoNotLoseIncrements() throws Exception {
        var store = new AnalyticsStore(directory.toString());
        try (var executor = Executors.newFixedThreadPool(4)) {
            var futures = new java.util.ArrayList<java.util.concurrent.Future<?>>();
            for (int i = 0; i < 100; i++) futures.add(executor.submit(() -> {
                try { store.record("", visitor, true); } catch (Exception e) { throw new RuntimeException(e); }
            }));
            for (var future : futures) future.get(10, TimeUnit.SECONDS);
            var day = LocalDate.now(AnalyticsStore.ZONE);
            assertThat(store.counts("page", day, day, false)).containsExactly(new AnalyticsStore.Count("/", 100, 100));
        } finally { store.close(); }
    }
}
