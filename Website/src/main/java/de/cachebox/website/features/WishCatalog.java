package de.cachebox.website.features;

import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

/** Eigenständige Abstimmungsrunde: Paket-IDs sind keine umgedeuteten Einzelstimmen. */
public final class WishCatalog {
    private WishCatalog() { }

    public record Wish(String id, String title, String benefit, List<String> featureIds) {
        public List<FeatureCatalog.Feature> openFeatures() {
            return FeatureCatalog.SECTIONS.stream().flatMap(section -> section.features().stream())
                    .filter(feature -> !feature.done() && featureIds.contains(feature.id())).toList();
        }
    }

    public static final List<Wish> WISHES = List.of(
            new Wish("offline", "Touren offline vorbereiten",
                    "Beschreibungs- und Spoilerbilder vorab laden und unterwegs ansehen.",
                    List.of("cacheliste-22", "aufnahmen-01", "aufnahmen-02")),
            new Wish("multis", "Multis besser bearbeiten",
                    "Stationen und eigene Wegpunkte anlegen, bearbeiten und als Navigationsziel wählen.",
                    List.of("cache-details-10", "cache-details-11", "cache-details-17", "navigation-09")),
            new Wish("mysteries", "Mysteries lösen",
                    "Formeln und Variablen berechnen und Ergebnisse als Wegpunkt übernehmen.",
                    List.of("solver-01", "solver-02")),
            new Wish("trackables", "Trackables verwalten",
                    "Travelbugs und Coins suchen, im Inventar behalten und loggen.",
                    List.of("trackables-01", "trackables-02", "trackables-03")),
            new Wish("tracks", "Touren aufzeichnen",
                    "Den eigenen Weg aufzeichnen und GPX-Tracks auf der Karte nutzen.",
                    List.of("tracks-01", "tracks-02", "tracks-03", "tracks-04")),
            new Wish("filters", "Caches gezielter auswählen",
                    "Mit zusätzlichen Filtern und gespeicherten Vorlagen passende Caches finden.",
                    List.of("cacheliste-07", "cacheliste-10", "cacheliste-12")),
            new Wish("maps", "Mehr Möglichkeiten auf der Karte",
                    "Online-Karten und weitere Kartenquellen nutzen und Orte suchen.",
                    List.of("karte-02", "karte-03", "karte-06", "karte-07", "karte-10", "karte-26")),
            new Wish("navigation", "Unterwegs leichter navigieren",
                    "Zum Parkplatz zurückfinden, die Navigations-App wählen und Annäherungstöne nutzen.",
                    List.of("navigation-11", "navigation-12", "navigation-13", "karte-24", "karte-28")),
            new Wish("logging", "Logs komfortabler schreiben",
                    "Schnellentwürfe, Textvorlagen und Bilder für persönliche Logs nutzen.",
                    List.of("loggen-03", "loggen-04", "loggen-05")),
            new Wish("data", "Cache-Daten austauschen",
                    "GPX exportieren und bestehende Cachebox- oder GSAK-Datenbanken übernehmen.",
                    List.of("cacheliste-19", "cacheliste-20", "cacheliste-21")));

    public static List<Wish> openWishes() {
        return WISHES.stream().filter(wish -> !wish.openFeatures().isEmpty()).toList();
    }

    public static Set<String> openIds() {
        return openWishes().stream().map(Wish::id).collect(Collectors.toUnmodifiableSet());
    }
}
