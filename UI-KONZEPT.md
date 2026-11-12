# iCacheBox – UI-Konzept und Startstand

Zusammenfassung der Recherche und des Gerüsts vom 9./10.11.2026, damit ein neuer Chat direkt mit UI und Startbildschirm beginnen kann.
Projektüberblick, Struktur und Befehle stehen in `CLAUDE.md`.

## 1. Ausgangslage

Die Android-App Cachebox (libGDX, eigene Oberfläche, fünf Hauptbuttons unten, Schnellbutton-Leiste oben, Wisch- und
Langdruck-Aktionen) soll als native iOS-App in SwiftUI neu gebaut werden. Cachebox-Quellen liegen unter
`/Users/Shared/LongriShare/@Work/cachebox`.

Cachebox-Bedienung (aus Screenshots und Code, `ViewManager.java`, `GestureButton.java`):

| Button | Antippen | Wischen auf / ab / links / rechts | Nur im Menü |
|---|---|---|---|
| 1 Cacheliste | Liste | Liste / Parken / Teilen / Trackables | – |
| 2 Cache | Beschreibung | Beschreibung / Logs / Notizen / Wegpunkte | Hinweis, Spoiler, extern anzeigen |
| 3 Karte | Karte | Karte / Navigieren / Tracks / Kompass | Kartendownload |
| 4 Werkzeuge | Entwürfe | Entwürfe / Foto / Solver 1 / Solver 2 | Video, Sprachnotiz |
| 5 Sonstiges | Menü | Credits / Beenden / Einstellungen / Parken | Tag/Nacht, Hilfe, Taschenlampe, Über |

Dazu: Schnellbutton-Leiste oben (konfigurierbar), eigene Dialoge und Menüs, Sprachauswahl in der App, Skins/Nachtmodus,
Info-Zeile des gewählten Caches unter der Leiste, grünes Farbschema.

## 2. Ergebnis der App-Review-Recherche

**Kernaussage:** Eine eigene Optik ist kein Ablehnungsgrund, die Risiken liegen bei Geocaching-API-Key und Lizenzen.
Quellen: App Store Review Guidelines (Stand 16.10.2026), HIG-Seiten, Geocaching-HQ-Partnerseiten, Cachebox-Code.
Teile waren nicht lesbar oder nur sekundär belegt; das ist unten markiert. Keine Rechtsberatung.

### Apple-Regeln, die das UI betreffen
- Die Guidelines schreiben weder HIG noch Standard-Controls vor. Grenzen setzen 2.5.9 (native UI-Elemente nicht verändern),
  2.5.19 (keine versteckten Funktionen) und 4.2 (kein „repackaged website“).
- 2.3.10: keine Namen, Icons oder Bilder anderer Mobilplattformen in App oder Metadaten (Texte mit „Android“,
  „CacheBox for Android“, Play-Store-Links entfernen).
- 2.1: Bei Login ist ein Demo-/Testkonto (Premium) für die Prüfer nötig.
- 4.8: Sign in with Apple ist nicht nötig (Ausnahme: Client für einen bestimmten Drittdienst).
- 5.1.1: Datenschutzerklärung in App und Metadaten. 5.1.5/2.5.4: Hintergrund-Ortung nur mit erklärtem Zweck (Track-Aufzeichnung).
- 2.5.2: kein Nachladen von ausführbarem Code (Cachebox-BeanShell-Kartenlayer nicht portieren).
- 3.1.3: Preise/Upgrade-Werbung für Geocaching-Premium nur wie erlaubt; Wortlaut mit HQ klären.

### HIG-Punkte, nach denen das UI gebaut wird
- Touch-Ziele 44×44 pt (Minimum 28×28), Safe Areas beachten, Dynamic Type bis mindestens 200 %.
- Tab-Bar nur für Navigation, nicht für Aktionen; Tabs nicht deaktivieren oder verstecken; keine „Mehr“-Überlauftabs
  (hier: ein bewusster Mehr-Tab, kein System-Überlauf).
