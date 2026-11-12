package de.cachebox.website.analytics;

import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;

class VisitorInfoTest {
    @Test
    void storesOnlyReferrerHostAndCoarseDeviceCategory() {
        assertThat(VisitorInfo.from("DE", "https://user:secret@Search.Example/path?token=private#secret", "cachebox.de", "Mozilla iPhone Mobile"))
                .isEqualTo(new VisitorInfo("DE", "search.example", "Smartphone", false));
        assertThat(VisitorInfo.from(null, "https://cachebox.de/private?token=secret", "cachebox.de", "Googlebot").referrer()).isEqualTo("Intern");
        assertThat(VisitorInfo.from(null, "javascript:alert(1)", "cachebox.de", "Googlebot").bot()).isTrue();
        assertThat(VisitorInfo.from(null, "invalid", "cachebox.de", null)).isEqualTo(new VisitorInfo("ZZ", "Direkt / unbekannt", "Unbekannt", false));
    }

    @Test
    void ignoresForwardingFromUntrustedClientsAndWalksTrustedChainFromRight() throws Exception {
        try (var countries = new CountryLookup("", "127.0.0.1, ::1, 10.0.0.2")) {
            assertThat(countries.clientAddress("203.0.113.1", "1.2.3.4")).isEqualTo("203.0.113.1");
            assertThat(countries.clientAddress("127.0.0.1", "1.2.3.4, 203.0.113.1, 10.0.0.2")).isEqualTo("203.0.113.1");
            assertThat(countries.clientAddress("::1", "203.0.113.1")).isEqualTo("203.0.113.1");
            assertThat(countries.clientAddress("127.0.0.1", "attacker.example")).isEmpty();
            assertThat(countries.country("127.0.0.1", "1.2.3.4")).isEqualTo("ZZ");
        }
    }
}
