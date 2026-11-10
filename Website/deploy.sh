#!/usr/bin/env bash
# Baut die Website und tauscht die Jar auf dem Webserver aus.
#
#   Website/deploy.sh            bauen, hochladen, Cachebox.service neu starten
#   Website/deploy.sh --dry-run  nur bauen und den Server prüfen (SSH, Verzeichnis, Dienst), nichts ändern
#
# Ablauf:
#   1. mvn clean package -Pproduction, Jar in target/cachebox-website.jar umbenennen
#   2. Server prüfen – bricht ab, bevor auf dem Server etwas geändert wird
#   3. Jar als ~/cachebox-website.jar.upload ins Home des SSH-Benutzers laden; der Dienst läuft noch
#   4. Dienst stoppen, alte Jar → cachebox-website.jar.bak, neue Jar einsetzen, Dienst starten
#      (schlägt dazwischen etwas fehl, kommt die alte Jar zurück und der Dienst wird wieder gestartet)
#   5. Nach ein paar Sekunden prüfen, ob der Dienst läuft, sonst Status und letzte Log-Zeilen zeigen
#
# Die Startseite zeigt den Build-Zeitpunkt als „Stand“. Weil hier direkt vor dem Upload gebaut wird,
# ist das der Zeitpunkt des letzten Uploads.
#
# Anpassbar über Umgebungsvariablen, z. B. DEPLOY_USER=root Website/deploy.sh
#   DEPLOY_USER     SSH-Benutzer, Standard matrix-admin
#   DEPLOY_HOST     Server, Standard 167.235.237.115
#   DEPLOY_DIR      Verzeichnis auf dem Server, Standard /Vaadin/iCacheboxWeb
#   DEPLOY_SERVICE  systemd-Dienst, Standard Cachebox.service
# Ist der Benutzer nicht root, laufen systemctl und das Tauschen über sudo; ein sudo-Passwort wird
# in Schritt 4 einmal abgefragt (vor dem Stoppen des Dienstes).

set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-matrix-admin}"
DEPLOY_HOST="${DEPLOY_HOST:-167.235.237.115}"
REMOTE_DIR="${DEPLOY_DIR:-/Vaadin/iCacheboxWeb}"
SERVICE="${DEPLOY_SERVICE:-Cachebox.service}"
JAR_NAME="cachebox-website.jar"
UPLOAD_NAME="$JAR_NAME.upload"   # relativ zum Home des SSH-Benutzers
START_WAIT=10                    # Sekunden bis zur Prüfung, ob der Dienst nach dem Start noch läuft

SSH_TARGET="$DEPLOY_USER@$DEPLOY_HOST"

DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        -n|--dry-run) DRY_RUN=true ;;
        -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# --- SSH ------------------------------------------------------------------------------------------

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
REMOTE_ARGS="$(q "$REMOTE_DIR") $(q "$SERVICE") $(q "$JAR_NAME") $(q "$UPLOAD_NAME") $START_WAIT"

# Prüft den Server, ändert nichts. Läuft ohne Terminal, das Skript kommt über stdin.
check_script() {
    cat <<'REMOTE'
set -eu
dir=$1 service=$2 jar=$3
[ -d "$dir" ] || { echo "Verzeichnis $dir fehlt" >&2; exit 1; }
systemctl cat "$service" >/dev/null || { echo "Dienst $service nicht gefunden" >&2; exit 1; }
echo "Angemeldet als $(id -un), Dienst $service: $(systemctl is-active "$service" || true)"
if [ -e "$dir/$jar" ]; then
    echo "Aktuelle Jar: $(ls -l "$dir/$jar")"
else
    echo "Noch keine $jar in $dir"
fi
if [ "$(id -u)" -ne 0 ]; then
    command -v sudo >/dev/null || { echo "$(id -un) ist nicht root und sudo fehlt" >&2; exit 1; }
    if sudo -n true 2>/dev/null; then echo "sudo: ohne Passwort"; else echo "sudo: Passwort wird beim Austausch abgefragt"; fi
fi
REMOTE
}