- Alerts: bis zu drei Buttons, nicht beim App-Start, nicht für undoable Aktionen; Auswahlen als Action Sheet.
- Dark Mode mitmachen, kein app-eigener Darstellungsschalter; Kontrast 4,5:1.
- Gesten: nie als einziger Weg für Wichtiges; Wisch ergänzt sichtbare Buttons; Zurück per Randwisch.

### Login, API und Lizenzen
- **Geocaching-API:** Programm laut Bewerbungsseite fast geschlossen. Ein Key gilt nur für eine App und eine Plattform
  (Lizenzvertrag §4.3), der Android-Key deckt iOS nicht ab. OAuth 2 mit PKCE, feste Redirect-URIs.
  Login nur über geocaching.com, Mitgliedsstatus bei Start/Resume prüfen, Pflicht-Badge „Powered by Geocaching HQ“.
  Cachebox steht nicht auf der Partnerliste der iOS-Apps. **Vor weiterer Arbeit mit HQ klären.**
- **Login-Technik:** `ASWebAuthenticationSession` statt eingebettetem WebView (Google blockiert WebView-OAuth,
  die Seite bietet Social-Logins). Cachebox nutzt dagegen WebView plus Proxy `gc-oauth.longri.de` mit Token-Scraping.
- **Nicht portieren:** HTML-Scraping von geocaching.com (`GroundspeakAPI.java:326-374`, `ContactOwner.java`, `GCVote.java`),
  BeanShell-Layer, GCVote-Login per HTTP-GET, Tokens im Log.
- **GPL:** Cachebox-Dateien tragen GPL-Header ohne Version, keine LICENSE-Datei. Ein Zeile-für-Zeile-Port wäre ein
  abgeleitetes Werk; FSF sieht GPL und App Store als unvereinbar. Nur Funktionen und Aussehen als Vorlage nutzen und
  selbst neu schreiben, oder Zustimmung aller Urheber einholen. `micross.ttf` nicht übernehmen, solange Rechte ungeklärt.
  Die Cachetyp-, Wegpunkt- und Status-Icons (`SkinPacker/Icons/default/day/UI_IconPack`) sind seit Nov. 2026 auf
  Wunsch übernommen (`App/iCacheBox/Assets.xcassets/Cachebox`, die kleinen Kartensymbole `small1…7` und `star` in
  `Assets.xcassets/CacheboxMap`), ebenso die Attribut-Icons
  (`CB_Android/assets/data/attributes` → `Assets.xcassets/Attributes`) und für das Karten-Infofeld Satellit, Karte und
  Kompassrose (`satellite`, `map`, `compass-frame-small`, `compass-scale-small` → `Assets.xcassets/CacheboxUI`); die
  Positions- und Zielpfeile (`arrow-Compass`, `arrow-GPS`, `target-arrow`) und der Toggle-Knopf sind als Vektoren
  nachgezeichnet (`CacheboxArrows.swift`, `MapControls.swift`). Seit 11.11.2026 außerdem die fünf Hauptknöpfe mit
  gedrückter und Filter-Variante, `cmIcon`/`MENUFILTERED` und `button-list-back` (→ `Assets.xcassets/CacheboxButtons`,
  äußerster halbtransparenter Pixelrand entfernt), für den Kompass `compass-frame`/`compass-scale` in 400 px, `sonne`,
  `mond` (→ `CacheboxCompass`) sowie Sterne `stars*icon`, Größenbalken, `tb` und `FavPoi` (→ `CacheboxInfo`).
  Rechte vor einer Veröffentlichung klären.
  Die Attribut-Texte sind selbst formuliert (nicht aus den Cachebox-`strings.ini`).
- **mapsforge:** LGPL-3.0 mit Verzicht auf Relink-Pflicht (§4d/e). Der Swift-Port bleibt LGPL-3.0, Quelltext veröffentlichen.
  Ob der Fork im Cachebox-Repo denselben Verzicht trägt, ist nicht geprüft.
- **Empfohlene Lizenzaufteilung:** `Packages/Mapsforge/` LGPL-3.0; App (`App/`) Apache-2.0 oder MIT (MPL-2.0 als Mittelweg).
  Keine GPL/AGPL für die App. Im Zweifel Repo zunächst privat anlegen.
