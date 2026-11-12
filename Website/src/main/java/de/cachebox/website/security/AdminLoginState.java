package de.cachebox.website.security;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.Properties;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;

/** Stabiler BCrypt-Hash und zufälliger Cookie-Schlüssel, damit Remember-Me Neustarts übersteht. */
record AdminLoginState(String passwordHash, String rememberMeKey) {
    static AdminLoginState load(String username, String password, String directory) throws IOException {
        if (username.isBlank() || password.isBlank()) return new AdminLoginState("", randomKey());
        if (password.length() < 10 || password.getBytes(java.nio.charset.StandardCharsets.UTF_8).length > 72) {
            throw new IllegalArgumentException("ADMIN_PASSWORD muss mindestens 10 Zeichen und höchstens 72 UTF-8-Bytes lang sein.");
        }
        Path folder = Path.of(directory).toAbsolutePath().normalize();
        Files.createDirectories(folder);
        Path file = folder.resolve("admin-login.properties");
        Properties state = new Properties();
        if (Files.exists(file)) {
            try (var input = Files.newInputStream(file)) { state.load(input); }
        }
        var encoder = new BCryptPasswordEncoder(12);
        String hash = state.getProperty("passwordHash", "");
        String key = state.getProperty("rememberMeKey", "");
        boolean changed = false;
        if (hash.isBlank() || !encoder.matches(password, hash)) {
            hash = encoder.encode(password);
            key = randomKey(); // Passwortwechsel widerruft auch bisherige Cookie-Signaturen.
            changed = true;
        }
        if (key.isBlank()) { key = randomKey(); changed = true; }
        if (changed) {
            state.setProperty("passwordHash", hash);
            state.setProperty("rememberMeKey", key);
            // createTempFile verwendet auf POSIX-Systemen nur für den Eigentümer lesbare Rechte.
            Path temporary = Files.createTempFile(folder, "admin-login-", ".tmp");
            try {
                try (var output = Files.newOutputStream(temporary)) {
                    state.store(output, "Admin-Login: nur Hash und Cookie-Schluessel, kein Klartextpasswort");
                }
                Files.move(temporary, file, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
            } finally { Files.deleteIfExists(temporary); }
        }
        return new AdminLoginState("{bcrypt}" + hash, key);
    }

    private static String randomKey() {
        byte[] bytes = new byte[32];
        new SecureRandom().nextBytes(bytes);
        return Base64.getEncoder().encodeToString(bytes);
    }
}
