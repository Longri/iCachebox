package de.cachebox.website.views;

import com.vaadin.flow.component.checkbox.Checkbox;
import com.vaadin.flow.component.html.Div;
import com.vaadin.flow.component.html.Span;
import com.vaadin.flow.server.auth.AnonymousAllowed;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import com.vaadin.flow.router.RouterLink;
import de.cachebox.website.MainLayout;
import de.cachebox.website.features.FeatureCatalog;
import de.cachebox.website.features.FeatureCatalog.Feature;
import java.util.Arrays;

@AnonymousAllowed
@Route(value = "funktionen", layout = MainLayout.class)
@PageTitle("Funktionen – iCachebox")
public class FeaturesView extends Page {

    public FeaturesView() {
        super("Was iCachebox kann",
                "iCachebox ist dein Werkzeugkasten für die Dosensuche: Alles, was du unterwegs brauchst, "
                        + "liegt auf dem Gerät – auch dort, wo es kein Netz gibt. "
                        + "Die Checklisten zählen die Funktionen von Cachebox für Android auf; abgehakt ist, "
                        + "was iCachebox schon kann (Stand: 12. November 2026).");

        addClassName("features");
        RouterLink vote = new RouterLink("Für die nächsten Funktionspakete abstimmen →", ComingSoonView.class);
        vote.addClassName("button");
        addComponentAtIndex(2, vote);
        for (var section : FeatureCatalog.SECTIONS) {
            Div card = card(section.icon(), section.title(), section.description(),
                    checklist(section.features().toArray(Feature[]::new)));
            if (section.features().stream().allMatch(feature -> !feature.done())) comingSoon(card);
            if (section.features().stream().anyMatch(Feature::done)) card.add(manual());
        }
    }

    /** Checkliste der Cachebox-Funktionen, abgehakt = in iCachebox umgesetzt; darüber „x von y umgesetzt“. */
    private static Div checklist(Feature... features) {
        Div list = new Div();
        list.addClassName("feature-checklist");
        long doneCount = Arrays.stream(features).filter(Feature::done).count();
        Span count = new Span(doneCount + " von " + features.length + " umgesetzt");
        count.addClassName("feature-count");
        list.add(count);
        for (Feature feature : features) {
            Checkbox checkbox = new Checkbox(feature.text());
            checkbox.setValue(feature.done());
            checkbox.setReadOnly(true);
            list.add(checkbox);
        }
        return list;
    }

    private static RouterLink manual() {
        return new RouterLink("Zur Anleitung", ManualView.class);
    }
}
