![Cachebox – too many secrets.](../docs/banner.jpg)

# iCachebox Website

Promotion-Website für [iCachebox](https://github.com/Longri/iCachebox) (Cachebox für iOS) – Java 21, Vaadin Flow 25, Spring Boot 4.

## Starten

```bash
cd Website && mvn
```

Danach http://localhost:8080 öffnen. Im Entwicklungsmodus wird kein Node.js benötigt.

Produktions-Build (lädt Node.js bei Bedarf automatisch nach `~/.vaadin`):

```bash
cd Website && mvn clean package -Pproduction && java -jar target/cachebox-website-1.0-SNAPSHOT.jar
```

## Aufbau

- `src/main/java/de/cachebox/website/MainLayout.java` – Kopfzeile, Navigation, Fußzeile
- `src/main/java/de/cachebox/website/views/` – eine Klasse pro Seite
  - `StartView` (`/`) – Logo „Cachebox – too many secrets." vor den Bäumen
  - `FeaturesView` (`/funktionen`), `MapsView` (`/karten`), `AboutView` (`/projekt`) – Karten über `Page.card(...)`
- `src/main/resources/META-INF/resources/styles/site.css` – gesamtes Styling inkl. Bäume-Hintergrund
- `src/main/resources/META-INF/resources/images/` – Bilder aus dem Cachebox-Repo
  (`SkinPacker/Icons/default/day/UI_IconPack`)

Neue Seite: View-Klasse mit `@Route(value = "...", layout = MainLayout.class)` anlegen, von `Page` erben
und in `MainLayout.createNav()` verlinken.