# Tauscht die Jar und startet den Dienst. Braucht ein Terminal (ssh -t), damit sudo nach dem Passwort
# fragen kann; deshalb kommt das Skript base64-kodiert in der Befehlszeile statt über stdin.
# Exit-Code: 0 = Dienst läuft, 3 = Dienst läuft nach dem Start nicht, sonst = Austausch fehlgeschlagen.
swap_script() {
    cat <<'REMOTE'
set -eu
dir=$1 service=$2 jar=$3 upload=$4 wait=$5
case "$upload" in /*) ;; *) upload="$HOME/$upload" ;; esac
SUDO=
[ "$(id -u)" -eq 0 ] || SUDO=sudo
[ -s "$upload" ] || { echo "Hochgeladene Datei $upload fehlt" >&2; exit 1; }
cd "$dir"

# sudo-Passwort jetzt abfragen, solange der Dienst noch läuft
[ -z "$SUDO" ] || sudo -v

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
    # Eigentümer und Rechte der bisherigen Jar übernehmen (der Upload gehört dem SSH-Benutzer)
    $SUDO chown --reference="$jar" "$upload" 2>/dev/null || true
    $SUDO chmod --reference="$jar" "$upload" 2>/dev/null || true
    $SUDO mv -f "$jar" "$jar.bak"
fi
$SUDO mv -f "$upload" "$jar"
trap - ERR
echo "Starte $service"
$SUDO systemctl start "$service" || echo "systemctl start meldet einen Fehler" >&2

echo "Warte $wait s und prüfe $service"
sleep "$wait"
if systemctl is-active --quiet "$service"; then
    echo "$service läuft"
else
    $SUDO systemctl status --no-pager "$service" || true
    $SUDO journalctl -u "$service" -n 40 --no-pager || true
    exit 3
fi
REMOTE
}

# --- 2. Server prüfen -----------------------------------------------------------------------------

step "Prüfe $SSH_TARGET:$REMOTE_DIR und $SERVICE"
check_script | ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "bash -s -- $REMOTE_ARGS" || fail "Server-Prüfung fehlgeschlagen"

if $DRY_RUN; then
    step "Dry-Run: würde jetzt $JAR_NAME hochladen, $SERVICE stoppen, die Jar tauschen und den Dienst starten"
    exit 0
fi

# --- 3. Hochladen (Dienst läuft noch) -------------------------------------------------------------

step "Lade $JAR_NAME hoch nach ~/$UPLOAD_NAME"
scp "${SSH_OPTS[@]}" "$JAR" "$SSH_TARGET:$UPLOAD_NAME" || fail "Upload fehlgeschlagen, auf dem Server ist nichts geändert"

# --- 4./5. Dienst stoppen, Jar tauschen, Dienst starten, prüfen -----------------------------------

step "Stoppe $SERVICE, tausche die Jar, starte $SERVICE"
swap_b64="$(swap_script | base64 | tr -d '\n')"
set +e
ssh -t "${SSH_OPTS[@]}" "$SSH_TARGET" "echo '$swap_b64' | base64 -d | bash -s -- $REMOTE_ARGS"
status=$?
set -e

case "$status" in
    0)
        echo "Fertig – „Stand“ auf der Startseite: build.time $build_time"
        ;;
    3)
        echo >&2
        echo "Zurück zur vorherigen Version:" >&2
        echo "  ssh -t $SSH_TARGET 'cd $REMOTE_DIR && sudo systemctl stop $SERVICE && sudo mv -f $JAR_NAME.bak $JAR_NAME && sudo systemctl start $SERVICE'" >&2
        fail "$SERVICE läuft nach dem Start nicht"
        ;;
    *)
        fail "Austausch fehlgeschlagen (siehe oben)"
        ;;
esac
