package de.cachebox.website.security;

import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.security.crypto.factory.PasswordEncoderFactories;
import static org.assertj.core.api.Assertions.*;

class SecurityConfigurationTest {
    @TempDir Path directory;

    @Test
    void missingCredentialsDisableAdminWithoutDefaultAccount() throws Exception {
        var config = new SecurityConfiguration();
        var users = config.adminUsers("", AdminLoginState.load("", "", directory.toString()));
        assertThatThrownBy(() -> users.loadUserByUsername("admin")).isInstanceOf(UsernameNotFoundException.class);
        assertThatThrownBy(() -> AdminLoginState.load("owner", "123456789", directory.toString()))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void tenCharacterPasswordIsAcceptedHashedAndSurvivesRestart() throws Exception {
        var state = AdminLoginState.load("owner", "test-12345", directory.toString());
        var user = new SecurityConfiguration().adminUsers("owner", state).loadUserByUsername("owner");
        assertThat(user.getPassword()).doesNotContain("test-12345");
        assertThat(PasswordEncoderFactories.createDelegatingPasswordEncoder().matches("test-12345", user.getPassword())).isTrue();
        assertThat(user.getAuthorities()).extracting(Object::toString).containsExactly("ROLE_ADMIN");
        assertThat(AdminLoginState.load("owner", "test-12345", directory.toString())).isEqualTo(state);
        assertThat(Files.readString(directory.resolve("admin-login.properties"))).doesNotContain("test-12345");
        assertThat(AdminLoginState.load("owner", "changed-12345", directory.toString()).rememberMeKey()).isNotEqualTo(state.rememberMeKey());
    }

    @Test
    void rememberMeDurationAcceptsConfiguredDaysAndRejectsInvalidValues() {
        assertThat(SecurityConfiguration.rememberMeSeconds(14)).isEqualTo(1209600);
        assertThat(SecurityConfiguration.rememberMeSeconds(7)).isEqualTo(604800);
        assertThatThrownBy(() -> SecurityConfiguration.rememberMeSeconds(0)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> SecurityConfiguration.rememberMeSeconds(-1)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> SecurityConfiguration.rememberMeSeconds(24856)).isInstanceOf(IllegalArgumentException.class);
    }
}
