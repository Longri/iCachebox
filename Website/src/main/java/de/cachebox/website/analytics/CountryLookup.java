package de.cachebox.website.analytics;

import com.maxmind.geoip2.DatabaseReader;
import jakarta.annotation.PreDestroy;
import java.io.File;
import java.io.IOException;
import java.net.InetAddress;
import java.util.Arrays;
import java.util.Set;
import java.util.stream.Collectors;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class CountryLookup implements AutoCloseable {
    private final DatabaseReader reader;
    private final Set<String> trustedProxies;

    public CountryLookup(@Value("${website.analytics.geoip-database:}") String database,
                         @Value("${website.analytics.trusted-proxies:}") String proxies) throws IOException {
        trustedProxies = Arrays.stream(proxies.split(",")).map(String::trim).filter(s -> !s.isEmpty())
                .map(value -> {
                    String ip = normalize(value);
                    if (ip.isEmpty()) throw new IllegalArgumentException("ANALYTICS_TRUSTED_PROXIES erwartet numerische IP-Adressen.");
                    return ip;
                }).collect(Collectors.toUnmodifiableSet());
        // Ein explizit konfigurierter, aber falscher Pfad ist ein Konfigurationsfehler.
        reader = database.isBlank() ? null : new DatabaseReader.Builder(new File(database)).build();
        if (reader == null) LoggerFactory.getLogger(getClass()).info("Keine GeoIP-Datenbank: Länder werden als unbekannt erfasst.");
    }

    public boolean available() { return reader != null; }

    public String country(String remoteAddress, String forwardedFor) {
        if (reader == null) return "ZZ";
        String address = clientAddress(remoteAddress, forwardedFor);
        try {
            InetAddress ip = literal(address);
            return reader.tryCountry(ip).map(result -> result.country().isoCode()).filter(s -> s != null).orElse("ZZ");
        } catch (Exception ignored) {
            return "ZZ";
        }
    }

    String clientAddress(String remoteAddress, String forwardedFor) {
        String address = normalize(remoteAddress);
        // Von rechts laufen: vom direkten Proxy bis zur ersten nicht vertrauten Adresse.
        if (forwardedFor != null && trustedProxies.contains(address)) {
            String[] chain = forwardedFor.split(",");
            if (chain.length > 20) return "";
            for (int i = chain.length - 1; i >= 0 && trustedProxies.contains(address); i--) {
                address = normalize(chain[i].trim());
            }
        }
        return address;
    }

    private static InetAddress literal(String address) throws IOException {
        // Vor getByName nur numerische IPs akzeptieren: niemals DNS für Besucher-Header.
        if (address == null || !address.matches("[0-9a-fA-F:.]+")) throw new IOException("Keine IP-Adresse");
        return InetAddress.getByName(address);
    }

    private static String normalize(String address) {
        try { return literal(address).getHostAddress(); }
        catch (IOException ignored) { return ""; }
    }

    @PreDestroy
    public void close() throws IOException { if (reader != null) reader.close(); }
}