- **Kartenquellen:** OSM-Standardkacheln verlangen eigenen User-Agent und verbieten Offline-Nutzung; OpenCycleMap
  (Thunderforest) braucht API-Key; Esri World Imagery laut Forenantwort nur mit ArcGIS-Lizenz (Primärquelle nicht lesbar).
  OpenAndroMaps und Elevate nicht ohne schriftliche Erlaubnis bündeln (Elevate CC BY-NC-SA 4.0).
  Bei sichtbarer Karte „© OpenStreetMap contributors“ anzeigen.

## 3. Zielkonzept: fünf Tabs mit nativen SwiftUI-Bausteinen

> **Geändert am 11.11.2026 (Wunsch des Nutzers):** Statt der Tab-Leiste sitzen unten die fünf Cachebox-Knöpfe mit den
> Bildern und dem Verhalten der Android-Version (Antippen, Menü beim zweiten Antippen, Wischen, Langdruck; siehe
> `MainButtons.swift` und Anleitung „Die fünf Knöpfe“). Die Ansichten selbst bleiben native SwiftUI-Bausteine; jede
> Wischfunktion steht auch im Menü des Knopfs und als VoiceOver-Aktion (HIG: Gesten nie der einzige Weg). Die Tabelle
> unten beschreibt den ursprünglichen Plan; die heutige Belegung steht in `MainButton.functions`.

> **Geändert am 12.11.2026 (Wunsch des Nutzers):** Der gewählte Cache steht nicht mehr als Kapsel unten, sondern wie
> in Cachebox als Slider oben über allen Ansichten. Herunterziehen zeigt die Zusatzknöpfe (Cachebox `QuickButtonList`
> mit der Grundbelegung) und darunter die Cache-Info (`CacheboxSlider.swift`, Anleitung „Der gewählte Cache und die
> Zusatzknöpfe“). Die ersten beiden Punkte unter „Weitere Entscheidungen“ sind damit überholt. Die Icons der
> Zusatzknöpfe (`Assets.xcassets/CacheboxQuick`) stammen aus der Cachebox-Skin; ihre Rechte sind so ungeklärt wie die
> der übrigen Skin-Bilder.

Struktur und Farben (Cachebox-Grün) bleiben, die Umsetzung ist nativ. Aus verstecktem Wischen werden sichtbare Controls.

| Tab | Inhalt |
|---|---|
| Caches | Liste mit Suchfeld; Zeilen-Wischen (Favorit, Karte, Markieren); Menü: Filter, Import, Trackables, Parken, Teilen |
| Cache | Umschalter Beschreibung / Wegpunkte / Logs / Spoiler; Hinweis als Alert mit Dekodieren; Menü: Aktualisieren, Favorit, Beobachtungsliste, Notizen, Solver, Bearbeiten, Löschen; Log: Langdruck-Menü |
| Karte | Mapsforge-Karte randlos, Infofeld und Knöpfe schweben darüber; Ebenen-Sheet (Karte, Theme, Stil, Overlays, Tracks); Standort-Knopf (GPS/Frei/Ausrichtung); Kompass; OSM-Attribution |
| Loggen | Entwürfe (Feldnotizen) als Liste; Plus legt Entwurf an; Foto, Sprachnotiz, Solver; Hochladen als sichtbarer Knopf |
| Mehr | Geocaching-Konto, Import, Karten und Themes, Schnellzugriffe, Einstellungen, Hilfe, Über |

Weitere Entscheidungen:
- Gewählter Cache als Kapsel über der Tab-Bar (Ersatz für die Cachebox-Infozeile). Ab iOS 26 wäre `tabViewBottomAccessory`
  möglich; das Projekt steht auf iOS 17, deshalb aktuell `safeAreaInset`.
- Schnellbuttons werden eine anpassbare Leiste über der Karte (noch nicht gebaut).
- Rückfragen als System-Alerts oder Sheets, Zurück per `NavigationStack`.
- Sprache pro App über iOS-Einstellungen, Tag/Nacht folgt dem System; Beenden und Taschenlampe entfallen.
- Offen: Der vierte Tab heißt „Loggen“ (Entwürfe im Mittelpunkt); der Solver könnte stattdessen beim Cache liegen.

## 4. Stand des Codes

