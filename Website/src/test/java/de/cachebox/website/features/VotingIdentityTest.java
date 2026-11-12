package de.cachebox.website.features;

import com.vaadin.flow.server.VaadinRequest;
import com.vaadin.flow.server.VaadinResponse;
import com.vaadin.flow.server.VaadinSession;
import com.vaadin.flow.internal.CurrentInstance;
import jakarta.servlet.http.Cookie;
import java.util.HashMap;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

class VotingIdentityTest {
    @AfterEach void cleanup() { CurrentInstance.clearAll(); }

    @Test
    void browserCookieRestoresIdentityWithoutSession() {
        String id = UUID.randomUUID().toString();
        var request = mock(VaadinRequest.class);
        var response = mock(VaadinResponse.class);
        var session = mock(VaadinSession.class);
        when(request.getCookies()).thenReturn(new Cookie[]{new Cookie(VotingIdentity.COOKIE, id)});
        CurrentInstance.set(VaadinRequest.class, request);
        CurrentInstance.set(VaadinResponse.class, response);
        CurrentInstance.set(VaadinSession.class, session);
        assertThat(VotingIdentity.current()).isEqualTo(id);
        verify(session).setAttribute(VotingIdentity.COOKIE, id);
        verifyNoInteractions(response);
    }

    @Test
    void newBrowserGetsCookieAndSameSessionReusesIdentity() {
        var request = mock(VaadinRequest.class);
        var response = mock(VaadinResponse.class);
        var session = mock(VaadinSession.class);
        var attributes = new HashMap<String, Object>();
        when(request.getContextPath()).thenReturn("");
        when(request.isSecure()).thenReturn(true);
        when(session.getAttribute(anyString())).thenAnswer(call -> attributes.get(call.getArgument(0)));
        doAnswer(call -> { attributes.put(call.getArgument(0), call.getArgument(1)); return null; })
                .when(session).setAttribute(anyString(), any());
        CurrentInstance.set(VaadinRequest.class, request);
        CurrentInstance.set(VaadinResponse.class, response);
        CurrentInstance.set(VaadinSession.class, session);
        String id = VotingIdentity.current();
        assertThat(UUID.fromString(id).toString()).isEqualTo(id);
        assertThat(VotingIdentity.current()).isEqualTo(id);
        var cookie = ArgumentCaptor.forClass(Cookie.class);
        verify(response, times(2)).addCookie(cookie.capture());
        assertThat(cookie.getValue().getMaxAge()).isEqualTo(365 * 86400);
        assertThat(cookie.getValue().getPath()).isEqualTo("/");
        assertThat(cookie.getValue().isHttpOnly()).isTrue();
        assertThat(cookie.getValue().getSecure()).isTrue();
        assertThat(cookie.getValue().getAttribute("SameSite")).isEqualTo("Lax");
    }

    @Test
    void malformedAndUnrelatedCookiesAreIgnored() {
        assertThat(VotingIdentity.fromCookies(null)).isNull();
        assertThat(VotingIdentity.fromCookies(new Cookie[]{new Cookie("other", "something")})).isNull();
        assertThat(VotingIdentity.fromCookies(new Cookie[]{new Cookie(VotingIdentity.COOKIE, "invalid")})).isNull();
    }
}
