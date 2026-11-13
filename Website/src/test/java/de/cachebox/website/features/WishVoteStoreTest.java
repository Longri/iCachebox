package de.cachebox.website.features;

import java.nio.file.Path;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import static org.assertj.core.api.Assertions.*;

class WishVoteStoreTest {
    @TempDir Path directory;

    @Test
    void newRoundPreservesLegacyVotesAndPersistsItsOwnBallot() throws Exception {
        String voter = UUID.randomUUID().toString();
        var store = new FeatureVoteStore(directory.toString());
        try {
            store.save(voter, Set.of("aufnahmen-01"));
            assertThat(store.wishChoices(voter)).isEmpty();
            assertThat(store.wishTotals()).isEmpty();
            store.saveWishes(voter, Set.of("offline", "multis", "maps"));
            store.saveWishes(voter, Set.of("offline", "multis", "maps"));
            assertThat(store.choices(voter)).containsExactly("aufnahmen-01");
            assertThat(store.totals()).containsExactly(entry("aufnahmen-01", 1L));
            assertThat(store.wishTotals()).hasSize(3).containsEntry("offline", 1L);
            for (Set<String> invalid : java.util.List.of(Set.of("offline", "multis", "maps", "tracks"),
                    Set.of("aufnahmen-01"), Set.of("unknown"))) {
                assertThatThrownBy(() -> store.saveWishes(voter, invalid)).isInstanceOf(IllegalArgumentException.class);
                assertThat(store.wishChoices(voter)).containsExactlyInAnyOrder("offline", "multis", "maps");
            }
        } finally { store.close(); }
        var reopened = new FeatureVoteStore(directory.toString());
        try {
            assertThat(reopened.wishChoices(voter)).containsExactlyInAnyOrder("offline", "multis", "maps");
            reopened.saveWishes(voter, Set.of("tracks"));
            assertThat(reopened.wishTotals()).containsExactly(entry("tracks", 1L));
            reopened.saveWishes(voter, Set.of());
            assertThat(reopened.wishTotals()).isEmpty();
            assertThat(reopened.choices(voter)).containsExactly("aufnahmen-01");
        } finally { reopened.close(); }
    }

    @Test
    void allPackagesHaveUniqueIdsAndReferenceExistingUnfinishedFeatures() {
        assertThat(WishCatalog.WISHES).hasSize(10).extracting(WishCatalog.Wish::id).doesNotHaveDuplicates();
        var features = FeatureCatalog.SECTIONS.stream().flatMap(section -> section.features().stream())
                .map(FeatureCatalog.Feature::id).collect(java.util.stream.Collectors.toSet());
        for (var wish : WishCatalog.WISHES) {
            assertThat(features).containsAll(wish.featureIds());
            assertThat(wish.openFeatures()).isNotEmpty().noneMatch(FeatureCatalog.Feature::done);
        }
    }
}
