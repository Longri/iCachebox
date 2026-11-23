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

## Wenn die Seite ohne Layout erscheint

Zwei Stolperfallen beim lokalen Start – beide zeigen sich als Seite ohne Styles oder als Fehlerseite:

- **Das Maven-Profil `production` darf lokal nicht aktiv sein** (in IntelliJ im Maven-Fenster unter „Profile“
  nachsehen, keine VM-Option `-Dvaadin.productionMode=true`). Mit dem Profil läuft Vaadin im Produktionsmodus und
  sucht das fertige Frontend-Bundle im Klassenpfad – das liegt seit der Trennung der Build-Verzeichnisse aber in
  `target/production` und nicht in `target/classes`, aus dem IntelliJ startet. Im Log steht dann
  `Unable to find index.html. It should be available on the classpath when running in production mode`.
- **Es darf nur eine Instanz laufen.** Die Statistik liegt in einer H2-Datei (`data/analytics.mv.db`), die beim
  Start gesperrt wird. Läuft schon ein `mvn spring-boot:run` oder ein zweiter Start aus der IDE, bricht der neue
  Start mit `Database may be already in use` ab; der Browser zeigt dann die alte oder eine nackte Fehlerseite.
  Also erst die laufende Instanz beenden (`lsof -nP -iTCP:8082 -sTCP:LISTEN`).

Im Entwicklungsmodus baut Vaadin das Frontend beim ersten Aufruf selbst; `mvn clean package -Pproduction` räumt
dabei nur `target/production` weg und lässt `target/classes` für IntelliJ in Ruhe.

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

## Tickets, Benutzerkonten und GitHub

`/tickets` ist die gemeinsame Ticketseite. Ohne Anmeldung führt sie zum vorhandenen `/login`;
unter `/registrieren` können Benutzer ein Ticketkonto mit Benutzername und Passwort anlegen.
Benutzernamen enthalten 3–40 Zeichen aus Buchstaben, Ziffern, Punkt, Unterstrich und Bindestrich und werden
kleingeschrieben. Das Passwort benötigt mindestens zehn Zeichen und darf höchstens 72 UTF-8-Bytes lang sein.
Gespeichert wird ausschließlich ein BCrypt-Hash. Der konfigurierte Adminname und Systemnamen sind reserviert.
Die bestehende Admin-Anmeldung aus der `.env` bleibt erhalten. Benutzer landen nach Anmeldung bei ihren Tickets,
Administratoren weiterhin bei `/admin`; dort ist die Ticket-Arbeitsliste verlinkt.

Benutzer können Fehler und Featurewünsche mit Titel und Beschreibung erstellen, bearbeiten und durch weitere
Nachrichten ergänzen. Sie sehen nur ihre eigenen Tickets und die dazugehörigen Antworten. Administratoren sehen
alle Tickets, einschließlich der von GitHub importierten Issues, und können Antworten oder ausdrücklich
**interne Notizen** speichern. Die Notizen werden bereits bei der Datenabfrage für normale Benutzer ausgeschlossen.
Auch der GitHub-Abgleich liest ausschließlich öffentliche Nachrichten. Die Status sind Neu, Rückfrage, Geplant,
In Arbeit und Erledigt. Titel/Beschreibungen haben einen Schutz vor dem Überschreiben zwischenzeitlicher Änderungen.

Die Adminliste unterstützt Suche nach Titel, Beschreibung oder Ticketnummer sowie Filter nach Typ und Status.
Tickets werden per Drag-and-drop oder mit den Pfeilknöpfen in der Zeile priorisiert. Jeder Verschiebevorgang
speichert die Reihenfolge sofort als eine Datenbanktransaktion. Auch bei gefilterter Ansicht bleibt die vollständige
Arbeitsliste erhalten; neue Tickets werden hinten angefügt. GitHub verändert diese Reihenfolge nicht.

### Screenshots und Speicherung

Nach dem Erstellen können Screenshots am Ticket hinzugefügt werden: Mehrfachauswahl, Drag-and-drop oder Einfügen
mit ⌘V/Strg+V im markierten Uploadbereich. Pro Ticket sind zehn Bilder erlaubt, pro Bild maximal 8 MiB und
24 Megapixel. Der Server prüft Dateigröße, Bildinhalt und Dimensionen unabhängig von Dateiname und MIME-Angabe.
Nur PNG und JPEG werden angenommen und vor der Speicherung neu kodiert; SVG und sonstige Dateien werden abgelehnt.
Die Anzeige über `/ticket-attachments/{id}` prüft bei jedem Abruf die Anmeldung und Ticketberechtigung und ist
nicht cachebar. Es gibt keine anonymen Bild-URLs und keine Freigabe der Uploads als statische Dateien.

`TICKETS_DIRECTORY` ist standardmäßig `data/tickets` unter dem bestehenden Datenverzeichnis. Die H2-Datei
`tickets.mv.db` enthält Konten, Tickets, Nachrichten, interne Notizen, Screenshotdaten, Reihenfolge und die
GitHub-Zuordnungen. Sie bleibt außerhalb der Jar und wird beim Deployment nicht ersetzt. Das Ticketverzeichnis
wird auf POSIX-Dateisystemen auf nur für den Dienstbenutzer zugänglich gesetzt. Für ein konsistentes Backup den
Dienst stoppen und die gesamte Datei geschützt sichern. Die Anwendung benötigt exklusiven Zugriff auf die Datei.
Der reguläre Build und Deploy-Befehl bleibt unverändert. Die erste Ausführung legt die Tabellen automatisch an.

Die Registrierung sammelt keine E-Mail-Adresse. E-Mail-Benachrichtigungen, Bestätigungsmails und ein automatisches
„Passwort vergessen“ gehören daher nicht zu dieser Umsetzung. Passwörter sicher im eigenen Passwortmanager aufbewahren.

