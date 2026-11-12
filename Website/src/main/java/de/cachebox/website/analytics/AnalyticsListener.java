package de.cachebox.website.analytics;

import com.vaadin.flow.server.VaadinRequest;
import com.vaadin.flow.server.VaadinServiceInitListener;
import com.vaadin.flow.server.VaadinServletRequest;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class AnalyticsListener {
    private static final String COUNTED = AnalyticsListener.class.getName() + ".counted";

    @Bean
    VaadinServiceInitListener trackPublicNavigation(AnalyticsStore store, CountryLookup countries) {
        return event -> event.getSource().addUIInitListener(init -> {
            var request = VaadinRequest.getCurrent();
            if (!(request instanceof VaadinServletRequest servletRequest)) return;
            var http = servletRequest.getHttpServletRequest();
            var info = VisitorInfo.from(countries.country(http.getRemoteAddr(), http.getHeader("X-Forwarded-For")),
                    http.getHeader("Referer"), http.getServerName(), http.getHeader("User-Agent"));
            init.getUI().addAfterNavigationListener(navigation -> {
                String path = navigation.getLocation().getPath();
                if (!AnalyticsStore.PUBLIC_PATHS.contains(path)) return;
                var session = init.getUI().getSession();
                try {
                    boolean first = session.getAttribute(COUNTED) == null;
                    store.record(path, info, first);
                    session.setAttribute(COUNTED, Boolean.TRUE);
                } catch (java.sql.SQLException ex) {
                    // Statistikfehler dürfen die öffentliche Website nicht unterbrechen.
                    LoggerFactory.getLogger(AnalyticsListener.class).error("Aufrufstatistik konnte nicht gespeichert werden (SQLState {}).", ex.getSQLState());
                }
            });
        });
    }
}
