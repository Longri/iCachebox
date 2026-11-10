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

## Auf den Server bringen

```bash
Website/deploy.sh            # bauen, hochladen, Cachebox.service neu starten
Website/deploy.sh --dry-run  # nur bauen und den Server prüfen, nichts ändern
```

Baut die Produktions-Jar, benennt sie in `target/cachebox-website.jar` um, lädt sie per SSH nach
`root@167.235.237.115:/Vaadin/iCacheboxWeb` (erst als `.upload`, der Dienst läuft so lange weiter), stoppt
`Cachebox.service`, sichert die alte Jar als `cachebox-website.jar.bak`, setzt die neue ein und startet den Dienst.
Ziel, Verzeichnis und Dienst lassen sich über `DEPLOY_SSH`, `DEPLOY_DIR`, `DEPLOY_SERVICE` ändern (`deploy.sh --help`).

Die Startseite zeigt unten „Stand: …“ – die Build-Zeit aus `META-INF/build-info.properties` (Maven-Goal
`build-info`). Da `deploy.sh` direkt vor dem Upload baut, ist das der Zeitpunkt des letzten Uploads.

## Aufbau

- `src/main/java/de/cachebox/website/MainLayout.java` – Kopfzeile, Navigation, Fußzeile
- `src/main/java/de/cachebox/website/views/` – eine Klasse pro Seite
  - `StartView` (`/`) – Logo „Cachebox – too many secrets." vor den Bäumen
  - `FeaturesView` (`/funktionen`), `MapsView` (`/karten`), `AboutView` (`/projekt`) – Karten über `Page.card(...)`
  - `ManualView` (`/anleitung`) – zeigt `docs/anleitung/README.md` mit der Vaadin-Markdown-Komponente; der
    Maven-Build kopiert Text und Bilder in den Classpath (`pom.xml`, Ausführungen `anleitung*`). Die Anleitung
    wird also nur in `docs/anleitung/` gepflegt.
- `src/main/resources/META-INF/resources/styles/site.css` – gesamtes Styling inkl. Bäume-Hintergrund
- `src/main/resources/META-INF/resources/images/` – Bilder aus dem Cachebox-Repo
  (`SkinPacker/Icons/default/day/UI_IconPack`)

Nach einem Produktions-Build liegen vorkomprimierte `*.gz`-Dateien in `target/classes`. Der Entwicklungsmodus
liefert sie weiter aus, CSS-Änderungen erscheinen dann nicht: vorher `mvn clean` ausführen.

Neue Seite: View-Klasse mit `@Route(value = "...", layout = MainLayout.class)` anlegen, von `Page` erben
und in `MainLayout.createNav()` verlinken.
