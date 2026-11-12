package de.cachebox.website.analytics;

import java.net.URI;
import java.util.Locale;

/** Nur diese groben Kategorien gelangen in die Statistik, keine IPs oder vollständigen URLs. */
public record VisitorInfo(String country, String referrer, String device, boolean bot) {
    public static VisitorInfo from(String country, String referer, String serverName, String userAgent) {
        String ua = userAgent == null ? "" : userAgent.toLowerCase(Locale.ROOT);
        boolean bot = ua.matches("(?s).*(bot|crawler|spider|headless|slurp|facebookexternalhit|preview).*");
        String device = ua.isBlank() ? "Unbekannt" : ua.contains("ipad") || ua.contains("tablet")
                || (ua.contains("android") && !ua.contains("mobile")) ? "Tablet"
                : ua.contains("mobile") || ua.contains("iphone") ? "Smartphone" : "Desktop";
        String source = "Direkt / unbekannt";
        if (referer != null) {
            try {
                URI uri = URI.create(referer);
                String host = uri.getHost();
                if (host != null && ("https".equalsIgnoreCase(uri.getScheme()) || "http".equalsIgnoreCase(uri.getScheme()))) {
                    source = host.equalsIgnoreCase(serverName) ? "Intern" : host.toLowerCase(Locale.ROOT);
                    if (source.length() > 180) source = "Andere";
                }
            } catch (IllegalArgumentException ignored) { /* ungültige Header nicht speichern */ }
        }
        return new VisitorInfo(country == null ? "ZZ" : country, source, device, bot);
    }
}
