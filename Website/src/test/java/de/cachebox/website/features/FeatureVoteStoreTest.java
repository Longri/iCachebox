package de.cachebox.website.features;

import java.nio.file.Path;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import static org.assertj.core.api.Assertions.*;

class FeatureVoteStoreTest {
    @TempDir Path directory;
    private static final String A = "aufnahmen-01";
    private static final String B = "aufnahmen-02";
    private static final String C = "aufnahmen-03";
    private static final String D = "aufnahmen-04";

    @Test
    void replacementIsIdempotentAndSurvivesRestart() throws Exception {
        String first = UUID.randomUUID().toString();
        String second = UUID.randomUUID().toString();
        var store = new FeatureVoteStore(directory.toString());
        try {
            assertThat(store.choices(first)).isEmpty();
            assertThat(store.totals()).isEmpty();
            store.save(first, Set.of(A, B, C));
            store.save(first, Set.of(A, B, C));
            store.save(second, Set.of(A));
            assertThat(store.totals()).containsEntry(A, 2L).containsEntry(B, 1L).containsEntry(C, 1L);
            store.save(first, Set.of(A, D));
            assertThat(store.totals()).containsOnlyKeys(A, D).containsEntry(A, 2L);
        } finally { store.close(); }
        store = new FeatureVoteStore(directory.toString());
        try {
            assertThat(store.choices(first)).containsExactlyInAnyOrder(A, D);
            assertThat(store.choices(second)).containsExactly(A);
            store.save(first, Set.of());
            assertThat(store.totals()).containsExactly(entry(A, 1L));
            assertThat(store.choices(first)).isEmpty();
        } finally { store.close(); }
    }

    @Test
    void rejectsMoreThanThreeUnknownAndCompletedFeaturesWithoutChangingExistingBallot() throws Exception {
        var store = new FeatureVoteStore(directory.toString());
        String voter = UUID.randomUUID().toString();
        try {
            store.save(voter, Set.of(A));
            for (var invalid : List.of(Set.of(A, B, C, D), Set.of("unknown"), Set.of("cacheliste-01"))) {
                assertThatThrownBy(() -> store.save(voter, invalid)).isInstanceOf(IllegalArgumentException.class);
                assertThat(store.choices(voter)).containsExactly(A);
                assertThat(store.totals()).containsExactly(entry(A, 1L));
            }
            assertThatThrownBy(() -> store.save("not-a-voter", Set.of(A)))
                    .isInstanceOf(IllegalArgumentException.class);
        } finally { store.close(); }
    }

    @Test
    void concurrentSubmissionsFromSameBrowserReplaceRatherThanAccumulate() throws Exception {
        var store = new FeatureVoteStore(directory.toString());
        String voter = UUID.randomUUID().toString();
        try (var pool = Executors.newFixedThreadPool(4)) {
            var calls = new java.util.ArrayList<java.util.concurrent.Future<?>>();
            for (int i = 0; i < 40; i++) {
                Set<String> ballot = i % 2 == 0 ? Set.of(A, B, C) : Set.of(D);
                calls.add(pool.submit(() -> {
                    try { store.save(voter, ballot); } catch (Exception ex) { throw new RuntimeException(ex); }
                }));
            }
            for (var call : calls) call.get(10, TimeUnit.SECONDS);
            assertThat(List.of(Set.of(A, B, C), Set.of(D))).contains(store.choices(voter));
            assertThat(store.totals().values()).allMatch(count -> count == 1L);
            assertThat(store.totals()).hasSize(store.choices(voter).size());
        } finally { store.close(); }
    }

    @Test
    void catalogIdsAreUniqueAndOpenSetContainsOnlyUnfinishedFunctions() {
        var all = FeatureCatalog.SECTIONS.stream().flatMap(section -> section.features().stream()).toList();
        assertThat(all).extracting(FeatureCatalog.Feature::id).doesNotHaveDuplicates();
        assertThat(FeatureCatalog.openIds()).contains(A).doesNotContain("cacheliste-01");
        assertThat(FeatureCatalog.SECTIONS.stream().filter(section -> section.title().equals("Fotos, Spoiler & Aufnahmen"))
                .findFirst().orElseThrow().features()).noneMatch(FeatureCatalog.Feature::done);
    }
}
