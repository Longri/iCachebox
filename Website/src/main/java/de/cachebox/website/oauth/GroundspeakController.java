package de.cachebox.website.oauth;

import jakarta.servlet.http.HttpServletRequest;
import java.net.URI;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.util.MultiValueMap;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;

/** Ordinary HTTP callbacks: independent of a Vaadin UI, including after a full-page redirect. */
@Controller
public class GroundspeakController {
    private final GroundspeakAuthorization authorization;

    public GroundspeakController(GroundspeakAuthorization authorization) {
        this.authorization = authorization;
    }

    @GetMapping("/oauth/groundspeak/start")
    ResponseEntity<Void> start(HttpServletRequest request) {
        try {
            return redirect(authorization.start(request.getSession()));
        } catch (GroundspeakException ex) {
            authorization.failure(request.getSession(), ex.getMessage());
            return redirect(resultUri(request));
        }
    }

    @GetMapping("/oauth/groundspeak/callback")
    ResponseEntity<Void> callback(HttpServletRequest request, @RequestParam MultiValueMap<String, String> parameters) {
        var session = request.getSession();
        try {
            authorization.complete(session, single(parameters, "state"), single(parameters, "code"), single(parameters, "error"));
        } catch (GroundspeakException ex) {
            authorization.failure(session, ex.getMessage());
        }
        // Immediately remove the provider's authorization code from the address bar.
        return redirect(resultUri(request));
    }

    private static String single(MultiValueMap<String, String> parameters, String name) {
        var values = parameters.get(name);
        if (values == null) return null;
        if (values.size() != 1 || values.getFirst().length() > 16384) {
            throw new GroundspeakException("Die Antwort von Geocaching.com ist ungültig. Bitte die Anmeldung erneut starten.");
        }
        return values.getFirst();
    }

    private static URI resultUri(HttpServletRequest request) {
        return URI.create(request.getContextPath() + "/api-key");
    }

    private static ResponseEntity<Void> redirect(URI target) {
        return ResponseEntity.status(303).location(target).cacheControl(CacheControl.noStore())
                .header("Pragma", "no-cache").header("Referrer-Policy", "no-referrer").build();
    }
}
