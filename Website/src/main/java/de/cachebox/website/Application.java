package de.cachebox.website;

import com.vaadin.flow.component.page.AppShellConfigurator;
import com.vaadin.flow.component.page.Viewport;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Einstiegspunkt der Cachebox-Website. Start: {@code mvn} (oder {@code mvn spring-boot:run}),
 * danach http://localhost:8080
 */
@SpringBootApplication
@Viewport("width=device-width, initial-scale=1")
public class Application implements AppShellConfigurator {

    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }
}
