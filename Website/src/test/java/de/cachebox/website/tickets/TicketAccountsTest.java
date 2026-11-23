package de.cachebox.website.tickets;

import java.nio.file.Path;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.security.crypto.factory.PasswordEncoderFactories;
import static org.assertj.core.api.Assertions.*;

class TicketAccountsTest {
    @TempDir Path directory;
    TicketStore store;
    @AfterEach void close() throws Exception { if (store != null) store.close(); }

    @Test void passwordsAreHashedAccountsPersistAndNeverGainAdminRole() throws Exception {
        store = new TicketStore(directory.toString());
        var accounts = new TicketAccounts(store, "Longri");
        accounts.register("Test.User", "test-password-12345");
        var user = accounts.load("TEST.USER");
        assertThat(user.getUsername()).isEqualTo("test.user");
        assertThat(user.getAuthorities()).extracting(Object::toString).containsExactly("ROLE_USER");
        assertThat(user.getPassword()).startsWith("{bcrypt}").doesNotContain("test-password-12345");
        assertThat(PasswordEncoderFactories.createDelegatingPasswordEncoder().matches("test-password-12345", user.getPassword())).isTrue();
        store.close(); store = new TicketStore(directory.toString());
        assertThat(new TicketAccounts(store, "Longri").load("test.user").getPassword()).isEqualTo(user.getPassword());
        assertThatThrownBy(() -> new TicketAccounts(store, "Longri").register("test.user", "different-password-12345"))
                .isInstanceOf(TicketException.class).hasMessageContaining("vergeben");
    }

    @Test void adminIdentityReservedAndPasswordLimitsUseUtf8Bytes() throws Exception {
        store = new TicketStore(directory.toString());
        var accounts = new TicketAccounts(store, "Longri");
        for (String name : new String[]{"Longri", "LONGRI", "admin", "github", "a", "name<script>", "space name"}) {
            assertThatThrownBy(() -> accounts.register(name, "valid-password-12345")).isInstanceOf(TicketException.class);
        }
        assertThatThrownBy(() -> accounts.register("valid-user", "short")).isInstanceOf(TicketException.class);
        assertThatThrownBy(() -> accounts.register("valid-user", "ä".repeat(37))).isInstanceOf(TicketException.class);
    }
}
