package de.cachebox.website.features;

import java.nio.file.Path;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import static org.assertj.core.api.Assertions.*;

class WishVoteStoreTest {
    @TempDir Path directory;

    @Test
    void newRoundPreservesLegacyVotesAndPersistsItsOwnBallot() throws Exception {
        // Die Ids kommen aus dem Katalog, damit der Test nicht bricht, sobald ein Wunsch umgesetzt ist
        // und damit aus der Abstimmung fällt.
        List<String> open = WishCatalog.openWishes().stream().map(WishCatalog.Wish::id).toList();
        assertThat(open).hasSizeGreaterThanOrEqualTo(4);
        String first = open.get(0), second = open.get(1), third = open.get(2), fourth = open.get(3);
        Set<String> ballot = Set.of(first, second, third);
        String voter = UUID.randomUUID().toString();
        var store = new FeatureVoteStore(directory.toString());
        try {
            store.save(voter, Set.of("aufnahmen-01"));
            assertThat(store.wishChoices(voter)).isEmpty();
            assertThat(store.wishTotals()).isEmpty();
            store.saveWishes(voter, ballot);
            store.saveWishes(voter, ballot);
            assertThat(store.choices(voter)).containsExactly("aufnahmen-01");
            assertThat(store.totals()).containsExactly(entry("aufnahmen-01", 1L));
            assertThat(store.wishTotals()).hasSize(3).containsEntry(first, 1L);
            for (Set<String> invalid : List.of(Set.of(first, second, third, fourth),
                    Set.of("aufnahmen-01"), Set.of("unknown"))) {
                assertThatThrownBy(() -> store.saveWishes(voter, invalid)).isInstanceOf(IllegalArgumentException.class);
                assertThat(store.wishChoices(voter)).containsExactlyInAnyOrderElementsOf(ballot);
            }
        } finally { store.close(); }
        var reopened = new FeatureVoteStore(directory.toString());
        try {
            assertThat(reopened.wishChoices(voter)).containsExactlyInAnyOrderElementsOf(ballot);
            reopened.saveWishes(voter, Set.of(fourth));
            assertThat(reopened.wishTotals()).containsExactly(entry(fourth, 1L));
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
        assertThat(WishCatalog.openWishes()).isNotEmpty();
        for (var wish : WishCatalog.WISHES) {
            assertThat(features).containsAll(wish.featureIds());
            if (wish.openFeatures().isEmpty()) {
                // alle Funktionen gebaut: der Wunsch steht nicht mehr zur Wahl
                assertThat(WishCatalog.openIds()).doesNotContain(wish.id());
            } else {
                assertThat(wish.openFeatures()).noneMatch(FeatureCatalog.Feature::done);
                assertThat(WishCatalog.openIds()).contains(wish.id());
            }
        }
    }
}
