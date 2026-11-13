package de.cachebox.website.oauth;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.stream.Collectors;

final class OAuthParameters {
    private OAuthParameters() { }

    static String encode(String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8)
                .replace("+", "%20").replace("*", "%2A").replace("%7E", "~");
    }

    static String form(Map<String, String> parameters) {
        return parameters.entrySet().stream()
                .map(p -> encode(p.getKey()) + "=" + encode(p.getValue()))
                .sorted().collect(Collectors.joining("&"));
    }

}
