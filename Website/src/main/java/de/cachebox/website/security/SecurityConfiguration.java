package de.cachebox.website.security;

import com.vaadin.flow.spring.security.VaadinSecurityConfigurer;
import de.cachebox.website.views.LoginView;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
@EnableWebSecurity
public class SecurityConfiguration {
    @Bean
    SecurityFilterChain securityFilterChain(HttpSecurity http, AdminLoginState state,
            @Value("${website.admin.remember-me-days:14}") int rememberMeDays) throws Exception {
        // Secrets and statistics must never be served as static resources.
        http.authorizeHttpRequests(auth -> auth
                .requestMatchers("/.env", "/.env/**", "/data/**").denyAll()
                .requestMatchers("/styles/**", "/images/**", "/anleitung/bilder/**").permitAll());
        http.with(VaadinSecurityConfigurer.vaadin(), config -> config.loginView(LoginView.class).defaultSuccessUrl("/admin"));
        http.rememberMe(remember -> remember.key(state.rememberMeKey())
                .tokenValiditySeconds(rememberMeSeconds(rememberMeDays)).useSecureCookie(true));
        return http.build();
    }

    static int rememberMeSeconds(int days) {
        if (days < 1 || days > Integer.MAX_VALUE / 86400) {
            throw new IllegalArgumentException("ADMIN_REMEMBER_ME_DAYS muss zwischen 1 und 24855 liegen.");
        }
        return days * 86400;
    }

    @Bean
    AdminLoginState adminLoginState(@Value("${website.admin.username:}") String username,
                                   @Value("${website.admin.password:}") String password,
                                   @Value("${website.analytics.directory:./data}") String directory) throws java.io.IOException {
        return AdminLoginState.load(username, password, directory);
    }

    @Bean
    UserDetailsService adminUsers(@Value("${website.admin.username:}") String username, AdminLoginState state) {
        var users = new InMemoryUserDetailsManager();
        if (state.passwordHash().isEmpty()) {
            LoggerFactory.getLogger(getClass()).warn("Admin-Zugang deaktiviert: ADMIN_USER und ADMIN_PASSWORD fehlen oder sind unvollständig.");
            return users;
        }
        users.createUser(User.withUsername(username).password(state.passwordHash()).roles("ADMIN").build());
        return users;
    }
}
