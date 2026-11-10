#!/usr/bin/env bash
# Baut die Website und tauscht die Jar auf dem Webserver aus.
#
#   Website/deploy.sh            bauen, hochladen, Cachebox.service neu starten
#   Website/deploy.sh --dry-run  nur bauen und den Server prüfen (SSH, Verzeichnis, Dienst), nichts ändern
#
# Ablauf:
#   1. mvn clean package -Pproduction, Jar in target/cachebox-website.jar umbenennen
#   2. Server prüfen – bricht ab, bevor auf dem Server etwas geändert wird
#   3. Jar als cachebox-website.jar.upload hochladen; der Dienst läuft währenddessen noch
#   4. Dienst stoppen, alte Jar → cachebox-website.jar.bak, neue Jar einsetzen, Dienst starten
#      (schlägt dazwischen etwas fehl, kommt die alte Jar zurück und der Dienst wird wieder gestartet)
#   5. Nach ein paar Sekunden prüfen, ob der Dienst läuft, sonst die letzten Log-Zeilen zeigen
#
# Die Startseite zeigt den Build-Zeitpunkt als „Stand“. Weil hier direkt vor dem Upload gebaut wird,
# ist das der Zeitpunkt des letzten Uploads.
#
# Anpassbar über Umgebungsvariablen:
#   DEPLOY_SSH      SSH-Ziel, Standard root@167.235.237.115 (ohne „benutzer@“ gilt ~/.ssh/config)
#   DEPLOY_DIR      Verzeichnis auf dem Server, Standard /Vaadin/iCacheboxWeb
#   DEPLOY_SERVICE  systemd-Dienst, Standard Cachebox.service
# Ist der SSH-Benutzer nicht root, braucht er Schreibrecht im Verzeichnis und sudo ohne Passwort.

set -euo pipefail

SSH_TARGET="${DEPLOY_SSH:-root@167.235.237.115}"
REMOTE_DIR="${DEPLOY_DIR:-/Vaadin/iCacheboxWeb}"
SERVICE="${DEPLOY_SERVICE:-Cachebox.service}"
JAR_NAME="cachebox-website.jar"
START_WAIT=10   # Sekunden bis zur Prüfung, ob der Dienst nach dem Start noch läuft

DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        -n|--dry-run) DRY_RUN=true ;;
        -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unbekannte Option: $arg (siehe --help)" >&2; exit 2 ;;
    esac
