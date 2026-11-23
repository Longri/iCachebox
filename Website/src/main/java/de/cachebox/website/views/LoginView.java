package de.cachebox.website.views;

import com.vaadin.flow.component.html.Div;
import com.vaadin.flow.component.checkbox.Checkbox;
import org.springframework.beans.factory.annotation.Value;
import com.vaadin.flow.component.html.H1;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.login.LoginForm;
import com.vaadin.flow.component.login.LoginI18n;
import com.vaadin.flow.router.BeforeEnterEvent;
import com.vaadin.flow.router.BeforeEnterObserver;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import com.vaadin.flow.server.auth.AnonymousAllowed;
import de.cachebox.website.MainLayout;
import com.vaadin.flow.router.RouterLink;

@Route(value = "login", layout = MainLayout.class)
@PageTitle("Anmelden | iCachebox")
@AnonymousAllowed
public class LoginView extends Div implements BeforeEnterObserver {
    private final LoginForm login = new LoginForm();

    public LoginView(@Value("${website.admin.remember-me-days:14}") int rememberMeDays) {
        addClassName("page");
        var i18n = LoginI18n.createDefault();
        i18n.getForm().setTitle("Dein iCachebox-Konto");
        i18n.getForm().setUsername("Benutzername");
        i18n.getForm().setPassword("Passwort");
        i18n.getForm().setSubmit("Anmelden");
        i18n.getErrorMessage().setTitle("Anmeldung fehlgeschlagen");
        i18n.getErrorMessage().setMessage("Bitte Benutzername und Passwort prüfen.");
        login.setI18n(i18n);
        login.setAction("login");
        login.setForgotPasswordButtonVisible(false);
        Checkbox rememberMe = new Checkbox(rememberMeDays + " Tage angemeldet bleiben");
        rememberMe.getElement().setAttribute("slot", "custom-form-area");
        rememberMe.getElement().setAttribute("name", "remember-me");
        rememberMe.getElement().setProperty("value", "true");
        login.getElement().appendChild(rememberMe.getElement());
        add(new H1("Anmelden"), new Paragraph("Melde dich für deine Tickets oder den Adminbereich an."), login,
                new RouterLink("Noch kein Konto? Registrieren", RegisterView.class));
    }

    @Override
    public void beforeEnter(BeforeEnterEvent event) {
        login.setError(event.getLocation().getQueryParameters().getParameters().containsKey("error"));
        if (event.getLocation().getQueryParameters().getParameters().containsKey("registered")) {
            addComponentAtIndex(1, new Paragraph("Dein Konto wurde erstellt. Du kannst dich jetzt anmelden."));
        }
    }
}
