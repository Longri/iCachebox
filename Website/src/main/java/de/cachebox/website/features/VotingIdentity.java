package de.cachebox.website.features;

import com.vaadin.flow.server.VaadinRequest;
import com.vaadin.flow.server.VaadinResponse;
import com.vaadin.flow.server.VaadinSession;
import jakarta.servlet.http.Cookie;
import java.util.UUID;

/** Zufällige Browserkennung nur für die Abstimmung, ohne Konto oder IP-Adresse. */
public final class VotingIdentity {
    static final String COOKIE = "cachebox-feature-voter";
    private VotingIdentity() { }

    public static String current() {
        var request = VaadinRequest.getCurrent();
        var session = VaadinSession.getCurrent();
        String voter = fromCookies(request.getCookies());
        if (voter != null) {
            session.setAttribute(COOKIE, voter);
            return voter;
        }
        voter = (String) session.getAttribute(COOKIE);
        if (voter == null) voter = UUID.randomUUID().toString();
        Cookie cookie = new Cookie(COOKIE, voter);
        cookie.setHttpOnly(true);
        cookie.setSecure(request.isSecure());
        cookie.setAttribute("SameSite", "Lax");
        cookie.setPath(request.getContextPath().isEmpty() ? "/" : request.getContextPath());
        cookie.setMaxAge(365 * 86400);
        VaadinResponse.getCurrent().addCookie(cookie);
        session.setAttribute(COOKIE, voter);
        return voter;
    }

    static String fromCookies(Cookie[] cookies) {
        if (cookies == null) return null;
        for (Cookie cookie : cookies) {
            if (!COOKIE.equals(cookie.getName())) continue;
            try {
                String value = cookie.getValue();
                if (UUID.fromString(value).toString().equals(value)) return value;
            } catch (IllegalArgumentException ignored) {
                // Ungültige Werte werden durch eine neue Kennung ersetzt.
            }
        }
        return null;
    }
}