done

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[31mFehler:\033[0m %s\n' "$*" >&2; exit 1; }

WEBSITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$WEBSITE_DIR"

# --- 1. Bauen -------------------------------------------------------------------------------------

step "Baue Produktions-Jar (mvn clean package -Pproduction)"
mvn -B -q clean package -Pproduction || fail "Maven-Build fehlgeschlagen"

shopt -s nullglob
jars=(target/cachebox-website-*.jar)
shopt -u nullglob
[ "${#jars[@]}" -eq 1 ] || fail "erwartet genau eine Jar target/cachebox-website-*.jar, gefunden: ${jars[*]:-keine}"
mv -f "${jars[0]}" "target/$JAR_NAME"
JAR="$WEBSITE_DIR/target/$JAR_NAME"

# Nur eine Produktions-Jar hochladen (ohne -Pproduction fehlt das Frontend-Bundle)
# (Spring Boot legt META-INF aus den Ressourcen an die Wurzel der Jar)
flow_info="$(unzip -p "$JAR" META-INF/VAADIN/config/flow-build-info.json 2>/dev/null || true)"
grep -q '"productionMode" *: *true' <<<"$flow_info" || fail "$JAR ist kein Vaadin-Produktions-Build"
build_info="$(unzip -p "$JAR" META-INF/build-info.properties 2>/dev/null || true)"
build_time="$(sed -n 's/^build\.time=//p' <<<"$build_info" | tr -d '\\')"
[ -n "$build_time" ] || fail "build-info.properties fehlt in $JAR (Stand auf der Startseite)"
echo "Gebaut: $JAR ($(du -h "$JAR" | cut -f1 | tr -d ' '), build.time $build_time)"

# --- 2. Server prüfen -----------------------------------------------------------------------------

# Eine SSH-Verbindung für alle Schritte (nur einmal anmelden)
CONTROL_DIR="$(mktemp -d /tmp/cbdeploy.XXXXXX)"
SSH_OPTS=(-o ControlMaster=auto -o "ControlPath=$CONTROL_DIR/%C" -o ControlPersist=120 -o ConnectTimeout=15)
cleanup() {
    ssh "${SSH_OPTS[@]}" -O exit "$SSH_TARGET" >/dev/null 2>&1 || true
    rm -rf "$CONTROL_DIR"
}
trap cleanup EXIT

# Argumente für die entfernte Shell quoten (ssh fügt sie zu einer Befehlszeile zusammen)
q() { printf '%q' "$1"; }
remote() { ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "$@"; }

step "Prüfe $SSH_TARGET:$REMOTE_DIR und $SERVICE"
remote bash -s -- "$(q "$REMOTE_DIR")" "$(q "$SERVICE")" "$(q "$JAR_NAME")" <<'REMOTE' || fail "Server-Prüfung fehlgeschlagen"
set -eu
dir=$1 service=$2 jar=$3
[ -d "$dir" ] || { echo "Verzeichnis $dir fehlt" >&2; exit 1; }
[ -w "$dir" ] || { echo "Keine Schreibrechte in $dir für $(id -un)" >&2; exit 1; }
systemctl cat "$service" >/dev/null || { echo "Dienst $service nicht gefunden" >&2; exit 1; }
echo "Dienst $service: $(systemctl is-active "$service" || true)"
if [ -e "$dir/$jar" ]; then
    echo "Aktuelle Jar: $(ls -l "$dir/$jar")"
else
    echo "Noch keine $jar in $dir"
fi
REMOTE

if $DRY_RUN; then
    step "Dry-Run: würde jetzt $JAR_NAME hochladen, $SERVICE stoppen, die Jar tauschen und den Dienst starten"
    exit 0
fi

# --- 3. Hochladen (Dienst läuft noch) -------------------------------------------------------------

step "Lade $JAR_NAME hoch"
scp "${SSH_OPTS[@]}" "$JAR" "$SSH_TARGET:$REMOTE_DIR/$JAR_NAME.upload" || fail "Upload fehlgeschlagen, auf dem Server ist nichts geändert"

# --- 4. Dienst stoppen, Jar tauschen, Dienst starten ----------------------------------------------

step "Stoppe $SERVICE, tausche die Jar, starte $SERVICE"
remote bash -s -- "$(q "$REMOTE_DIR")" "$(q "$SERVICE")" "$(q "$JAR_NAME")" <<'REMOTE' || fail "Austausch fehlgeschlagen (siehe oben)"
set -eu
dir=$1 service=$2 jar=$3
SUDO=
[ "$(id -u)" -eq 0 ] || SUDO="sudo -n"
cd "$dir"
[ -s "$jar.upload" ] || { echo "Hochgeladene Datei $dir/$jar.upload fehlt" >&2; exit 1; }

# Bei einem Fehler nach dem Stoppen: alte Jar zurück und Dienst wieder starten
restore() {
    echo "Fehler beim Austausch – stelle die alte Version wieder her" >&2
    if [ ! -e "$jar" ] && [ -e "$jar.bak" ]; then $SUDO mv -f "$jar.bak" "$jar"; fi
    $SUDO systemctl start "$service" || true
}

echo "Stoppe $service"
$SUDO systemctl stop "$service"
trap restore ERR
if [ -e "$jar" ]; then
    # Eigentümer und Rechte der bisherigen Jar übernehmen (falls der Dienst unter eigenem Benutzer läuft)
    $SUDO chown --reference="$jar" "$jar.upload" 2>/dev/null || true
    $SUDO chmod --reference="$jar" "$jar.upload" 2>/dev/null || true
    $SUDO mv -f "$jar" "$jar.bak"
fi
$SUDO mv -f "$jar.upload" "$jar"
trap - ERR
echo "Starte $service"
# Ein Fehler hier bricht nicht ab: Schritt 5 zeigt dann Status, Log und den Weg zurück
$SUDO systemctl start "$service" || echo "systemctl start meldet einen Fehler" >&2
REMOTE

# --- 5. Läuft der Dienst? -------------------------------------------------------------------------

step "Warte $START_WAIT s und prüfe $SERVICE"
sleep "$START_WAIT"
if remote systemctl is-active --quiet "$(q "$SERVICE")"; then
    echo "$SERVICE läuft. Fertig – „Stand“ auf der Startseite: build.time $build_time"
else
    remote "SUDO=; [ \"\$(id -u)\" -eq 0 ] || SUDO='sudo -n'; \$SUDO systemctl status --no-pager $(q "$SERVICE"); \$SUDO journalctl -u $(q "$SERVICE") -n 40 --no-pager" || true
    echo >&2
    echo "Zurück zur vorherigen Version:" >&2
    echo "  ssh $SSH_TARGET 'cd $REMOTE_DIR && systemctl stop $SERVICE && mv -f $JAR_NAME.bak $JAR_NAME && systemctl start $SERVICE'" >&2
    fail "$SERVICE läuft nach dem Start nicht"
fi
