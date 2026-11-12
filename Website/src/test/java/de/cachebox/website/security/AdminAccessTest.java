package de.cachebox.website.security;

import de.cachebox.website.Application;
import java.nio.file.Files;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestBuilders.*;
import static org.springframework.security.test.web.servlet.response.SecurityMockMvcResultMatchers.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest(classes = Application.class, properties = {
        "website.admin.username=test-owner", "website.admin.password=test-password-only-12345",
        "website.analytics.geoip-database=", "vaadin.productionMode=true", "spring.config.import="
})
class AdminAccessTest {
    @Autowired WebApplicationContext context;
    MockMvc mvc;

    @DynamicPropertySource
    static void storage(DynamicPropertyRegistry registry) throws Exception {
        var path = Files.createTempDirectory("website-security-test-");
        registry.add("website.analytics.directory", path::toString);
    }

    @BeforeEach
    void setup() {
        // MockMvc prüft die Filterkette; der echte Vaadin-Servlet wird im Browser geprüft.
        ((org.springframework.mock.web.MockServletContext) context.getServletContext()).registerNamedDispatcher(
                "springServlet", new org.springframework.mock.web.MockRequestDispatcher("springServlet"));
        mvc = MockMvcBuilders.webAppContextSetup(context).apply(springSecurity()).build();
    }

    @Test
    void adminRequiresLoginAndSecretsAreDenied() throws Exception {
        mvc.perform(get("/admin")).andExpect(status().is3xxRedirection()).andExpect(redirectedUrl("/login"));
        mvc.perform(get("/.env")).andExpect(status().is3xxRedirection());
        mvc.perform(get("/data/analytics.mv.db")).andExpect(status().is3xxRedirection());
        mvc.perform(get("/.env").with(user("test-owner").roles("ADMIN"))).andExpect(status().isForbidden());
        mvc.perform(get("/data/analytics.mv.db").with(user("test-owner").roles("ADMIN"))).andExpect(status().isForbidden());
    }

    @Test
    void publicAssetsPassSecurityFilter() throws Exception {
        mvc.perform(get("/styles/site.css")).andExpect(status().isOk());
        mvc.perform(get("/images/cb-ios.png")).andExpect(status().isOk());
    }

    @Test
    void invalidCredentialsFailAndConfiguredCredentialsWork() throws Exception {
        mvc.perform(formLogin().user("test-owner").password("wrong")).andExpect(unauthenticated());
        var result = mvc.perform(formLogin().user("test-owner").password("test-password-only-12345"))
                .andExpect(authenticated().withRoles("ADMIN")).andExpect(redirectedUrl("/admin")).andReturn();
        var session = (org.springframework.mock.web.MockHttpSession) result.getRequest().getSession(false);
        mvc.perform(post("/logout").with(csrf()).session(session)).andExpect(unauthenticated());
    }

    @Test
    void rememberMeIsOptionalRestoresAuthenticationAndIsClearedOnLogout() throws Exception {
        mvc.perform(formLogin().user("test-owner").password("test-password-only-12345"))
                .andExpect(cookie().doesNotExist("remember-me"));
        var result = mvc.perform(post("/login").secure(true).with(csrf())
                        .param("username", "test-owner").param("password", "test-password-only-12345")
                        .param("remember-me", "true"))
                .andExpect(authenticated().withRoles("ADMIN"))
                .andExpect(cookie().maxAge("remember-me", 14 * 86400))
                .andExpect(cookie().httpOnly("remember-me", true))
                .andExpect(cookie().secure("remember-me", true)).andReturn();
        var remembered = result.getResponse().getCookie("remember-me");
        // Nur das Cookie, keine alte Sitzung: simuliert Browser-Neustart/Sitzungsablauf.
        mvc.perform(get("/styles/site.css").secure(true).cookie(remembered))
                .andExpect(authenticated().withRoles("ADMIN"));
        mvc.perform(post("/logout").secure(true).with(csrf()).cookie(remembered))
                .andExpect(unauthenticated()).andExpect(cookie().maxAge("remember-me", 0));
        var invalid = new jakarta.servlet.http.Cookie("remember-me", "invalid-cookie");
        mvc.perform(get("/admin").secure(true).cookie(invalid)).andExpect(unauthenticated())
                .andExpect(status().is3xxRedirection());
    }

}