Das Tab-Gerüst ist im Commit „Initial Commit“ enthalten; Willkommensseite und Konto (unten) sind noch nicht committet.
Deployment-Target iOS 17, getestet im Simulator iPhone 18 Pro (Debug-Build, Build erfolgreich, alle Tabs bedienbar).

Neue Dateien in `App/iCacheBox/`:

| Datei | Inhalt |
|---|---|
| `AppState.swift` | `MainTab`, Platzhalter-Modell `Cache` mit drei Beispiel-Caches (`GC0TEST1`–`3`), `AppState` (Tab, Auswahl), `Color.cachebox` |
| `RootView.swift` | `TabView` mit fünf Tabs, `SelectedCacheBar` (Kapsel mit gewähltem Cache) |
| `CacheListView.swift` | Liste mit Suche, Auswahl, Wisch zur Karte, Menü (Einträge ausgegraut) |
| `CacheDetailView.swift` | Umschalter, Hinweis-Alert, Aktionsmenü; nur Beschreibung hat Inhalt |
| `LogDraftsView.swift` | Leere Entwurfsliste |
| `MoreView.swift` | Mehr-Tab: Kontozeile mit Status, Platzhalterseiten, „Willkommensseite zeigen“ |
| `WelcomeView.swift` | Willkommensseite beim ersten Start: vier Funktionszeilen, „Mit Geocaching.com anmelden“, „Ohne Konto starten“ |
| `GeocachingAccount.swift` | Kontomodell (abgemeldet/angemeldet); `signIn()` wirft bis zum API-Zugang `AccountError.signInUnavailable` |
| `AccountView.swift` | Mehr › Geocaching-Konto und `SignInButton` (Fortschritt, Fehler-Alert), auch auf der Willkommensseite genutzt |

Geändert: `iCacheBoxApp.swift` startet `RootView`; `RootView` zeigt die Willkommensseite, bis
`@AppStorage("onboardingCompleted")` gesetzt ist, danach die Tabs. `ContentView.swift` (Kartenansicht samt `MapModel`)
blieb unverändert und ist der Karte-Tab. `Color.cachebox` hat jetzt eine hellere Dark-Mode-Variante
(Kontrast 4,5:1 auf Listenzellen, 5,6:1 auf Schwarz; weiße Schrift auf Grün dort nur 3,8:1, wie bei den Systemfarben).

Willkommensseite getestet: passt bei Standardschrift ohne Scrollen auf das iPhone 18 Pro, scrollt bei AX5-Schrift
(Symbole dann über dem Text), Dark Mode geprüft, Anmelde-Hinweis, „Ohne Konto starten“ und „Willkommensseite zeigen“
funktionieren. Nicht geprüft: VoiceOver, iPad, Querformat.

Beobachtungen aus dem Test:
- Die Kartenansicht lädt im Simulator Bremen; die Performance-Anzeige (Kachelzahl, Ø/max ms) liegt noch über der Karte.
- Der Umschalter heißt „Beschr.“, weil „Beschreibung“ bei vier Segmenten abgeschnitten wurde.
- Der Kartentab hat noch ein eigenes Layer-Menü (`MapMenu`), die gewünschte Ebenen-Sheet-Variante steht aus.

## 5. Nächste Schritte (Vorschlag für den neuen Chat)

1. ~~Startbildschirm und Onboarding~~ erledigt (siehe Abschnitt 4).
2. Login-Ablauf mit `ASWebAuthenticationSession` als Platzhalter, bis ein API-Key geklärt ist.
3. Schnellbutton-Leiste auf der Karte und gewählter Cache auf der Karte (Marker, Zentrieren).
4. Cache-Detail weiter ausbauen: Wegpunkte, Logs, Spoiler, Notizen als SwiftUI-Ansichten.
5. Entwürfe-Datenmodell, später Persistenz (SwiftData oder SQLite) statt Platzhalterdaten.
6. Barrierefreiheit prüfen: Dynamic Type, VoiceOver-Labels, Touch-Ziele, Dark Mode.
7. Parallel: Geocaching-HQ-Anfrage (iOS-Key), Entscheidung zur Lizenz, LICENSE-/NOTICE-Dateien anlegen.