### Synchronisation mit Longri/iCachebox aktivieren

Die GitHub-Verbindung in diesem Chat und die Zugangsdaten des laufenden Website-Servers sind getrennt.
Die Anwendung benötigt einen eigenen Fine-grained PAT: Resource owner `Longri`, Repository `iCachebox`,
Repository permission **Issues: Read and write**, sowie die automatisch enthaltene Metadata-Leseberechtigung.
Der Token benötigt keinen Zugriff auf den Quellcode. Den Token ausschließlich in der geschützten `.env` hinterlegen:

```properties
TICKETS_DIRECTORY=./data/tickets
TICKETS_GITHUB_ENABLED=true
TICKETS_GITHUB_TOKEN=
TICKETS_PUBLIC_URL=https://deine-domain.de
TICKETS_GITHUB_INTERVAL_MS=120000
```

`TICKETS_PUBLIC_URL` ist optional und enthält die eigene HTTPS-Adresse, bei Bedarf einschließlich Unterpfad.
Sie wird für Links aus dem GitHub-Issue zum geschützten Website-Ticket verwendet. Ohne Adresse steht nur die
Website-Ticketnummer im Issue. Nach Konfigurationsänderungen neu starten. Solange Synchronisation deaktiviert
ist oder der Token fehlt, funktioniert das gesamte lokale Ticketsystem und der Abgleichknopf ist deaktiviert.
Bei eingerichteter Verbindung läuft der Abgleich alle zwei Minuten und zusätzlich über „GitHub jetzt abgleichen“
in der Adminliste. Fehler beim Abgleich lassen die lokalen Daten erhalten; ein Hinweis erscheint in der Adminliste.

Das Ziel ist ausdrücklich `Longri/iCachebox`, unabhängig davon, welches Git-Remote der Website-Quellcode verwendet.
Da das Repository öffentlich ist, veröffentlicht die Website nur Tickets, deren Ersteller der Weitergabe von
Titel, Beschreibung, Benutzername und öffentlichen Antworten ausdrücklich zugestimmt hat. Diese Freigabe ist
bei der Erstellung oder später im Ticket möglich. Ein Administrator kann die Freigabe eines fremden Tickets
nicht stellvertretend erteilen. Bereits veröffentlichte Inhalte können auf GitHub kopiert worden sein; die Website
bietet deshalb keine irreführende Funktion zum nachträglichen „Privatmachen“ an.

### Abgleichregeln und Konflikte

Die Umsetzung verwendet die offiziellen [GitHub-Issue-Endpunkte](https://docs.github.com/en/rest/issues/issues)
und [Kommentar-Endpunkte](https://docs.github.com/en/rest/issues/comments). Issues und Kommentare werden vollständig
seitenweise geladen; Pull Requests werden herausgefiltert. Eine unvollständige Gesamtliste wird nicht als Grundlage
für neue Issues verwendet. Website-Tickets und -Nachrichten erhalten dauerhafte UUIDs, die als unsichtbare Marker
in GitHub-Beschreibungen bzw. -Kommentaren stehen. Vor dem Anlegen wird nach diesen Markern gesucht, sodass ein
wiederholter Abgleich auch nach verlorener HTTP-Antwort keine normalen Duplikate erzeugt. Diese Marker sollten
auf GitHub erhalten bleiben. Gelöschte oder nicht erreichbare verknüpfte Issues werden nicht automatisch neu angelegt.

Titel, Beschreibung und Offen-/Geschlossen-Status werden über einen Vergleich mit dem letzten erfolgreichen Stand
in beide Richtungen abgeglichen. Änderungen an unterschiedlichen Feldern werden zusammengeführt. Unterschiedliche
Änderungen desselben Feldes auf beiden Seiten erzeugen einen Konflikt; der Admin sieht die Website-Fassung und
die GitHub-Fassung und entscheidet ausdrücklich. Zwischenzeitliche Änderungen verhindern auch hier ein veraltetes
Überschreiben. Nur „Erledigt“ entspricht GitHub „closed“; die übrigen Website-Status entsprechen „open“.
Die feineren Status bleiben bei bloßen Textänderungen erhalten. Ein Wiederöffnen eines zuvor erledigten Tickets
auf GitHub setzt es auf „Neu“.

Öffentliche Website-Antworten werden einmalig als GitHub-Kommentare übertragen und mit dem ursprünglichen
Website-Benutzernamen gekennzeichnet; GitHub zeigt als tatsächlichen API-Autor den Tokeninhaber an. Antworten
und Kommentaränderungen von GitHub werden zurückgelesen. Website-Nachrichten werden ergänzt und nicht nachträglich
editiert oder gelöscht. Das Löschen von GitHub-Kommentaren wird nicht in die Website übernommen.
Bestehende externe GitHub-Issues werden einmalig in die Adminliste importiert und keinem Website-Benutzer zugänglich
gemacht. Interne Notizen, manuelle Reihenfolge und Screenshotdaten werden niemals an GitHub übertragen.
Screenshots werden dort über den Link zum geschützten Website-Ticket referenziert und erfordern auch dort eine
passende Website-Anmeldung; GitHub bekommt keine öffentlichen oder mit Zugriffstoken versehenen Bild-URLs.

Prüfen: `mvn test`. Tests decken Berechtigungen, Registrierung, Bildprüfung, Neustart, Sortierung, Konflikte,
beidseitige Änderungen, Kommentaränderungen, Wiederholungen und verlorene Antworten ab. Die HTTP-Tests verwenden
einen lokalen GitHub-Testanbieter. Ein echter schreibender Serverabgleich benötigt den separat konfigurierten PAT.

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
