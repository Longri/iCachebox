![Cachebox – too many secrets.](../docs/banner.jpg)

# iCachebox Website

Promotion-Website für [iCachebox](https://github.com/Longri/iCachebox) (Cachebox für iOS) – Java 21, Vaadin Flow 25, Spring Boot 4.

## Starten

```bash
cd Website && mvn
```

Danach http://localhost:8082 öffnen. Im Entwicklungsmodus wird kein Node.js benötigt.

Produktions-Build (lädt Node.js bei Bedarf automatisch nach `~/.vaadin`):

```bash
cd Website && mvn clean package -Pproduction && java -jar target/production/cachebox-website-1.0-SNAPSHOT.jar
```

## Auf den Server bringen

```bash
Website/deploy.sh            # bauen, hochladen, Cachebox.service neu starten
Website/deploy.sh --dry-run  # nur bauen und den Server prüfen, nichts ändern
```

Baut die Produktions-Jar, benennt sie in `target/production/cachebox-website.jar` um und lädt sie per SSH als `matrix-admin`
auf `167.235.237.115` hoch (erst ins Home als `cachebox-website.jar.upload`, der Dienst läuft so lange weiter).
Dann stoppt es `Cachebox.service`, sichert die alte Jar in `/Vaadin/iCacheboxWeb` als `cachebox-website.jar.bak`,
setzt die neue ein und startet den Dienst; `systemctl` und das Tauschen laufen über `sudo` (fragt ggf. einmal nach
dem Passwort). Benutzer, Server, Verzeichnis und Dienst lassen sich über `DEPLOY_USER`, `DEPLOY_HOST`, `DEPLOY_DIR`,
`DEPLOY_SERVICE` ändern (`deploy.sh --help`).

Die Startseite zeigt unten „Stand: …“ – die Build-Zeit aus `META-INF/build-info.properties` (Maven-Goal
`build-info`). Da `deploy.sh` direkt vor dem Upload baut, ist das der Zeitpunkt des letzten Uploads.

## Aufbau

- `src/main/java/de/cachebox/website/MainLayout.java` – Kopfzeile, Navigation, Fußzeile
- `src/main/java/de/cachebox/website/views/` – eine Klasse pro Seite
  - `StartView` (`/`) – iCachebox-Logo (`images/icachebox-logo.svg`) mit „too many secrets." vor den Bäumen;
    dasselbe Logo steht in der Kopfzeile und, als Kopie ohne `<use>`, in der App unter Mehr › Über
  - `FeaturesView` (`/funktionen`), `MapsView` (`/karten`), `AboutView` (`/projekt`) – Karten über `Page.card(...)`
  - `ManualView` (`/anleitung`) – zeigt `docs/anleitung/README.md` mit der Vaadin-Markdown-Komponente; der
    Maven-Build kopiert Text und Bilder in den Classpath (`pom.xml`, Ausführungen `anleitung*`). Die Anleitung
    wird also nur in `docs/anleitung/` gepflegt.
- `src/main/resources/META-INF/resources/styles/site.css` – gesamtes Styling inkl. Bäume-Hintergrund
- `src/main/resources/META-INF/resources/images/` – Bilder aus dem Cachebox-Repo
  (`SkinPacker/Icons/default/day/UI_IconPack`)

Lokale Starts, IntelliJ und Tests verwenden wie üblich `target/classes`. Das Profil `production`
baut separat nach `target/production`; dort liegt auch die Produktions-Jar. Dadurch gelangen komprimierte
Produktionsressourcen nicht in die lokale Vorschau. Nach einem Produktions-Build kann die Website direkt
wieder lokal gestartet werden. Nach Änderungen an der `pom.xml` das Maven-Projekt in IntelliJ neu einlesen.

Neue Seite: View-Klasse mit `@Route(value = "...", layout = MainLayout.class)` anlegen, von `Page` erben
und in `MainLayout.createNav()` verlinken.

## Geocaching-Zugang für iCachebox

`/api-key` („Geocaching-Zugang“ in der Navigation) holt nach Freigabe bei Geocaching.com einen persönlichen
Access Token und Refresh Token. Der Ablauf verwendet den aktuellen
[Groundspeak OAuth-2-Authorization-Code-Flow mit PKCE/S256](https://api.groundspeak.com/documentation#authorization).
Die Anmeldung beim Website-Admin ist davon unabhängig.

**Voraussetzung sind von Groundspeak freigeschaltete Partner-Zugangsdaten für iCachebox.** Diese Website kann
keine Client-ID und kein Client-Secret erzeugen. Das bereitgestellte alte PHP-Skript verwendete OAuth 1.0a
und verpackte den erhaltenen Benutzertoken mit RC4/Base64 für damalige Cachebox-Versionen. Für die geplante
iOS-Anmeldung wird dieser alte Ablauf nicht verwendet. Die im ZIP enthaltenen Zugangsdaten wurden nicht
in den Quellcode oder die lokale Konfiguration übernommen. Ob frühere Partner-Zugangsdaten auch für
iCachebox/iOS verwendet werden dürfen und freigeschaltet sind, muss Groundspeak bestätigen.

In der bestehenden `.env` ergänzen:

```properties
GROUNDSPEAK_CLIENT_ID=
GROUNDSPEAK_CLIENT_SECRET=
GROUNDSPEAK_REDIRECT_URI=https://deine-domain.de/oauth/groundspeak/callback
GROUNDSPEAK_STAGING=false
```

Die Callback-URL muss bei Groundspeak **exakt so** registriert sein; sie wird absichtlich nicht aus
eingehenden Host-/Proxy-Headern abgeleitet. Bei Betrieb unter einem Unterpfad gehört dieser ebenfalls in
die URL, etwa `https://deine-domain.de/website/oauth/groundspeak/callback`. Für lokale Tests ist
`http://localhost:8082/oauth/groundspeak/callback` erlaubt; auch dafür sind passende Zugangsdaten und eine
registrierte Rücksprungadresse erforderlich. Mit `GROUNDSPEAK_STAGING=true` werden ausschließlich die
offiziellen Staging-Endpunkte verwendet; dafür die zugehörigen Staging-Zugangsdaten eintragen.
Nach Konfigurationsänderungen neu starten. Ohne vollständige Konfiguration bleibt die Seite erreichbar
und erklärt, dass die Verbindung noch nicht eingerichtet ist.

Der Browser ruft `/oauth/groundspeak/start` auf; der Server speichert zufälligen `state` und PKCE-Verifier
kurzzeitig in dessen HTTP-Sitzung. Nach der externen Freigabe prüft `/oauth/groundspeak/callback` die
Sitzungszuordnung und tauscht den Code serverseitig gegen die Token. Die Anmeldung verfällt nach zehn Minuten;
ein neuer Start ersetzt den bisherigen Versuch. Ein Callback ist nur einmal nutzbar. Fehler und Abbruch
führen mit verständlichem Hinweis zurück auf `/api-key`. Netzwerkaufrufe prüfen TLS-Zertifikate und folgen
keinen Weiterleitungen. Client-Secret und PKCE-Verifier gelangen nicht in den Browser.

Token stehen weder in Redirect-URLs noch in Anwendungslogs oder Datenbank. Das Ergebnis wird einmalig
aus der HTTP-Sitzung in die Vaadin-Seite übernommen (höchstens fünf Minuten nach dem Callback) und kann
dort kopiert oder geschlossen werden. Neuladen oder erneutes Öffnen zeigt es nicht nochmals. Bis zum
Schließen/Neuladen/Sitzungsablauf liegt die Anzeige im flüchtigen Vaadin-Sitzungszustand. Bei einem Neustart
gehen laufende Anmeldungen und Anzeigen verloren. Die Callback-Antwort ist nicht cachebar und unterdrückt
den Referer; Spring Security setzt auch für die Vaadin-Antworten die bestehenden Cache-Schutzheader.

Die Seite zeigt den Ablaufzeitpunkt des Access Tokens und den für eine spätere Erneuerung benötigten
Refresh Token. Sie erneuert Token nicht im Hintergrund. Die direkte Übernahme und Anmeldung in der
iOS-App ist ein eigener Schritt; `App/iCacheBox/GeocachingAccount.swift` ist weiterhin ein Platzhalter.

Tests: `mvn test`. Die OAuth-Tests prüfen PKCE, Sitzungsbindung, Ablauf, Wiederholung, Abbruch und den
Token-Austausch mit einem lokalen Testanbieter. Ein echter Groundspeak-Login benötigt die freigeschalteten
Partner-Zugangsdaten und lässt sich ohne sie nicht abschließend prüfen.

## Coming Soon! und Funktionsabstimmung

`/coming-soon` zeigt zehn verständliche Funktionspakete mit kurzem Nutzen und aufklappbaren
Details. Bis zu drei Pakete erhalten je eine gleichwertige Stimme. Die Reihenfolge richtet sich nach
Stimmen; Gleichstände teilen einen Rang. Die Auswahl lässt sich ersetzen oder vollständig zurückziehen.
Caches direkt laden und einfache Log-Entwürfe werden als geplante Grundlagen vor der Veröffentlichung
separat erklärt. Der vollständige offene Funktionskatalog bleibt unter „Alle offenen Funktionen im Detail“ erreichbar.

`WishCatalog.java` definiert dauerhaft stabile Paket-IDs und die zugehörigen IDs aus `FeatureCatalog.java`.
Nur noch offene Einzelpunkte erscheinen in den Paketdetails; vollständig erledigte Pakete scheiden aus.
`FeatureCatalog.java` bleibt die gemeinsame Quelle für den Umsetzungsstand auf `/funktionen`.
`done=true` kennzeichnet eine umgesetzte Funktion. IDs bei Textänderungen beibehalten und nicht wiederverwenden.

Die Paket-Abstimmung ist eine neue Runde in der Tabelle `wish_votes`. Frühere Einzelstimmen in
`feature_votes` bleiben unverändert erhalten und werden separat aufgeklappt angezeigt, einschließlich
der eigenen früheren Auswahl und einer Möglichkeit zum Zurückziehen. Sie werden niemals in Paketstimmen
umgerechnet. Beide Runden liegen in `feature-votes.mv.db` im Datenverzeichnis (`ANALYTICS_DIRECTORY`),
das auch bei Deployments erhalten bleiben und gesichert werden muss. Die Tabellen werden beim Start
bei Bedarf angelegt; eine manuelle Migration ist nicht erforderlich.

Ein HttpOnly-Cookie `cachebox-feature-voter` mit zufälliger Kennung ordnet die Auswahl für ein Jahr dem
Browser zu (SameSite=Lax, bei HTTPS zusätzlich Secure). Es wird erst beim Öffnen der Abstimmungsseite gesetzt.
Die Abstimmung speichert keine IP-Adresse und benötigt keine Anmeldung. Die Begrenzung gilt je Browser;
Cookie-Löschen, andere Browser und Automatisierung werden nicht als dieselbe Person erkannt.
Die Seite ist damit eine unverbindliche Wunschliste, keine manipulationssichere Personenabstimmung.

## Geschützte Website-Statistik

`/admin` öffnet die Auswertung; ohne Anmeldung wird auf `/login` weitergeleitet. Die öffentlichen Seiten bleiben
frei erreichbar. Der Zugang erscheint nicht in der öffentlichen Navigation. Nach Anmeldung steht „Abmelden“ bereit.
Die Umsetzung nutzt die [Vaadin-Sicherheitsintegration](https://vaadin.com/docs/latest/flow/security/enabling-security).

### Server einrichten

Im Arbeitsverzeichnis des Dienstes (z. B. `/Vaadin/iCacheboxWeb`) `.env.example` als `.env` anlegen und ausfüllen:

```properties
ADMIN_USER=dein-benutzername
ADMIN_PASSWORD=hier-ein-eigenes-zufaelliges-langes-passwort-eintragen
ADMIN_REMEMBER_ME_DAYS=14
ANALYTICS_DIRECTORY=/Vaadin/iCacheboxWeb/data
GEOIP_DATABASE=/Vaadin/iCacheboxWeb/GeoLite2-Country.mmdb
ANALYTICS_TRUSTED_PROXIES=127.0.0.1,::1
```

Das gezeigte Passwort ist nur ein Platzhalter. Ein eigenes Passwort mit mindestens 10 Zeichen und höchstens
72 UTF-8-Bytes verwenden. Fehlt Benutzer oder Passwort, gibt es **keinen** anmeldbaren Admin und kein Standardpasswort.
Zu kurze konfigurierte Passwörter verhindern den Start. Benutzername und Passwort werden beim Start geladen;
Änderungen erfordern einen Neustart. Intern wird das Passwort als BCrypt-Hash für die Anmeldung gehalten.

Die optionale Checkbox „14 Tage angemeldet bleiben“ setzt ein Remember-Me-Cookie. Die Dauer lässt sich über
`ADMIN_REMEMBER_ME_DAYS` als ganze Zahl von 1 bis 24855 konfigurieren; ohne Angabe gelten 14 Tage ab Anmeldung.
Ohne Häkchen bleibt es bei der normalen Sitzung. Remember-Me-Cookies sind HttpOnly und werden ausschließlich
über HTTPS übertragen. Abmelden entfernt das Cookie aus diesem Browser. Ein Passwortwechsel mit anschließendem
Neustart widerruft alle bisherigen Remember-Me-Cookies. Die Dauer ist keine gleitende Verlängerung bei jedem Aufruf.
Die Remember-Me-Anmeldung ersetzt keine Sitzung: Die Statistik zählt nach Sitzungsablauf weiterhin einen neuen Besuch.

Damit Remember-Me auch Neustarts und Deployments übersteht, speichert die Anwendung im Datenverzeichnis zusätzlich
`admin-login.properties` mit dem BCrypt-Hash und einem zufälligen Cookie-Schlüssel. Das Klartextpasswort bleibt in
der `.env`. Die Datei ist nur für den Dienstbenutzer lesbar und darf weder öffentlich ausgeliefert noch eingecheckt
werden. Bei geändertem Passwort wird sie automatisch aktualisiert. Zum Widerrufen aller Cookies ohne Passwortwechsel
diese Datei bei gestopptem Dienst entfernen; beim nächsten Start werden Hash und Schlüssel neu erzeugt.

Die `.env` wird über [Spring Boots externe Konfiguration](https://docs.spring.io/spring-boot/reference/features/external-config.html)
als UTF-8 Java-Properties-Datei eingelesen: `NAME=Wert`, ohne `export` und ohne Anführungszeichen.
Rückstriche als `\\` schreiben. Keine Shell-Skripte mit dieser Datei ausführen.
`.env`, `.env.*` (außer `.env.example`), Statistikdaten und GeoIP-Datenbanken sind in `.gitignore` ausgeschlossen.
Die Datei bleibt außerhalb der Jar und wird von `deploy.sh` weder übertragen noch ersetzt.

Für `Cachebox.service` entweder `WorkingDirectory=/Vaadin/iCacheboxWeb` setzen oder
`Environment=WEBSITE_ENV_FILE=/Vaadin/iCacheboxWeb/.env` in der systemd-Konfiguration ergänzen.
Die `.env` nur für den Dienstbenutzer lesbar machen (`chmod 600 .env`); das Datenverzeichnis ebenfalls nur diesem
Benutzer zugänglich machen (`chmod 700 data`) und schreibbar halten. Nach Änderungen der systemd-Konfiguration
`sudo systemctl daemon-reload` und `sudo systemctl restart Cachebox.service` ausführen.
Die Anmeldung über die öffentliche Website ausschließlich über HTTPS verwenden. Der Proxy muss die Verbindung
zu Java auf lokale/vertraute Zugriffe begrenzen. Keine zusätzliche Freigabe von `.env` oder `data` im Webserver anlegen.

### Länder und vorgeschalteter Webserver

Eine lokale [MaxMind GeoLite2-Country-Datenbank](https://dev.maxmind.com/geoip/geolite2-free-geolocation-data/)
(`.mmdb`) nach den Bedingungen des Anbieters beziehen und unter `GEOIP_DATABASE` eintragen. Sie ist nicht Teil dieses
Repos. Die Anwendung verwendet ausschließlich die lokale [GeoIP-Datenbank-API](https://maxmind.github.io/GeoIP2-java/),
keinen Webdienst; IP-Adressen werden nicht gespeichert. Datenbank regelmäßig aktualisieren und den Dienst danach
neu starten. Ohne konfigurierten Pfad läuft die Statistik mit Land „Unbekannt“; ein falscher konfigurierter Pfad
verhindert den Start, damit ein Einrichtungsfehler auffällt.

`ANALYTICS_TRUSTED_PROXIES` enthält ausschließlich die **exakten IP-Adressen** der eigenen Proxies (kein CIDR).
Die Beispielwerte passen nur zu einem Proxy auf demselben Server. Ohne Proxy die Variable leer lassen.
Nur für diese direkten Absender wird `X-Forwarded-For` ausgewertet; die Kette wird von rechts bis zum ersten
nicht vertrauten Absender durchlaufen. Der Proxy muss den Header überschreiben oder die tatsächliche Client-IP
anhängen (Nginx beispielsweise `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;`).
Die Anwendung wertet keine vom Besucher frei behaupteten Länder-Header aus. Bestehende globale
`server.forward-headers-strategy`/Tomcat-Remote-IP-Einstellungen nur mit passender Proxy-Vertrauenskonfiguration einsetzen.

### Was gezählt wird

- Aufrufe: erfolgreich angezeigte öffentliche Vaadin-Seiten, auch interne Navigation und Neuladen. Keine Bilder,
  Heartbeats, Login- oder Admin-Seiten. Die Erfassung erfolgt nach der Vaadin-Navigation und benötigt einen
  funktionierenden Browser mit JavaScript; reine HTTP-Abrufe und viele Crawler werden nicht gezählt.
- Besuche: erster öffentlicher Aufruf pro Vaadin-Sitzung (30 Minuten Inaktivität). Mehrere Tabs derselben Sitzung
  zählen zusammen. Das sind keine eindeutig wiedererkannten Menschen. Ein Besuch über Mitternacht wird nur am
  Starttag als Besuch gezählt. Es gibt keine zusätzlichen Tracking-Cookies oder Fingerprints; die bestehende
  technisch erforderliche Vaadin-Sitzung dient als kurzlebige Zählhilfe.
- Tagesverlauf, Seiten, Länder, Herkunftsdomains und grobe Geräteklassen; Filter für 7/30/90/365 Tage und erkannte
  Bots. Der Zeitraum enthält den heutigen, noch unvollständigen Tag. Die Tabellen zeigen Besuchsstarts in der
  jeweiligen Kategorie. Herkunftsdomains werden pro Browser-Tab beim Laden erfasst; interne Navigation behält
  diese Quelle. Fehlender Referer ist „Direkt / unbekannt“. Nur der Hostname wird gespeichert, keine Pfade,
  Suchbegriffe, URL-Parameter, Browserkennungen oder IP-Adressen. Bots und Geräte werden nur grob anhand des
  User-Agent-Headers eingeordnet. „Bots einschließen“ zeigt erkannte Bots zusammen mit den übrigen Aufrufen.

Gespeichert werden ausschließlich Tagesaggregate (Zeitzone Europe/Berlin) in `data/analytics.mv.db`, für maximal
400 Kalendertage. Ältere Zeilen werden beim Start und beim nächsten Zugriff am neuen Tag entfernt. Der Dienst
muss allein auf diese eingebettete H2-Datenbank zugreifen. Bei einem Neustart bleiben die Zahlen erhalten, die
Sitzungen beginnen neu. Vor der ersten Inbetriebnahme gibt es keine rückwirkenden Zahlen. Für Backups den Dienst
stoppen und die Datenbankdatei sowie `admin-login.properties` geschützt sichern; `.env` getrennt und geschützt sichern. Diese Aggregation ändert keine
bestehenden Webserver-Zugriffslogs.

Prüfen: `mvn test`; Produktions-Jar: `mvn package -Pproduction`.
