package de.cachebox.website.tickets;

import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.Set;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Service;

@Service
public class TicketAccounts {
    private final TicketStore store;
    private final String adminName;
    private final BCryptPasswordEncoder passwords = new BCryptPasswordEncoder(12);

    public TicketAccounts(TicketStore store, @Value("${website.admin.username:}") String adminName) {
        this.store = store;
        this.adminName = canonical(adminName);
    }

    public void register(String username, String password) {
        String name = canonical(username);
        if (!name.matches("[a-z0-9][a-z0-9._-]{2,39}") || name.equals(adminName)
                || Set.of("admin", "administrator", "system", "github", "anonymoususer").contains(name)) {
            throw new TicketException("Bitte einen verfügbaren Benutzernamen mit 3 bis 40 Zeichen verwenden: Buchstaben, Ziffern, Punkt, Unterstrich oder Bindestrich.");
        }
        if (password == null || password.length() < 10 || password.getBytes(StandardCharsets.UTF_8).length > 72) {
            throw new TicketException("Das Passwort muss mindestens zehn Zeichen und höchstens 72 UTF-8-Bytes lang sein.");
        }
        store.register(name, "{bcrypt}" + passwords.encode(password));
    }

    public UserDetails load(String username) {
        String name = canonical(username);
        // The configured admin identity is always reserved, including when temporarily disabled.
        if (name.equals(adminName)) throw new UsernameNotFoundException("Benutzer nicht verfügbar.");
        String hash = store.passwordHash(name);
        if (hash == null) throw new UsernameNotFoundException("Benutzer nicht verfügbar.");
        return User.withUsername(name).password(hash).roles("USER").build();
    }

    private static String canonical(String name) { return name == null ? "" : name.strip().toLowerCase(Locale.ROOT); }
}
