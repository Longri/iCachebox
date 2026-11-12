package de.cachebox.website.security;

import java.nio.file.Path;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.web.authentication.rememberme.TokenBasedRememberMeServices;
import static org.assertj.core.api.Assertions.*;

class RememberMeRestartTest {
    @TempDir Path directory;

    @Test
    void cookieSurvivesRestartButNotExpiryOrPasswordChange() throws Exception {
        var initial = AdminLoginState.load("owner", "test-12345", directory.toString());
        var users = new SecurityConfiguration().adminUsers("owner", initial);
        var user = users.loadUserByUsername("owner");
        var service = new TokenBasedRememberMeServices(initial.rememberMeKey(), users);
        service.setTokenValiditySeconds(SecurityConfiguration.rememberMeSeconds(7));
        var login = new MockHttpServletRequest();
        login.setParameter("remember-me", "true");
        var response = new MockHttpServletResponse();
        service.loginSuccess(login, response, UsernamePasswordAuthenticationToken.authenticated(user, null, user.getAuthorities()));
        var cookie = response.getCookie("remember-me");
        assertThat(cookie).isNotNull();
        assertThat(cookie.getMaxAge()).isEqualTo(7 * 86400);
        var nextRequest = new MockHttpServletRequest();
        nextRequest.setCookies(cookie);

        var restarted = AdminLoginState.load("owner", "test-12345", directory.toString());
        var afterRestart = new TokenBasedRememberMeServices(restarted.rememberMeKey(), new SecurityConfiguration().adminUsers("owner", restarted));
        assertThat(afterRestart.autoLogin(nextRequest, new MockHttpServletResponse())).isNotNull();
        var changed = AdminLoginState.load("owner", "new-pass-12345", directory.toString());
        var afterPasswordChange = new TokenBasedRememberMeServices(changed.rememberMeKey(), new SecurityConfiguration().adminUsers("owner", changed));
        assertThat(afterPasswordChange.autoLogin(nextRequest, new MockHttpServletResponse())).isNull();

        String[] fields = new String(Base64.getDecoder().decode(cookie.getValue()), StandardCharsets.UTF_8).split(":");
        fields[1] = "1";
        cookie.setValue(Base64.getEncoder().encodeToString(String.join(":", fields).getBytes(StandardCharsets.UTF_8)));
        assertThat(afterRestart.autoLogin(nextRequest, new MockHttpServletResponse())).isNull();
    }
}
