#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u
# If a pipeline fails, the error code of the last command to exit with a non-zero status is returned.
set -o pipefail
#
#                           _____            _____             __________ 
# _______ ________  ___________(_)_____________  /_      _________  /__(_)
# __  __ `__ \_  / / /_  ___/_  /_  _ \_  __ \  __/_______  ___/_  /__  /
# _  / / / / /  /_/ /_  /   _  / /  __/  / / / /_ _/_____/ /__ _  / _  /
# /_/ /_/ /_/_\__, / /_/    /_/  \___//_/ /_/\__/        \___/ /_/  /_/
#            /____/
#
# ==============================================================================
#
# Script Name:    myrient-cli.sh
# Description:    A command-line tool to browse and download content from the Myrient archive.
# GitHub:         https://github.com/elyps/myrient-cli
# License:        MIT
#
# ==============================================================================

# Verzeichnis des Skripts ermitteln
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PROJECT_ROOT=$(cd -- "$SCRIPT_DIR/.." &> /dev/null && pwd)
 
# Basis-URL der zu durchsuchenden Website
BASE_URL="https://myrient.erista.me" 
DOWNLOAD_DIR="./downloads" # Standard-Download-Verzeichnis
CONFIG_FILE="$PROJECT_ROOT/config/.myrient_cli_rc"
AUTO_VERIFY="yes" # Standardmäßig nachfragen
MAX_CONCURRENT_DOWNLOADS=3 # Maximale Anzahl gleichzeitiger Downloads
AUTO_EXTRACT="yes" # Standardmäßig kein automatisches Entpacken
DELETE_ARCHIVE_AFTER_EXTRACT="yes" # Standardmäßig Archiv nach dem Entpacken löschen
AUTO_UPDATE_CHECK="yes" # Standardmäßig keine automatische Update-Prüfung
GITHUB_REPO="elyps/myrient-cli" # Update-Repository
SEARCH_REGIONS="" # Standardmäßig keine Regionsfilter
DISCLAIMER_ACCEPTED="no" # Ob der Haftungsausschluss akzeptiert wurde
SEARCH_EXCLUDE_KEYWORDS="Demo Beta" # Standardmäßig "Demo" und "Beta" ausschließen
VERSION="" # Aktuelle Version, wird aus der VERSION-Datei geladen
IP_ADDRESS="" # Globale Variable für die IP-Adresse
IP_LOCATION="" # Globale Variable für den Standort
DOWNLOAD_SPEED_LIMIT="0" # Standardmäßig keine Begrenzung (0 = unbegrenzt) 
DOWNLOAD_HISTORY_LOG="$PROJECT_ROOT/logs/.download_history" # Protokoll für abgeschlossene Downloads
RE_DOWNLOAD_POLICY="ask" # Richtlinie für erneute Downloads: ask, always, skip
WATCHLIST_FILE="$PROJECT_ROOT/config/.watchlist"
DOWNLOAD_QUEUE_FILE="$PROJECT_ROOT/config/.download_queue"
QUEUE_LOCK_FILE="$PROJECT_ROOT/config/.queue.lock"
QUEUE_PAUSE_FILE="$PROJECT_ROOT/config/.queue.pause"


# --- Farben ---
C_RESET=$'\033[0m'
C_RED=$'\033[0;31m'
C_GREEN=$'\033[0;32m'
C_YELLOW=$'\033[0;33m'
C_BLUE=$'\033[0;34m'
C_PURPLE=$'\033[0;35m'
C_CYAN=$'\033[0;36m'
C_WHITE=$'\033[1;37m'
C_GRAY=$'\033[0;90m'
C_BOLD=$'\033[1m'
HEADLINE_COLOR="$C_CYAN" # Standard-Überschriftenfarbe

# Funktion zur Dekodierung von URL-kodierten Zeichen (z.B. %20 -> Leerzeichen)
url_decode() {
    local url_encoded="${1//+/ }"
    printf '%b' "${url_encoded//%/\\x}"
}

# Funktion zum Abrufen und Parsen der Verzeichnisliste
# Extrahiert Links und Dateinamen aus dem HTML-Code
get_links() {
    local current_path="$1"
    # curl holt den HTML-Inhalt.
    # sed verarbeitet den HTML-Code zeilenweise:
    # - /<tr/!d; löscht alle Zeilen, die nicht mit <tr beginnen.
    # - /class="link"/!d; löscht alle Zeilen, die nicht die Link-Zelle enthalten.
    # - s/.../p; extrahiert den href-Wert und den Link-Text.
    curl -s "${BASE_URL}${current_path}" | \
        sed -n -e '/<tr/!d' -e '/class="link"/!d' \
        -e 's/.*<a href="\([^"]*\)".*>\([^<]*\)<\/a>.*<td class="size">\([^<]*\)<\/td>.*/\1|\2|\3/p' | \
        while IFS='|' read -r encoded_path display_name size; do
            # Filtere Navigations-Links heraus
            if [[ "$display_name" != "./" && "$display_name" != "../" && "$display_name" != "Parent directory/" ]]; then
                # Ausgabe: Vollständiger KODIERTER Pfad | Anzeigename (bereits dekodiert) | Größe
                echo "${current_path}${encoded_path}|${display_name}|${size}"
            fi
        done
}
# Exportiere die Funktion, damit sie in Subshells (z.B. in `gum spin`) verfügbar ist.
export -f get_links


# A simple spinner function
spinner() {
    local spin='-\|/'
    local i=0
    while true; do
        i=$(( (i+1) %4 ))
        # Use -n with echo and \r to stay on the same line
        echo -n -e "\r [${spin:$i:1}] "
        sleep 0.1
    done
}

# Funktion zum Festlegen des Download-Verzeichnisses
set_download_directory() {
    local no_save="${1:-}" # Ensure no_save is always set, even if empty
    gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Download-Verzeichnis festlegen"

    new_dir=$(gum input --placeholder "Neues Verzeichnis eingeben..." --value "$DOWNLOAD_DIR")

    # Wenn die Eingabe leer ist, keine Änderung
    if [[ -z "$new_dir" ]]; then
        gum style --foreground 212 "Keine Änderung vorgenommen."
        return
    fi

    # Tilde-Expansion manuell durchführen (z.B. ~/Downloads)
    eval new_dir="$new_dir"

    if [[ ! -d "$new_dir" ]]; then
        if gum confirm "Verzeichnis '$new_dir' existiert nicht. Erstellen?"; then
            mkdir -p "$new_dir"
            if [[ $? -eq 0 ]]; then
                echo -e "${C_GREEN}Verzeichnis '$new_dir' wurde erstellt.${C_RESET}"
                DOWNLOAD_DIR="$new_dir"
            else
                echo -e "${C_RED}Fehler beim Erstellen des Verzeichnisses. Keine Änderung vorgenommen.${C_RESET}"
            fi
        else
            gum style --foreground 212 "Keine Änderung vorgenommen."
        fi
    else
        DOWNLOAD_DIR="$new_dir"
        echo -e "${C_GREEN}Download-Verzeichnis auf '$DOWNLOAD_DIR' gesetzt.${C_RESET}"
    fi

    save_config "suppress_message"
    gum spin --title "Einstellungen gespeichert. Kehre zum Hauptmenü zurück..." -- sleep 2
}

# Funktion zum Anzeigen laufender Hintergrund-Downloads
show_background_downloads() {
    gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Laufende Hintergrund-Downloads"

    # Finde die Log-Dateien der im Hintergrund laufenden wget-Prozesse
    local log_files
    log_files=$(find "$PROJECT_ROOT/logs" -maxdepth 1 -type f -name "*.log")

    if [ -z "$log_files" ]; then
        gum style --padding "1" "Keine laufenden Hintergrund-Downloads gefunden."
    else
        local table_rows=()
        # Header für die Tabelle
        table_rows+=("DATEI,FORTSCHRITT,GESCHWINDIGKEIT,VERBLEIBEND")

        for log_file in $log_files; do
            # Extrahiere den Dateinamen ohne .log
            local filename
            filename=$(basename "$log_file" .log)

            # Extrahiere die letzte Fortschrittszeile aus dem Log
            local last_line
            last_line=$(tail -n 1 "$log_file" 2>/dev/null | tr -d '\r')

            # Parse die Zeile, um Fortschritt, Geschwindigkeit und ETA zu erhalten
            local progress eta speed
            # Standardwerte, falls die Zeile nicht geparst werden kann (z.B. Download startet gerade)
            progress=$(echo "$last_line" | sed -n 's/.* \([0-9]\+%\).*/\1/p' | sed 's/%//g')
            progress=${progress:-0}
            speed=$(echo "$last_line" | sed -n 's/.* \([0-9.,]*[KMGT]B\/s\).*/\1/p')
            speed=${speed:-"N/A"}
            eta=$(echo "$last_line" | sed -n 's/.*eta \([0-9ms h]*\).*/\1/p')
            eta=${eta:-"N/A"}

            table_rows+=("$filename,${progress}%,$speed,$eta")
        done
        # Zeige die Tabelle an
        gum table --separator="," --widths="auto,10,15,15" "${table_rows[@]}"
    fi
    gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 4
}

# Hilfsfunktion, um Geschwindigkeits-Strings (z.B. 1.2MB/s) in KB/s umzuwandeln
parse_speed_to_kb() {
    local speed_str="$1"
    if [[ -z "$speed_str" ]]; then
        echo 0
        return
    fi

    # Extrahiere den numerischen Wert und ersetze Komma durch Punkt
    local speed_val
    speed_val=$(echo "$speed_str" | sed -n 's/\([0-9.,]\+\).*/\1/p' | tr ',' '.')
    
    # Umrechnung basierend auf der Einheit
    case "$speed_str" in
        *GB/s)
            echo "$speed_val * 1024 * 1024" | bc
            ;;
        *MB/s)
            echo "$speed_val * 1024" | bc
            ;;
        *KB/s)
            echo "$speed_val" | bc
            ;;
        *B/s)
            echo "$speed_val / 1024" | bc
            ;;
        *)
            echo 0
            ;;
    esac
}

# Hilfsfunktion, um KB/s in ein lesbares Format umzuwandeln
format_speed_from_kb() {
    local total_kb="$1"
    if (( $(echo "$total_kb > 1024" | bc -l) )); then
        printf "%.2f MB/s\n" "$(echo "$total_kb / 1024" | bc -l)"
    else
        printf "%.2f KB/s\n" "$total_kb"
    fi
}

# Hilfsfunktion, um Bytes in ein lesbares Format umzuwandeln
format_size_from_bytes() {
    local bytes="$1"
    if (( $(echo "$bytes >= 1024*1024*1024" | bc -l) )); then
        printf "%.2f GB\n" "$(echo "$bytes / (1024*1024*1024)" | bc -l)"
    elif (( $(echo "$bytes >= 1024*1024" | bc -l) )); then
        printf "%.2f MB\n" "$(echo "$bytes / (1024*1024)" | bc -l)"
    elif (( $(echo "$bytes >= 1024" | bc -l) )); then
        printf "%.2f KB\n" "$(echo "$bytes / 1024" | bc -l)"
    else
        printf "%d Bytes\n" "$bytes"
    fi
}

# Hilfsfunktion, um Größenangaben (z.B. 1.2G, 500M) in Bytes umzuwandeln
parse_size_to_bytes() {
    local size_str="$1"
    if [[ -z "$size_str" ]]; then
        echo 0
        return
    fi

    # Extrahiere den numerischen Wert und die Einheit
    local num val
    num=$(echo "$size_str" | sed -e 's/[a-zA-Z]//g' -e 's/,/./g')
    
    # bc mag keine führenden Punkte
    if [[ $num == .* ]]; then
        num="0$num"
    fi

    case "$size_str" in
        *G) val=$(echo "$num * 1024 * 1024 * 1024" | bc) ;;
        *M) val=$(echo "$num * 1024 * 1024" | bc) ;;
        *K) val=$(echo "$num * 1024" | bc) ;;
        *B) val=$(echo "$num" | bc) ;;
        *)  val=0 ;;
    esac
    # Runden, da bc Nachkommastellen erzeugt
    printf "%.0f\n" "$val"
}

# Funktion zum Abbrechen aller laufenden Hintergrund-Downloads
cancel_background_downloads() {
    gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Alle Downloads abbrechen"

    local pids
    pids=$(pgrep -f "wget -b -q -c -P .*${BASE_URL}")

    if [ -z "$pids" ]; then
        gum style --padding "1" "Keine laufenden Hintergrund-Downloads gefunden."
    else
        gum style "Folgende Hintergrund-Downloads sind aktiv:"
        ps -o pid,args -p "$pids" | grep "${BASE_URL}"

        if gum confirm "Möchten Sie wirklich alle diese Downloads abbrechen?"; then
            kill $pids 2>/dev/null
            gum style --foreground 10 "Alle laufenden Hintergrund-Downloads wurden abgebrochen."
        else
            gum style --foreground 212 "Vorgang abgebrochen."
        fi
    fi

    gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 2
}

# Funktion zum Leeren der wget-Log-Datei
clear_download_log() {
    local log_file="$PROJECT_ROOT/logs/wget-log" # Assuming wget-log is in PROJECT_ROOT/logs
    gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Wget Log-Datei leeren"
    if [ -f "$log_file" ]; then
        if gum confirm "Möchten Sie die Log-Datei '$log_file' wirklich leeren?"; then
            rm "$log_file"
            gum style --foreground 10 "Log-Datei wurde geleert."
        else
            gum style --foreground 212 "Vorgang abgebrochen."
        fi
    else
        gum style --foreground 212 "Keine Log-Datei ('$log_file') zum Leeren gefunden."
    fi
    gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 2

}

# Funktion zum Entfernen alter Log-Dateien von abgeschlossenen Downloads
cleanup_stale_logs() {
    gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Abgeschlossene Download-Logs entfernen"
    mkdir -p "$PROJECT_ROOT/logs"
    # Finde alle .log Dateien im Download-Verzeichnis
    local log_files
    log_files=$(find "$PROJECT_ROOT/logs" -maxdepth 1 -type f -name "*.log")

    if [ -z "$log_files" ]; then
        gum style --padding "1" "Keine Log-Dateien zum Entfernen gefunden."
    else
        gum style "Die folgenden Log-Dateien werden entfernt:"
        printf "  - %s\n" "$log_files" | xargs -d '\n' -I {} basename {}
        if gum confirm "Möchten Sie wirklich fortfahren?"; then
            rm -f $log_files && echo -e "${C_GREEN}Alle gefundenen Log-Dateien wurden entfernt.${C_RESET}"
        else
            gum style --foreground 212 "Vorgang abgebrochen."
        fi
    fi
    gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 2
}
# Funktion zur Überprüfung von Abhängigkeiten
check_dependencies() {
    # Check for 'gum' first, as it is needed for the UI of this script.
    if ! command -v "gum" &> /dev/null; then
        echo -e "${C_YELLOW}Warnung: Das benötigte Programm 'gum' ist nicht installiert.${C_RESET}"
        read -r -p "Möchten Sie 'gum' jetzt automatisch installieren? [y/N] " response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            install_package "gum"
            if ! command -v "gum" &> /dev/null; then
                echo -e "${C_RED}Fehler: Installation von 'gum' fehlgeschlagen. Bitte installieren Sie es manuell von https://github.com/charmbracelet/gum${C_RESET}" >&2
                exit 1
            fi
        else
            echo -e "${C_RED}Fehler: 'gum' wird für dieses Skript benötigt.${C_RESET}" >&2
            echo -e "${C_CYAN}Bitte installieren Sie 'gum' von https://github.com/charmbracelet/gum${C_RESET}" >&2
            exit 1
        fi
    fi

    # Now verify other dependencies using gum for the UI
    for cmd in "$@"; do
        # We already checked gum, helpful to skip if passed in args
        if [[ "$cmd" == "gum" ]]; then continue; fi

        if ! command -v "$cmd" &> /dev/null; then
            if gum confirm "Warnung: Das benötigte Programm '$cmd' ist nicht installiert. Jetzt installieren?"; then
                install_package "$cmd"
                # Erneute Prüfung nach der Installation
                if ! command -v "$cmd" &> /dev/null; then
                    echo -e "${C_RED}Fehler: Installation von '$cmd' fehlgeschlagen oder Programm wurde nicht gefunden. Bitte installieren Sie es manuell.${C_RESET}" >&2
                    exit 1
                fi
            else
                echo -e "${C_RED}Fehler: '$cmd' ist für die Ausführung des Skripts erforderlich.${C_RESET}" >&2
                exit 1
            fi
        fi
    done
}

# Funktion zum Installieren von Paketen basierend auf dem erkannten Paketmanager
install_package() {
    local cmd_to_install="$1"
    local package_name="$cmd_to_install"

    # Paketnamen-Anpassungen für verschiedene Distributionen
    if [[ "$cmd_to_install" == "7z" ]]; then
        package_name="p7zip" # Standardname
    fi

    if command -v apt-get &> /dev/null; then
        echo "Debian/Ubuntu-basiertes System erkannt. Verwende 'apt-get'."
        if [[ "$cmd_to_install" == "7z" ]]; then package_name="p7zip-full"; fi
        sudo apt-get update && sudo apt-get install -y "$package_name"
    elif command -v pacman &> /dev/null; then
        echo "Arch-basiertes System erkannt. Verwende 'pacman'."
        if [[ "$cmd_to_install" == "7z" ]]; then package_name="p7zip"; fi
        sudo pacman -Syu --noconfirm "$package_name"
    elif command -v dnf &> /dev/null; then
        echo "Fedora/CentOS-basiertes System erkannt. Verwende 'dnf'."
        if [[ "$cmd_to_install" == "7z" ]]; then package_name="p7zip-plugins"; fi
        sudo dnf install -y "$package_name"
    elif command -v yum &> /dev/null; then
        echo "RHEL/CentOS-basiertes System erkannt. Verwende 'yum'."
        if [[ "$cmd_to_install" == "7z" ]]; then package_name="p7zip-plugins"; fi
        sudo yum install -y "$package_name"
    elif command -v brew &> /dev/null; then
        echo "macOS mit Homebrew erkannt. Verwende 'brew'."
        if [[ "$cmd_to_install" == "7z" ]]; then package_name="p7zip"; fi
        brew install "$package_name"
    else
        echo -e "${C_RED}Fehler: Konnte keinen unterstützten Paketmanager (apt, pacman, dnf, yum, brew) erkennen.${C_RESET}"
        echo "Bitte installieren Sie '$package_name' manuell."
        return 1
    fi
}

# Funktion zum Laden der Konfiguration
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # echo "Lade Konfiguration von $CONFIG_FILE..." # Silent on purpose
        # source the config file to load variables
        # shellcheck source=/dev/null
        . "$CONFIG_FILE"
        return 0 # Success
    else
        return 1 # Not found
    fi
}

# Funktion zum Speichern der Konfiguration
save_config() { # Akzeptiert ein optionales Argument, um die "Weiter"-Meldung zu unterdrücken
    echo -e "${HEADLINE_COLOR}Speichere aktuelle Einstellungen in $CONFIG_FILE...${C_RESET}"
    # Write current settings to the config file
    {
        echo "DOWNLOAD_DIR=\"$DOWNLOAD_DIR\""
        echo "AUTO_VERIFY=\"$AUTO_VERIFY\""
        echo "MAX_CONCURRENT_DOWNLOADS=$MAX_CONCURRENT_DOWNLOADS"
        echo "DELETE_ARCHIVE_AFTER_EXTRACT=\"$DELETE_ARCHIVE_AFTER_EXTRACT\""
        echo "AUTO_EXTRACT=\"$AUTO_EXTRACT\""
        echo "AUTO_UPDATE_CHECK=\"$AUTO_UPDATE_CHECK\""
        echo "SEARCH_REGIONS=\"$SEARCH_REGIONS\""
        echo "DISCLAIMER_ACCEPTED=\"$DISCLAIMER_ACCEPTED\""
        echo "SEARCH_EXCLUDE_KEYWORDS=\"$SEARCH_EXCLUDE_KEYWORDS\""
        echo "DOWNLOAD_SPEED_LIMIT=\"$DOWNLOAD_SPEED_LIMIT\""
        echo "RE_DOWNLOAD_POLICY=\"$RE_DOWNLOAD_POLICY\""
    } > "$CONFIG_FILE"
    echo -e "${C_GREEN}Einstellungen gespeichert.${C_RESET}"
}

# Funktion zum Zurücksetzen der Konfiguration
reset_config() {
    gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Konfiguration zurücksetzen"

    if [ ! -f "$CONFIG_FILE" ]; then
        gum style --foreground 212 "Keine Konfigurationsdatei ($CONFIG_FILE) zum Zurücksetzen gefunden."
    else
        if gum confirm "Möchten Sie die Konfiguration wirklich auf die Standardwerte zurücksetzen?"; then
            rm -f "$CONFIG_FILE"
            # Reset runtime variables to default
            DOWNLOAD_DIR="./downloads"
            AUTO_VERIFY="yes"
            MAX_CONCURRENT_DOWNLOADS=3
            DELETE_ARCHIVE_AFTER_EXTRACT="yes"
            AUTO_EXTRACT="yes"
            AUTO_UPDATE_CHECK="yes"
            SEARCH_REGIONS=""
            DISCLAIMER_ACCEPTED="no"
            SEARCH_EXCLUDE_KEYWORDS="Demo Beta"
            DOWNLOAD_SPEED_LIMIT="0"
            RE_DOWNLOAD_POLICY="ask"
            gum style --foreground 10 "Konfigurationsdatei entfernt und Einstellungen auf Standardwerte zurückgesetzt."
        else
            echo -e "${C_YELLOW}Vorgang abgebrochen.${C_RESET}"
        fi
    fi
    gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 2
}

# Funktion zum Bearbeiten der Konfigurationsdatei
edit_config_file() {
    local editor
    if [[ -n "$EDITOR" ]]; then
        editor="$EDITOR"
    elif command -v nano &> /dev/null; then
        editor="nano"
    elif command -v vim &> /dev/null; then
        editor="vim"
    elif command -v vi &> /dev/null; then
        editor="vi"
    else
        gum style --border normal --margin "1" --padding "1" --border-foreground 9 "Fehler: Kein Editor gefunden." "Bitte setzen Sie die EDITOR-Umgebungsvariable (z.B. export EDITOR=nano)."
        gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 3
        return
    fi

    gum spin --title "Öffne Konfigurationsdatei '$CONFIG_FILE' mit '$editor'..." -- sleep 1
    "$editor" "$CONFIG_FILE"

    load_config
    gum spin --title "Konfiguration neu geladen. Kehre zum Hauptmenü zurück..." -- sleep 2
}

# Funktion zum Sichern der Konfiguration
backup_config() {
    gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Konfiguration sichern"
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${C_YELLOW}Keine Konfigurationsdatei ($CONFIG_FILE) zum Sichern gefunden.${C_RESET}"
    else
        local backup_file="${CONFIG_FILE}.$(date +%Y-%m-%d_%H-%M-%S).bak"
        mkdir -p "$PROJECT_ROOT/backups"
        cp "$CONFIG_FILE" "$PROJECT_ROOT/backups/$backup_file"
        if [[ $? -eq 0 ]]; then
            echo -e "${C_GREEN}Konfigurationsdatei wurde erfolgreich gesichert nach: ${C_WHITE}$backup_file${C_RESET}"
        else
            echo -e "${C_RED}Fehler beim Erstellen der Sicherungskopie.${C_RESET}"
        fi
    fi
    gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 2
}

# Funktion zum Anzeigen der Gesamtgröße aller heruntergeladenen Dateien
show_total_download_size() {
    gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Gesamtgröße der Downloads"

    if [ ! -d "$DOWNLOAD_DIR" ]; then
        gum style --padding "1" "Download-Verzeichnis '$DOWNLOAD_DIR' nicht gefunden."
    else
        local total_bytes total_size_hr
        total_bytes=$(gum spin --title "Berechne Größe..." -- du -sb "$DOWNLOAD_DIR" | awk '{print $1}')

        if [ -n "$total_bytes" ]; then
            total_size_hr=$(format_size_from_bytes "$total_bytes")
            gum style "Gesamtgröße in '$(gum style --bold "$DOWNLOAD_DIR")': $(gum style --bold --foreground 10 "$total_size_hr")"
        else
            gum style --foreground 9 "Größe konnte nicht berechnet werden."
        fi
    fi
    gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 3
}

# Funktion zum Wiederherstellen einer Konfiguration
restore_config() {
    gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Konfiguration wiederherstellen"

    # Finde alle .bak Dateien, die zum Config-File gehören
    mapfile -t backup_files < <(find "$PROJECT_ROOT/backups" -maxdepth 1 -type f -name "$(basename "$CONFIG_FILE").*.bak" | sort -r)

    if [ ${#backup_files[@]} -eq 0 ]; then
        echo -e "${C_YELLOW}Keine Backup-Dateien gefunden.${C_RESET}"
    else
        echo "Bitte wählen Sie eine wiederherzustellende Backup-Datei aus:"
        local backup_files_display=()
        for f in "${backup_files[@]}"; do backup_files_display+=("$(basename "$f")"); done

        local choice
        choice=$(gum choose "${backup_files_display[@]}" "Abbrechen")

        if [[ -n "$choice" && "$choice" != "Abbrechen" ]]; then
            local backup_file="$PROJECT_ROOT/backups/$choice"
            if gum confirm "Möchten Sie '$CONFIG_FILE' wirklich mit '$choice' überschreiben?"; then
                cp "$backup_file" "$CONFIG_FILE"
                load_config
            else
                gum style --foreground 212 "Wiederherstellung abgebrochen."
            fi
        fi
    fi
    gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 2
}

# Funktion zum Festlegen der maximalen Anzahl gleichzeitiger Downloads
set_max_downloads() {
    local no_save="$1"
    gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Maximale Anzahl gleichzeitiger Downloads"
    new_max=$(gum input --placeholder "Anzahl eingeben..." --value "$MAX_CONCURRENT_DOWNLOADS")

    if [[ -z "$new_max" ]]; then
        echo -e "${C_YELLOW}Keine Änderung vorgenommen.${C_RESET}"
    elif ! [[ "$new_max" =~ ^[1-9][0-9]*$ && "$new_max" -le 10 ]]; then
        echo -e "${C_RED}Ungültige Eingabe. Bitte geben Sie eine positive Zahl ein.${C_RESET}"
    else
        MAX_CONCURRENT_DOWNLOADS=$new_max
        echo -e "${C_GREEN}Maximale Anzahl gleichzeitiger Downloads auf ${C_WHITE}$MAX_CONCURRENT_DOWNLOADS${C_GREEN} gesetzt.${C_RESET}"
        if [[ "$no_save" != "no_save" ]]; then
            save_config "suppress_message"
        fi
    fi
    gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 2
}

# Funktion zum Umschalten der automatischen Verifizierung
toggle_auto_verify() {
    local no_save="$1"
    gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Automatische Verifizierung umschalten"
    if [[ "$AUTO_VERIFY" == "yes" ]]; then
        AUTO_VERIFY="no"
        gum style --foreground 9 "Automatische Prüfsummen-Verifizierung ist jetzt DEAKTIVIERT."
    else
        AUTO_VERIFY="yes"
        gum style --foreground 10 "Automatische Prüfsummen-Verifizierung ist jetzt AKTIVIERT."
    fi
    if [[ "$no_save" != "no_save" ]]; then
        save_config "suppress_message"
    fi
    gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 1
}

# Funktion zum Umschalten des automatischen Entpackens
toggle_auto_extract() {
    local no_save="$1"
    gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Automatisches Entpacken umschalten"
    if [[ "$AUTO_EXTRACT" == "yes" ]]; then
        AUTO_EXTRACT="no"
        gum style --foreground 9 "Automatisches Entpacken nach dem Download ist jetzt DEAKTIVIERT."
    else
        AUTO_EXTRACT="yes"
        gum style --foreground 10 "Automatisches Entpacken nach dem Download ist jetzt AKTIVIERT."
    fi
    if [[ "$no_save" != "no_save" ]]; then
        save_config "suppress_message"
    fi
    gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 1
}

cleanup_backups() {
    gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Veraltete Backups löschen"
    mapfile -t backup_files < <(find "$PROJECT_ROOT/backups" -maxdepth 1 -type f -name "$(basename "$CONFIG_FILE").*.bak" | sort -r)

    if [ ${#backup_files[@]} -lt 2 ]; then
        gum style --padding "1" "Nicht genügend Backups zum Aufräumen gefunden (weniger als 2)."
    else
        local num_to_keep
        num_to_keep=$(gum input --placeholder "Anzahl zu behaltender Backups..." --value "5")

        if ! [[ "$num_to_keep" =~ ^[0-9]+$ ]]; then
            gum style --foreground 9 "Ungültige Eingabe. Bitte geben Sie eine Zahl ein."
        elif [ "${#backup_files[@]}" -le "$num_to_keep" ]; then
            gum style --padding "1" "Anzahl der Backups (${#backup_files[@]}) ist bereits passend. Nichts zu tun."
        else
            # Die Liste ist von neu nach alt sortiert. Wir löschen alle nach den ersten 'num_to_keep'.
            local files_to_delete=("${backup_files[@]:$num_to_keep}")
            
            gum style "Die folgenden ${#files_to_delete[@]} veralteten Backup-Dateien werden gelöscht:"
            printf "  - %s\n" "${files_to_delete[@]}" | xargs -d '\n' -I {} basename {} | sed 's/^/  - /'

            if gum confirm "Möchten Sie wirklich fortfahren?"; then
                for file in "${files_to_delete[@]}"; do
                    rm "$file" && echo -e "${C_GREEN}Gelöscht: $(basename "$file")${C_RESET}"
                done
                gum style --foreground 10 "Veraltete Backups wurden gelöscht."
            else
                echo -e "${C_YELLOW}Vorgang abgebrochen.${C_RESET}"
            fi
        fi
    fi
    gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 2
}

# Funktion zur Überprüfung der Dateiintegrität mittels Prüfsumme
verify_file_integrity() {
    local local_filepath="$1"
    local silent="$2"
    local filename
    filename=$(basename "$local_filepath")

    # Suche nach einer passenden Prüfsummendatei (.md5 oder .sha1)
    local checksum_type=""
    local checksum_file_entry=""
    checksum_file_entry=$(printf '%s\n' "${all_games[@]}" | grep -F -- "${filename}.md5") && checksum_type="md5"
    if [ -z "$checksum_file_entry" ]; then
        checksum_file_entry=$(printf '%s\n' "${all_games[@]}" | grep -F -- "${filename}.sha1") && checksum_type="sha1"
    fi

    if [ -n "$checksum_file_entry" ]; then
        if [[ "$AUTO_VERIFY" != "yes" ]]; then
            if [[ "$silent" == "silent" ]]; then
                echo "Automatische Verifizierung übersprungen (AUTO_VERIFY != yes)."
                return
            fi
            gum confirm "Prüfsummendatei gefunden. '$filename' verifizieren?" || return
        else
            if [[ "$silent" == "silent" ]]; then
                echo "Verifiziere '$filename'..."
            else
                echo -e "${C_CYAN}Automatische Verifizierung wird für '${C_WHITE}$filename${C_CYAN}' durchgeführt...${C_RESET}"
            fi
        fi

        local checksum_remote_path
        checksum_remote_path=$(echo "$checksum_file_entry" | awk '{print $1}')
        local temp_checksum_file
        temp_checksum_file=$(mktemp)

        if [[ "$silent" == "silent" ]]; then
            echo "Lade Prüfsummendatei herunter..."
            wget -q -O "$temp_checksum_file" --limit-rate="$DOWNLOAD_SPEED_LIMIT" -- "${BASE_URL}${checksum_remote_path}"
             echo "Verifiziere Datei..."
        else
            echo -e "${C_CYAN}Lade Prüfsummendatei herunter...${C_RESET}"        
            gum spin --spinner dot --title "Lade Prüfsummendatei herunter..." -- wget -q -O "$temp_checksum_file" --limit-rate="$DOWNLOAD_SPEED_LIMIT" -- "${BASE_URL}${checksum_remote_path}"
            echo -e "${C_CYAN}Verifiziere Datei (dies kann dauern)...${C_RESET}"
        fi

        # Prüfsumme aus Datei extrahieren (erster Block)
        local expected_checksum
        expected_checksum=$(cut -d' ' -f1 < "$temp_checksum_file")

        # cd in das Verzeichnis, da manche .md5/.sha1-Dateien nur den Dateinamen enthalten
        if (cd "$DOWNLOAD_DIR" && "${checksum_type}sum" -c <(echo "$expected_checksum  $filename") >/dev/null 2>&1); then
             if [[ "$silent" == "silent" ]]; then
                echo "Verifikation erfolgreich: $filename"
             else
                gum style --foreground 10 "Verifikation erfolgreich!"
             fi
        else
             if [[ "$silent" == "silent" ]]; then
                echo "VERIFIKATION FEHLGESCHLAGEN: $filename"
             else
                gum style --foreground 9 "Verifikation FEHLGESCHLAGEN!"
             fi
        fi
        rm "$temp_checksum_file"
    fi
}

# Funktion zum Drucken einer horizontalen Linie über die gesamte Breite
print_horizontal_line() {
    printf "%*s\n" "$(tput cols)" "" | tr ' ' '-'
}

# Funktion zum Anzeigen des Headers und der Konfiguration
show_header() {
    clear
    local logo
    logo=$(gum style --foreground 5 "                          _____            _____             __________
_______ ________  ___________(_)_____________  /_      _________  /__(_)
__  __ \`__ \\_  / / /_  ___/_  /_  _ \\_  __ \\  __/_______  ___/_  /__  /
_  / / / / /  /_/ /_  /   _  / /  __/  / / / /_ _/_____/ /__ _  / _  /
/_/ /_/ /_/_\__, / /_/    /_/  \\___//_/ /_/\__/        \\___/ /_/  /_/
           /____/")

    local title
    title=$(gum style --bold "Myrient-CLI v${VERSION} (unofficial)")

    local ip_info
    if [[ -n "$IP_ADDRESS" ]]; then
        ip_info=$(gum style "IP: $(gum style --bold "$IP_ADDRESS")  Standort: $(gum style --bold "$IP_LOCATION")")
    else
        ip_info=$(gum style --foreground 240 "Lade IP-Informationen...")
    fi

    local content
    content=$(gum join --align center --vertical "$logo" "$title" " " "$ip_info")

    gum style --padding "1 2" --border rounded --border-foreground 5 "$content"
}

# Funktion für die Ersteinrichtung
initial_setup() {
    gum style --border double --margin "1" --padding "1" --border-foreground 212 "Willkommen zur Ersteinrichtung von myrient-cli" "Wir werden nun einige Grundeinstellungen vornehmen."
    
    set_download_directory "no_save"
    
    local max_dl
    max_dl=$(gum input --header "Maximale Anzahl gleichzeitiger Downloads" --value "3")
    if [[ "$max_dl" =~ ^[1-9][0-9]*$ ]]; then
        MAX_CONCURRENT_DOWNLOADS=$max_dl
    fi

    if gum confirm "Sollen heruntergeladene Dateien automatisch verifiziert werden?"; then
        AUTO_VERIFY="yes"
    else
        AUTO_VERIFY="no"
    fi

    if gum confirm "Soll beim Start automatisch nach Updates gesucht werden?"; then
        AUTO_UPDATE_CHECK="yes"
    else
        AUTO_UPDATE_CHECK="no"
    fi
    
    if gum confirm "Sollen heruntergeladene Archive (.zip, .7z) automatisch entpackt werden?"; then
        AUTO_EXTRACT="yes"
    else
        AUTO_EXTRACT="no"
    fi

    if gum confirm "Sollen Archive nach dem Entpacken automatisch gelöscht werden?"; then
        DELETE_ARCHIVE_AFTER_EXTRACT="yes"
    else
        DELETE_ARCHIVE_AFTER_EXTRACT="no"
    fi
    
    SEARCH_REGIONS=$(gum input --header "Bevorzugte Suchregionen (z.B. 'Europe Germany')" --placeholder "Leer lassen für keine...")
    
    SEARCH_EXCLUDE_KEYWORDS=$(gum input --header "Auszuschließende Suchbegriffe" --value "Demo Beta")
    DISCLAIMER_ACCEPTED="yes" # Bei der Ersteinrichtung wird der Disclaimer als akzeptiert gesetzt
    
    DOWNLOAD_SPEED_LIMIT=$(gum input --header "Download-Geschwindigkeitsbegrenzung (z.B. 500k, 2m)" --placeholder "Leer lassen für unbegrenzt...")
    DOWNLOAD_SPEED_LIMIT="${DOWNLOAD_SPEED_LIMIT:-0}"
    
    local policy_choice
    policy_choice=$(gum choose --header "Wie soll mit bereits heruntergeladenen Spielen verfahren werden?" "Nachfragen (Standard)" "Immer erneut herunterladen" "Überspringen")
    case "$policy_choice" in
        "Immer erneut herunterladen") RE_DOWNLOAD_POLICY="always" ;;
        "Überspringen") RE_DOWNLOAD_POLICY="skip" ;;
        *) RE_DOWNLOAD_POLICY="ask" ;;
    esac

    # Speichern ist hier entscheidend, bevor das Skript in main() neu gestartet wird.
    save_config
    gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 2
}

# Funktion zum Anzeigen des Haftungsausschlusses und Einholen der Zustimmung
show_disclaimer_and_get_agreement() {
    if [[ "$DISCLAIMER_ACCEPTED" == "yes" ]]; then
        return 0
    fi

    local disclaimer_text
    disclaimer_text=$(gum style \
        "$(gum style --bold 'Bitte lesen Sie die folgenden Hinweise sorgfältig durch:')" \
        "" \
        "1. $(gum style --bold 'Keine Zugehörigkeit:') Der Entwickler dieses Skripts steht in keinerlei Verbindung zu den Betreibern von Myrient. Das Skript ist ein unabhängiges Projekt." \
        "" \
        "2. $(gum style --bold 'Rechtliche Verantwortung:') Sie als Nutzer sind allein für die Einhaltung der geltenden Gesetze in Ihrem Land verantwortlich. Das Herunterladen von urheberrechtlich geschütztem Material kann illegal sein." \
        "" \
        "3. $(gum style --bold 'Distanzierung von illegalen Aktivitäten:') Der Entwickler distanziert sich ausdrücklich von jeglicher Form illegaler Downloads. Das Skript ist nicht für rechtswidrige Zwecke bestimmt." \
        "" \
        "4. $(gum style --bold 'Nutzung auf eigene Gefahr:') Die Nutzung des Skripts erfolgt auf Ihr eigenes Risiko. Es wird keine Garantie für Funktionalität oder Sicherheit übernommen." \
        "" \
        "Indem Sie fortfahren, bestätigen Sie, diesen Haftungsausschluss gelesen zu haben und das Skript ausschließlich für legale Zwecke zu verwenden.")

    if gum confirm "$disclaimer_text" --affirmative="Zustimmen" --negative="Ablehnen"; then
        DISCLAIMER_ACCEPTED="yes"
        save_config "suppress_message"
        echo -e "${C_GREEN}Vielen Dank. Das Skript wird nun gestartet.${C_RESET}"
        sleep 2
    else
        echo -e "${C_RED}Sie müssen den Bedingungen zustimmen, um das Skript zu verwenden. Das Skript wird beendet.${C_RESET}"
        exit 1
    fi
}

# Funktion zum Widerrufen der Zustimmung zum Haftungsausschluss
revoke_disclaimer_agreement() {
    if gum confirm "Möchten Sie Ihre Zustimmung zum Haftungsausschluss widerrufen?" "Das Skript wird danach beendet."; then
        DISCLAIMER_ACCEPTED="no"
        save_config "suppress_message"
        gum spin --title "Ihre Zustimmung wurde widerrufen. Das Skript wird jetzt beendet..." -- sleep 3
        exit 0
    else
        echo -e "${C_YELLOW}Vorgang abgebrochen. Ihre Zustimmung bleibt bestehen.${C_RESET}"
    fi
}

# Funktion zum einmaligen Abrufen der IP-Adresse und des Standorts
fetch_ip_info() {
    # Führe dies nur aus, wenn die IP-Adresse noch nicht bekannt ist oder "N/A" ist (Retry-Möglichkeit)
    if [[ -z "$IP_ADDRESS" || "$IP_ADDRESS" == "N/A" ]]; then
        local response
        # Verwende einen Timeout, um das Skript nicht zu blockieren.
        # "|| true" verhindert, dass set -e das Skript bei Netzwerkfehlern beendet.
        # Verwende HTTPS explizit.
        response=$(curl -s --connect-timeout 3 "https://ipinfo.io/json" || true)

        if [[ -n "$response" ]]; then
            # Extrahiere die Daten aus der JSON-Antwort
            local ip=$(echo "$response" | grep -o '"ip": *"[^"]*"' | cut -d'"' -f4)
            
            if [[ -n "$ip" ]]; then
                IP_ADDRESS="$ip"
                local city=$(echo "$response" | grep -o '"city": *"[^"]*"' | cut -d'"' -f4)
                local region=$(echo "$response" | grep -o '"region": *"[^"]*"' | cut -d'"' -f4)
                local country=$(echo "$response" | grep -o '"country": *"[^"]*"' | cut -d'"' -f4)
                IP_LOCATION="${city}, ${region}, ${country}"
                # Bereinige mögliche leere Felder (z.B. ", , Country")
                IP_LOCATION=$(echo "$IP_LOCATION" | sed 's/^, //; s/, , /, /; s/, $//')
            fi
        fi

        # Fallback, falls fehlgeschlagen
        if [[ -z "$IP_ADDRESS" ]]; then
            IP_ADDRESS="N/A"
            IP_LOCATION="N/A"
        fi
    fi
}

# Funktion zum Festlegen der Download-Geschwindigkeitsbegrenzung
set_download_speed_limit() {
    local no_save="$1"
    gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Download-Geschwindigkeit festlegen"
    gum style "Geben Sie ein Limit an (z.B. '500k', '1.5m'). Leer für unbegrenzt."

    local current_limit_display
    if [[ "$DOWNLOAD_SPEED_LIMIT" == "0" ]]; then
        current_limit_display="Unbegrenzt"
    else
        current_limit_display="$DOWNLOAD_SPEED_LIMIT"
    fi

    new_limit=$(gum input --placeholder "Limit eingeben..." --value "$current_limit_display")
    DOWNLOAD_SPEED_LIMIT="${new_limit:-0}"

    echo -e "${C_GREEN}Download-Geschwindigkeitsbegrenzung auf '${DOWNLOAD_SPEED_LIMIT}' gesetzt.${C_RESET}"
    save_config "suppress_message"
    gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 2
}

# Funktion zum Festlegen der Richtlinie für erneute Downloads
set_re_download_policy() {
    local no_save="$1"
    clear
    echo -e "${HEADLINE_COLOR}Richtlinie für erneute Downloads festlegen${C_RESET}\n"
    echo "Legen Sie fest, wie das Skript verfahren soll, wenn ein Spiel"
    echo "bereits im Download-Verlauf vorhanden ist."

    policy_choice=$(gum choose "Nachfragen (ask)" "Immer (always)" "Überspringen (skip)")

    case "$policy_choice" in
        "Nachfragen (ask)") RE_DOWNLOAD_POLICY="ask" ;;
        "Immer (always)") RE_DOWNLOAD_POLICY="always" ;;
        "Überspringen (skip)") RE_DOWNLOAD_POLICY="skip" ;;
        *) # This case should ideally not be reached with gum choose
            echo -e "${C_RED}Ungültige Auswahl. Keine Änderung vorgenommen.${C_RESET}"
            gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 2
            return
            ;;
    esac
    echo -e "${C_GREEN}Richtlinie für erneute Downloads auf '${C_WHITE}$RE_DOWNLOAD_POLICY${C_GREEN}' gesetzt.${C_RESET}"
    save_config "suppress_message"
    gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 2
}

# Funktion zum Anzeigen des Download-Verlaufs
show_download_history() {
    gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Download-Verlauf"

    if [ ! -f "$DOWNLOAD_HISTORY_LOG" ] || [ ! -s "$DOWNLOAD_HISTORY_LOG" ]; then
        gum style --padding "1" "Es wurden noch keine Downloads protokolliert."
    else
        # Zeige den Verlauf mit gum filter an, was eine interaktive Suche ermöglicht.
        # --height 20 begrenzt die Höhe der Liste.
        # Die Ausgabe von gum filter wird unterdrückt, da wir nur die Anzeige wollen.
        gum style "Drücken Sie ESC, um die Ansicht zu verlassen."
        <"$DOWNLOAD_HISTORY_LOG" gum filter --placeholder "Verlauf durchsuchen..." --height 20 > /dev/null

        # Frage danach, ob der Verlauf geleert werden soll.
        if gum confirm "Möchten Sie den gesamten Download-Verlauf leeren?"; then
            rm "$DOWNLOAD_HISTORY_LOG"
            gum style --foreground 10 "Der Download-Verlauf wurde geleert."
        else
            gum style --foreground 212 "Vorgang abgebrochen."
        fi
    fi

    gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 2
}

# Funktion zum Entfernen doppelter Einträge aus dem Download-Verlauf
deduplicate_download_history() {
    gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Doppelte Einträge im Verlauf entfernen"

    if [ ! -f "$DOWNLOAD_HISTORY_LOG" ] || [ ! -s "$DOWNLOAD_HISTORY_LOG" ]; then
        gum style --padding "1" "Download-Verlauf nicht gefunden oder leer. Nichts zu tun."
    else
        local original_lines
        original_lines=$(wc -l < "$DOWNLOAD_HISTORY_LOG")

        local temp_history_file
        temp_history_file=$(mktemp)

        # Sortiere und entferne Duplikate, behalte die ursprüngliche Reihenfolge der ersten Vorkommen bei
        awk '!seen[$0]++' "$DOWNLOAD_HISTORY_LOG" > "$temp_history_file"

        local unique_lines duplicates_found
        unique_lines=$(wc -l < "$temp_history_file")
        local duplicates_found=$((original_lines - unique_lines))

        if [ "$duplicates_found" -gt 0 ]; then
            if gum confirm "Es wurden $duplicates_found doppelte Einträge gefunden. Möchten Sie diese entfernen?"; then
                mv "$temp_history_file" "$DOWNLOAD_HISTORY_LOG"
                gum style --foreground 10 "Doppelte Einträge wurden erfolgreich entfernt."
            else
                rm "$temp_history_file"
                gum style --foreground 212 "Vorgang abgebrochen."
            fi
        else
            rm "$temp_history_file"
            gum style --padding "1" "Keine doppelten Einträge im Verlauf gefunden."
        fi
    fi
    gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 2
}

# Funktion zum Exportieren des Download-Verlaufs in eine CSV-Datei
export_download_history_to_csv() {
    gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Download-Verlauf als CSV exportieren"

    if [ ! -f "$DOWNLOAD_HISTORY_LOG" ] || [ ! -s "$DOWNLOAD_HISTORY_LOG" ]; then
        gum style --padding "1" "Download-Verlauf nicht gefunden oder leer. Nichts zu exportieren."
    else
        local default_csv_file="$PROJECT_ROOT/myrient_download_history.csv"
        local csv_file
        csv_file=$(gum input --placeholder "Dateipfad für CSV-Export..." --value "$default_csv_file")

        csv_file="${csv_file:-$default_csv_file}"
        eval csv_file="$csv_file"

        if [ -f "$csv_file" ]; then
            if ! gum confirm "Datei '$csv_file' existiert bereits. Überschreiben?"; then
                gum style --foreground 212 "Export abgebrochen."
                gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 2
                return
            fi
        fi

        local lines_exported
        lines_exported=$(gum spin --title "Exportiere Verlauf nach '$csv_file'..." -- bash -c '
            echo "\"Timestamp\",\"Console\",\"Game\"" > "'"$csv_file"'"
            while IFS= read -r line; do
                timestamp=$(echo "$line" | sed -n "s/^\[\([^]]*\)\].*/\1/p")
                console=$(echo "$line" | sed -n "s/.* - \[\([^]]*\)\] - .*/\1/")
                game=$(echo "$line" | sed -n "s/.* - \[.*\] - \(.*\)/\1/p")
                echo "\"$timestamp\",\"$console\",\"$game\"" >> "'"$csv_file"'"
            done < "'"$DOWNLOAD_HISTORY_LOG"'"
            wc -l < "'"$DOWNLOAD_HISTORY_LOG"'"
        ')
        gum style --foreground 10 "Erfolgreich $lines_exported Einträge nach '$csv_file' exportiert."
    fi
    gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 2
}
# Funktion "Über das Skript"
show_about() {
    gum style --border normal --margin "1" --padding "1" --border-foreground 212 \
        "Über Myrient CLI" \
        "Version: $(gum style --bold "$VERSION")" \
        "Beschreibung: Ein Kommandozeilen-Tool zum Durchsuchen und Herunterladen von Inhalten aus dem Myrient-Archiv." \
        "GitHub: $(gum style --underline "https://github.com/${GITHUB_REPO}")" \
        "Lizenz: $(gum style --bold "MIT")"

    gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 4
}

# Funktion zum automatischen Entpacken von Archiven
extract_archive() {
    local filepath="$1"
    local silent="$2"
    local filename
    filename=$(basename "$filepath")
    local extract_dir
    extract_dir="${filepath%.*}" # Verzeichnisname = Dateiname ohne Endung

    if [[ "$silent" != "silent" ]]; then
        gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Entpacke Archiv" "Prüfe, ob '$filename' entpackt werden kann..."
    else
        echo "Prüfe, ob '$filename' entpackt werden kann..."
    fi

    case "$filename" in
        *.zip)
            if [[ "$silent" == "silent" ]]; then
                 echo "STATUS: Entpacke ZIP-Archiv..."
                 if bash -c "mkdir -p \"$extract_dir\" && unzip -q -o \"$filepath\" -d \"$extract_dir\""; then
                    echo "STATUS: Entpacken erfolgreich."
                    if [[ "$DELETE_ARCHIVE_AFTER_EXTRACT" == "yes" ]]; then
                        echo "STATUS: Lösche Archiv..."
                        rm "$filepath" && echo "Archiv '$filename' wurde gelöscht."
                    fi
                 else
                    echo "STATUS: Fehler beim Entpacken."
                 fi
            else
                if gum spin --title "Entpacke ZIP-Archiv nach '$extract_dir'..." -- bash -c "mkdir -p \"$extract_dir\" && unzip -q -o \"$filepath\" -d \"$extract_dir\""; then
                    gum style --foreground 10 "Entpacken erfolgreich."
                    if [[ "$DELETE_ARCHIVE_AFTER_EXTRACT" == "yes" ]]; then
                        rm "$filepath" && gum style --foreground 10 "Archiv '$filename' wurde gelöscht."
                    fi
                else
                    gum style --foreground 9 "Fehler beim Entpacken des ZIP-Archivs."
                fi
            fi
            ;;
        *.7z)
            if [[ "$silent" == "silent" ]]; then
                 echo "STATUS: Bereite Entpacken vor..."
                 # Verwende -bsp1 für Fortschrittsausgabe in 7z
                 if bash -c "mkdir -p \"$extract_dir\" && 7z x \"$filepath\" -o\"$extract_dir\" -y -bsp1"; then
                    echo "STATUS: Entpacken erfolgreich."
                    if [[ "$DELETE_ARCHIVE_AFTER_EXTRACT" == "yes" ]]; then
                        echo "STATUS: Lösche Archiv..."
                        rm "$filepath" && echo "Archiv '$filename' wurde gelöscht."
                    fi
                 else
                     echo "STATUS: Fehler beim Entpacken."
                 fi
            else
                if gum spin --title "Entpacke 7-Zip-Archiv nach '$extract_dir'..." -- bash -c "mkdir -p \"$extract_dir\" && 7z x \"$filepath\" -o\"$extract_dir\" -y > /dev/null"; then
                     gum style --foreground 10 "Entpacken erfolgreich."
                    if [[ "$DELETE_ARCHIVE_AFTER_EXTRACT" == "yes" ]]; then
                        rm "$filepath" && gum style --foreground 10 "Archiv '$filename' wurde gelöscht."
                    fi
                else
                     gum style --foreground 9 "Fehler beim Entpacken des 7-Zip-Archivs."
                fi
            fi
            ;;
        *)
            if [[ "$silent" == "silent" ]]; then
                echo "Kein unterstütztes Archivformat (.zip, .7z) für '$filename' gefunden."
            else
                gum style --foreground 212 "Kein unterstütztes Archivformat (.zip, .7z) für '$filename' gefunden."
            fi
            ;;
    esac
}

# Funktion zum Durchführen des Self-Updates
perform_self_update() {
    local base_url="https://raw.githubusercontent.com/elyps/myrient-cli/refs/heads/main"
    local new_script_url="${base_url}/src/myrient-cli.sh" # Korrigierter Pfad
    local new_version_url="${base_url}/src/VERSION"
    local temp_script_path="$SCRIPT_DIR/myrient-cli.sh.tmp"
    local version_path="$SCRIPT_DIR/VERSION"

    echo "Lade neues Skript von $new_script_url herunter..."

    # Lade das neue Skript in eine temporäre Datei
    if ! curl -sL "$new_script_url" -o "$temp_script_path"; then
        echo "Fehler: Download des neuen Skripts fehlgeschlagen."
        rm -f "$temp_script_path"
        return 1
    fi

    gum spin --spinner dot --title "Lade neue VERSION-Datei herunter..." -- sleep 0.1 # Placeholder for actual download
    # Lade die neue VERSION-Datei direkt
    if ! curl -sL "$new_version_url" -o "$version_path"; then
        echo "Fehler: Download der neuen VERSION-Datei fehlgeschlagen."
        # Das Skript-Update ist trotzdem da, also fahren wir fort, aber mit einer Warnung.
        echo "Warnung: Das Skript wurde aktualisiert, aber die VERSION-Datei konnte nicht aktualisiert werden."
    fi

    # Mache das neue Skript ausführbar
    chmod +x "$temp_script_path"

    # Ersetze das alte Skript durch das neue
    # $0 ist der Pfad, mit dem das Skript aufgerufen wurde
    mv "$temp_script_path" "$0"

    gum style --foreground 10 "Update erfolgreich abgeschlossen!"
    gum style "Bitte starten Sie das Skript neu, um die Änderungen zu übernehmen."
    exit 0
}

# Funktion zum Suchen nach Skript-Updates auf GitHub
check_for_updates() {
    local mode="$1" # "auto" oder "manual"

    if [[ "$mode" == "manual" ]]; then
        gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Suche nach Updates"
    fi

    # Annahme: Die Version steht in einer Datei namens 'VERSION' im src-Verzeichnis des Repos.
    # Extrahiere 'user/repo' aus verschiedenen URL-Formaten
    local repo_path
    repo_path=$(echo "$GITHUB_REPO" | sed -e 's|https://github.com/||' -e 's|\.git$||')
    local version_url="https://raw.githubusercontent.com/elyps/myrient-cli/refs/heads/main/src/VERSION"
    local response
    # "|| true" verhindert, dass set -e das Skript bei Netzwerkfehlern beendet.
    response=$(curl -sL -w "\n%{http_code}" "$version_url" || true)
    local http_code
    http_code=$(echo "$response" | tail -n1)
    local latest_version
    latest_version=$(echo "$response" | sed '$d')

    if [[ "$http_code" -ne 200 ]]; then
        if [[ "$mode" == "manual" ]]; then
            gum style --foreground 9 "Fehler: Konnte die neueste Version nicht von GitHub abrufen (HTTP-Status: $http_code)."
        fi
    else
        # Extrahiere die Versionsnummer aus "VERSION=1.2.3"
        latest_version=$(echo "$latest_version" | cut -d'=' -f2)
        # Verwende sort -V für einen robusten Versionsvergleich. Wenn die aktuelle Version die gleiche oder neuer ist, dann ist es aktuell.
        if [[ "$(printf '%s\n' "$VERSION" "$latest_version" | sort -V | tail -n 1)" == "$VERSION" ]] && [[ "$VERSION" == "$latest_version" ]]; then
            if [[ "$mode" == "manual" ]]; then
                gum style --foreground 10 "Sie verwenden bereits die neueste Version ($VERSION)."
            fi
        else
            if gum confirm "Eine neue Version ($latest_version) ist verfügbar! Jetzt aktualisieren?"; then
                perform_self_update
            else
                if [[ "$mode" == "manual" ]]; then
                    gum style --foreground 212 "Update abgebrochen."
                fi
            fi
        fi
    fi

    # Im manuellen Modus immer auf eine Eingabe warten
    if [[ "$mode" == "manual" ]]; then
        gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 2
    fi
}

# Funktion zum Testen der Download-Geschwindigkeit
test_download_speed() {
    gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Download-Geschwindigkeitstest"

    # URL für eine 10MB Testdatei
    local test_file_url="http://cachefly.cachefly.net/10mb.test"
    local test_file_size_mb=10

    echo "Starte den Download einer ${test_file_size_mb}MB großen Testdatei von cachefly.net..."

    # Führe den Download durch und erfasse die Ausgabe von wget (die an stderr gesendet wird)
    local wget_output
    wget_output=$(gum spin --spinner dot --title "Teste Geschwindigkeit..." -- \
        wget -O /dev/null "$test_file_url" 2>&1)

    # Prüfe, ob wget erfolgreich war
    if [[ $? -ne 0 ]]; then
        gum style --foreground 9 "Fehler beim Herunterladen der Testdatei. Bitte prüfen Sie Ihre Internetverbindung."
    else
        # Extrahiere die Geschwindigkeitsangabe aus der letzten Zeile der wget-Ausgabe
        local speed
        speed=$(echo "$wget_output" | grep -o -E '\([0-9.,]+.?B/s\)' | sed 's/[()]//g')

        gum style --bold --padding "1" "Test abgeschlossen!" "Ihre durchschnittliche Download-Geschwindigkeit beträgt: $(gum style --foreground 10 --bold "$speed")"
    fi

    gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 4
}

# Funktion zum Festlegen der bevorzugten Suchregionen
set_search_regions() {
    local no_save="$1"
    gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Bevorzugte Suchregionen festlegen"
    local new_regions
    new_regions=$(gum input --header "Regionen durch Leerzeichen getrennt eingeben (z.B. 'Europe Germany')." --placeholder "Leer lassen, um Filter zu deaktivieren." --value "$SEARCH_REGIONS")

    # Trim leading/trailing whitespace
    new_regions=$(echo "$new_regions" | sed 's/^[ \t]*//;s/[ \t]*$//')

    SEARCH_REGIONS="$new_regions"
    gum style --foreground 10 "Bevorzugte Suchregionen auf '${SEARCH_REGIONS:-Keine}' gesetzt."
    save_config "suppress_message"
    gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 2
}

# Funktion zum Festlegen der auszuschließenden Suchbegriffe
set_exclude_keywords() {
    local no_save="$1"
    gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Auszuschließende Suchbegriffe festlegen"

    local new_keywords
    new_keywords=$(gum input --header "Begriffe durch Leerzeichen getrennt eingeben (z.B. 'Demo Beta')." --placeholder "Leer lassen, um Filter zu deaktivieren." --value "$SEARCH_EXCLUDE_KEYWORDS")

    # Trim leading/trailing whitespace
    new_keywords=$(echo "$new_keywords" | sed 's/^[ \t]*//;s/[ \t]*$//')

    SEARCH_EXCLUDE_KEYWORDS="$new_keywords"
    gum style --foreground 10 "Auszuschließende Suchbegriffe auf '${SEARCH_EXCLUDE_KEYWORDS:-Keine}' gesetzt."
    if [[ "$no_save" != "no_save" ]]; then
        save_config "suppress_message"    
    fi
    gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 2
}

# Funktion zum Umschalten des automatischen Löschens von Archiven
toggle_delete_archive_after_extract() {
    local no_save="$1"
    gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Archiv nach Entpacken löschen umschalten"
    if [[ "$DELETE_ARCHIVE_AFTER_EXTRACT" == "yes" ]]; then
        DELETE_ARCHIVE_AFTER_EXTRACT="no"
        gum style --foreground 9 "Automatisches Löschen von Archiven nach dem Entpacken ist jetzt DEAKTIVIERT."
    else
        DELETE_ARCHIVE_AFTER_EXTRACT="yes"
        gum style --foreground 10 "Automatisches Löschen von Archiven nach dem Entpacken ist jetzt AKTIVIERT."
    fi
    gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 1
    if [[ "$no_save" != "no_save" ]]; then
        save_config "suppress_message"
    fi
}

# Funktion zum Lesen der lokalen Versionsdatei
get_local_version() {
    local local_version_file
    local_version_file="$SCRIPT_DIR/VERSION"

    if [ -f "$local_version_file" ]; then
        # Extrahiere den Wert direkt aus der Datei, um Scope-Probleme zu vermeiden
        grep '^VERSION=' "$local_version_file" | cut -d'=' -f2
    fi
}
# Funktion zum Anzeigen des manuellen Hauptmenüs
show_main_menu() {
    # Der Titel wird nach stderr ausgegeben, damit er nicht in der 'choice'-Variable landet
    # gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Hauptmenü" >&2

    # Die Ausgabe von 'gum choose' wird direkt zurückgegeben.
    # Die Trennlinien werden durch nicht-anklickbare, gestylte Elemente ersetzt.
    # WICHTIG: Alle Optionen müssen VOR den Flags (--height etc.) stehen.
    gum choose \
        "Spiele-Download starten" \
        "Merkliste verwalten" \
        " " \
        "Download-Einstellungen" \
        "──────────────────────" \
        "Download-Verzeichnis festlegen" \
        "Anzahl gleichzeitiger Downloads" \
        "Download-Geschwindigkeit" \
        "Download-Warteschlange anzeigen" \
        "Richtlinie für erneute Downloads" \
        " " \
        "Such- & Filtereinstellungen" \
        "───────────────────────────" \
        "Bevorzugte Suchregionen" \
        "Auszuschließende Suchbegriffe" \
        " " \
        "Automatisierungs-Einstellungen" \
        "──────────────────────────────" \
        "Automatische Verifizierung umschalten" \
        "Automatisches Entpacken umschalten" \
        "Archiv nach Entpacken löschen" \
        "Automatische Update-Prüfung" \
        " " \
        "Konfigurations-Management" \
        "─────────────────────────" \
        "Konfigurationsdatei bearbeiten" \
        "Konfiguration sichern" \
        "Konfiguration wiederherstellen" \
        "Veraltete Backups löschen" \
        "Konfiguration zurücksetzen" \
        " " \
        "Download-Management & Verlauf" \
        "───────────────────────────────" \
        "Laufende Downloads anzeigen" \
        "Gesamtgröße der Downloads" \
        "Download-Verlauf anzeigen" \
        "Doppelte Einträge im Verlauf entfernen" \
        "Download-Verlauf als CSV exportieren" \
        "Abgeschlossene Download-Logs entfernen" \
        "Alle Downloads abbrechen" \
        " " \
        "Sonstiges" \
        "─────────" \
        "Nach Updates suchen" \
        "Download-Geschwindigkeit testen" \
        "Haftungsausschluss widerrufen" \
        "Über das Skript" \
        "Beenden" \
        --cursor-prefix "  " --header "" --height 50
}

# Hauptfunktion des Skripts
main() {
    check_dependencies wget curl md5sum sha1sum bc unzip 7z gum fzf
    
    # Rufe die IP-Informationen einmalig beim Start ab
    fetch_ip_info

    # Lese die Version aus der lokalen .version-Datei und setze die globale Variable
    VERSION=$(get_local_version)

    # Prüfe, ob eine Konfigurationsdatei existiert.
    if [ ! -f "$CONFIG_FILE" ]; then
        # Wenn keine Konfigurationsdatei existiert, zeige zuerst den Haftungsausschluss.
        show_disclaimer_and_get_agreement
        # Starte dann die Ersteinrichtung, die die Konfigurationsdatei erstellt.
        initial_setup
        # Starte das Skript neu, um die neue Konfiguration zu laden
        echo -e "${C_GREEN}Konfiguration erstellt. Starte das Skript neu...${C_RESET}"
        exec "$0" "$@"
    else
        # Wenn die Konfigurationsdatei existiert, lade sie und prüfe die Zustimmung zum Haftungsausschluss.
        load_config
        show_disclaimer_and_get_agreement
    fi

    if [[ -f "$CONFIG_FILE" && "$AUTO_UPDATE_CHECK" == "yes" ]]; then
        check_for_updates "auto"
    fi

    while true; do
        show_header
        # show_main_menu gibt jetzt nur noch die Auswahl an stdout aus.
        # Der Titel wird innerhalb der Funktion nach stderr umgeleitet.
        choice=$(show_main_menu)

        case $choice in
            "Spiele-Download starten") select_console_and_download ;;
            "Merkliste verwalten") manage_watchlist ;;
            "Download-Verzeichnis festlegen") set_download_directory ;;
            "Anzahl gleichzeitiger Downloads") set_max_downloads ;;
            "Download-Geschwindigkeit") set_download_speed_limit ;;
            "Richtlinie für erneute Downloads") set_re_download_policy ;;
            "Bevorzugte Suchregionen") set_search_regions; save_config "suppress_message" ;;
            "Auszuschließende Suchbegriffe") set_exclude_keywords; save_config "suppress_message" ;;
            "Automatische Verifizierung umschalten") toggle_auto_verify; save_config "suppress_message" ;;
            "Automatisches Entpacken umschalten") toggle_auto_extract; save_config "suppress_message" ;;
            "Archiv nach Entpacken löschen") toggle_delete_archive_after_extract; save_config "suppress_message" ;;
            "Automatische Update-Prüfung") toggle_auto_update_check; save_config "suppress_message" ;;
            "Konfigurationsdatei bearbeiten") edit_config_file ;;
            "Konfiguration sichern") backup_config ;;
            "Konfiguration wiederherstellen") restore_config ;;
            "Veraltete Backups löschen") cleanup_backups ;;
            "Konfiguration zurücksetzen") reset_config ;;
            "Laufende Downloads anzeigen") show_background_downloads ;;
            "Download-Warteschlange anzeigen") show_queue_status ;;
            "Gesamtgröße der Downloads") show_total_download_size ;;
            "Download-Verlauf anzeigen") show_download_history ;;
            "Doppelte Einträge im Verlauf entfernen") deduplicate_download_history ;;
            "Download-Verlauf als CSV exportieren") export_download_history_to_csv ;;
            "Abgeschlossene Download-Logs entfernen") cleanup_stale_logs ;;
            "Alle Downloads abbrechen") cancel_background_downloads ;;
            "Nach Updates suchen") check_for_updates ;;
            "Haftungsausschluss widerrufen") revoke_disclaimer_agreement ;;
            "Download-Geschwindigkeit testen") test_download_speed ;;
            "Über das Skript") show_about ;;
            "Beenden") echo "Skript wird beendet."; exit 0 ;;
            *) continue ;; # Handle empty selection or invalid choice
        esac
    done
}

# Funktion zum Hinzufügen von Spielen zur Merkliste
add_to_watchlist() {
    local console_name="$1"
    shift # Entfernt das erste Argument (console_name), der Rest sind die Spiele
    local games_to_add=("$@")
    local added_count=0
    local skipped_count=0

    if [ ${#games_to_add[@]} -eq 0 ]; then
        return
    fi

    mkdir -p "$(dirname "$WATCHLIST_FILE")"
    touch "$WATCHLIST_FILE"

    for game_entry in "${games_to_add[@]}"; do
        # Format: path|name|size
        # Wir fügen den Konsolennamen hinzu: path|name|size|console_name
        local name
        name=$(echo "$game_entry" | cut -d'|' -f2)
        
        # Prüfen, ob das Spiel (anhand des Namens) bereits auf der Liste steht
        if grep -q -F -- "|$name|" "$WATCHLIST_FILE"; then
            ((skipped_count+=1))
        else
            echo "${game_entry}|${console_name}" >> "$WATCHLIST_FILE"
            ((added_count+=1))
        fi
    done

    if [ "$added_count" -gt 0 ]; then
        gum style --foreground 10 "$added_count Spiel(e) zur Merkliste hinzugefügt."
    fi
    if [ "$skipped_count" -gt 0 ]; then
        gum style --foreground 212 "$skipped_count Spiel(e) war(en) bereits auf der Merkliste."
    fi
    sleep 2
}

# Funktion zum Verwalten der Merkliste
manage_watchlist() {
    while true; do
        if [ ! -s "$WATCHLIST_FILE" ]; then
            gum style --border normal --margin 1 --padding 1 "Deine Merkliste ist leer."
            gum spin --title "Kehre zum Hauptmenü zurück..." -- sleep 2
            return
        fi

        mapfile -t watchlist_items < <(sort "$WATCHLIST_FILE")

        local display_items=()
        for item in "${watchlist_items[@]}"; do
            local name size console
            name=$(echo "$item" | cut -d'|' -f2)
            size=$(echo "$item" | cut -d'|' -f3)
            console=$(echo "$item" | cut -d'|' -f4)
            display_items+=("$name ($console) - [$size]")
        done

        clear
        gum style --border double --margin "1" --padding "1" --border-foreground 51 "Meine Merkliste"

        local selections
        selections=$(printf '%s\n' "${display_items[@]}" | gum filter --no-limit --placeholder "Spiele auswählen (Leertaste) und mit Enter bestätigen..." || true)

        if [[ -z "$selections" ]]; then return; fi
        
        local selected_full_items=()
        mapfile -t selected_lines < <(echo "$selections")
        for line in "${selected_lines[@]}"; do
            local clean_name
            clean_name=$(echo "$line" | sed -E 's/ \([^)]+\) - \[[^]]+\]$//')
            local original_entry
            original_entry=$(printf '%s\n' "${watchlist_items[@]}" | grep -F -- "|$clean_name|")
            selected_full_items+=("$original_entry")
        done

        local action
        action=$(gum choose "Ausgewählte herunterladen" "Ausgewählte entfernen" "Alles herunterladen" "Merkliste leeren" "Zurück" || true)

        case "$action" in
            "Ausgewählte herunterladen"|"Alles herunterladen")
                local items_to_queue=("${selected_full_items[@]}")
                if [[ "$action" == "Alles herunterladen" ]]; then
                    items_to_queue=("${watchlist_items[@]}")
                fi

                if [ ${#items_to_queue[@]} -gt 0 ]; then
                    printf '%s\n' "${items_to_queue[@]}" >> "$DOWNLOAD_QUEUE_FILE"
                    # Starte den Prozessor nur, wenn er nicht bereits läuft
                    if [ ! -f "$QUEUE_LOCK_FILE" ]; then
                        process_download_queue &
                    fi
                    gum style --foreground 10 "${#items_to_queue[@]} Spiel(e) zur Download-Warteschlange hinzugefügt."
                    # Springe zur Warteschlangen-Ansicht und kehre dann zum Hauptmenü zurück
                    show_queue_status
                    break
                fi
                ;;
            "Ausgewählte entfernen")
                if [ ${#selected_full_items[@]} -gt 0 ]; then
                    local temp_file
                    temp_file=$(mktemp)
                    grep -vFf <(printf '%s\n' "${selected_full_items[@]}") "$WATCHLIST_FILE" > "$temp_file"
                    mv "$temp_file" "$WATCHLIST_FILE"
                    gum style --foreground 10 "${#selected_full_items[@]} Spiel(e) von der Merkliste entfernt."
                    sleep 2
                fi
                ;;
            "Merkliste leeren")
                if gum confirm "Möchten Sie die gesamte Merkliste wirklich leeren?"; then
                    > "$WATCHLIST_FILE"
                    gum style --foreground 10 "Merkliste wurde geleert."
                    sleep 2
                    return
                fi
                ;;
            "Zurück")
                continue
                ;;
            *) # Bei Abbruch (ESC) oder leerer Auswahl
                return
                ;;
        esac
    done
}

# Funktion zum sequenziellen Abarbeiten der Download-Warteschlange im Hintergrund
process_download_queue() {
    # Lock-Mechanismus, um zu verhindern, dass der Prozess mehrfach läuft
    if [ -f "$QUEUE_LOCK_FILE" ]; then
        return
    fi
    touch "$QUEUE_LOCK_FILE"
    trap 'rm -f "$QUEUE_LOCK_FILE"' EXIT

    # Redirect all output/error to a debug log to prevent TUI corruption
    # This block runs in a subshell due to the redirection, which is fine.
    {
        while [ -s "$DOWNLOAD_QUEUE_FILE" ]; do
            # Lade Konfiguration neu, um auf Änderungen während des Laufs zu reagieren
            load_config
            
            # Prüfen auf Pause-Status
            if [ -f "$QUEUE_PAUSE_FILE" ]; then
                sleep 2
                continue
            fi

            local game_entry
            game_entry=$(head -n 1 "$DOWNLOAD_QUEUE_FILE")
            
            local path name size console_name
            path=$(echo "$game_entry" | cut -d'|' -f1)
            name=$(echo "$game_entry" | cut -d'|' -f2)
            size=$(echo "$game_entry" | cut -d'|' -f3)
            console_name=$(echo "$game_entry" | cut -d'|' -f4)

            local log_file="$PROJECT_ROOT/logs/$(basename "$name").log"
            
            # wget im Vordergrund (innerhalb dieses Hintergrund-Skripts) ausführen
            if wget -P "$DOWNLOAD_DIR" -c --limit-rate="$DOWNLOAD_SPEED_LIMIT" -o "$log_file" --progress=bar:force:noscroll "${BASE_URL}${path}"; then
                
                # Update status for Dashboard
                echo "STATUS: Verifying..." >> "$log_file"
                verify_file_integrity "$DOWNLOAD_DIR/$name" "silent" >> "$log_file" 2>&1
                
                if [[ "$AUTO_EXTRACT" == "yes" ]]; then
                    extract_archive "$DOWNLOAD_DIR/$name" "silent" >> "$log_file" 2>&1
                fi
                
                echo "STATUS: Complete" >> "$log_file"

                # Erfolgreich: Erst JETZT aus Warteschlange entfernen
                local temp_file=$(mktemp)
                tail -n +2 "$DOWNLOAD_QUEUE_FILE" > "$temp_file" && mv "$temp_file" "$DOWNLOAD_QUEUE_FILE"
                
                # Auch aus Merkliste entfernen
                local temp_watchlist=$(mktemp)
                grep -vF -- "$game_entry" "$WATCHLIST_FILE" > "$temp_watchlist" && mv "$temp_watchlist" "$WATCHLIST_FILE"

                # Protokollieren
                mkdir -p "$(dirname "$DOWNLOAD_HISTORY_LOG")"
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] - [$console_name] - $name" >> "$DOWNLOAD_HISTORY_LOG"
                
            else
                # Fehler: Aus Warteschlange entfernen, aber auf Merkliste lassen
                local temp_file=$(mktemp)
                tail -n +2 "$DOWNLOAD_QUEUE_FILE" > "$temp_file" && mv "$temp_file" "$DOWNLOAD_QUEUE_FILE"
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] - FAILED - [$console_name] - $name" >> "$PROJECT_ROOT/logs/failed_downloads.log"
            fi
        done
    } > "$PROJECT_ROOT/logs/queue_processor_debug.log" 2>&1
}

# Funktion zum Anzeigen des Warteschlangen-Status (Dashboard)
show_queue_status() {
    # Verstecke Cursor
    tput civis
    trap 'tput cnorm' EXIT
    clear # Einmaliges Leeren des Bildschirms vor der Schleife

    while true; do
        tput cup 0 0 # Cursor oben links positionieren (verhindert Flackern durch 'clear')
        gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Download-Dashboard" "Drücken Sie eine beliebige Taste, um zurückzukehren."

        if [ ! -s "$DOWNLOAD_QUEUE_FILE" ]; then
            gum style --padding "1" "Die Warteschlange ist leer (oder Aufgaben abgeschlossen)."
            if [ -f "$QUEUE_LOCK_FILE" ]; then
                 gum style --foreground 10 "Hintergrund-Prozess ist noch aktiv (schließt Abschlussarbeiten ab)..."
            else
                 gum style --foreground 212 "Keine aktiven Downloads."
            fi
        else
            # Starte den Prozessor nur, wenn er nicht bereits läuft
            if [ ! -f "$QUEUE_LOCK_FILE" ]; then
                 process_download_queue &
                 # Kurze Pause, damit der Prozess Zeit hat, das Lock-File zu erstellen
                 # und den Status im Log zu aktualisieren
                 sleep 1
            fi

            local current_download
            current_download=$(head -n 1 "$DOWNLOAD_QUEUE_FILE")
            local name size
            name=$(echo "$current_download" | cut -d'|' -f2)
            size=$(echo "$current_download" | cut -d'|' -f3)

            gum style "Aktive Aufgabe: $(gum style --bold "$name ($size)")"

            local log_file="$PROJECT_ROOT/logs/$(basename "$name").log"
            if [ -f "$log_file" ]; then
                local last_line
                last_line=$(tail -n 1 "$log_file" 2>/dev/null | tr -d '\0\r')
                
                local progress speed eta state_text

                if [[ "$last_line" == STATUS:* ]]; then
                    state_text="${last_line#STATUS: }"
                    progress=100
                    speed="-"
                    eta="-"
                    
                    # Wenn wir Fortschritt in der Statuszeile haben (von 7z -bsp1)
                    if [[ "$state_text" =~ ([0-9]+)% ]]; then
                        progress="${BASH_REMATCH[1]}"
                    fi

                    gum style --foreground 10 "Status: $state_text"
                elif [[ "$last_line" =~ ([0-9]+)% ]]; then
                    # Universeller Parser für Fortschritt in der letzten Zeile (7z -bsp1 gibt Zeilen wie " 10%" aus)
                    progress="${BASH_REMATCH[1]}"
                    speed="-"
                    eta="-"
                    state_text="Wird entpackt..."
                    
                    # Suche nach der letzten "STATUS:" Zeile vor dem Fortschritt, um den Kontext zu kennen
                    local context
                    context=$(grep -a "STATUS:" "$log_file" | tail -n 1 | tr -d '\0' || true)
                    if [[ -n "$context" ]]; then
                        state_text="${context#STATUS: }"
                    fi
                    
                    gum style "Status: $state_text"
                else
                    progress=$(echo "$last_line" | sed -n 's/.* \([0-9]\+%\).*/\1/p' | sed 's/%//g')
                    progress=${progress:-0}
                    speed=$(echo "$last_line" | sed -n 's/.* \([0-9.,]*[KMGT]B\/s\).*/\1/p')
                    speed=${speed:-"N/A"}
                    eta=$(echo "$last_line" | sed -n 's/.*eta \([0-9ms h]*\).*/\1/p')
                    eta=${eta:-"N/A"}
                    state_text="Wird heruntergeladen..."
                    
                    gum style "Status: $state_text"
                fi

                # Manuelle Progress Bar Berechnung
                local bar_width=40
                local filled_len=$(echo "($progress * $bar_width) / 100" | bc)
                local empty_len=$((bar_width - filled_len))
                local bar=""
                if [ "$filled_len" -gt 0 ]; then
                    bar=$(printf "%0.s█" $(seq 1 $filled_len))
                fi
                if [ "$empty_len" -gt 0 ]; then
                    bar="${bar}$(printf "%0.s░" $(seq 1 $empty_len))"
                fi
                
                local bar_color=212
                if [[ "$progress" -eq 100 ]]; then bar_color=10; fi
                
                gum join --horizontal "$(gum style --foreground "$bar_color" "[$bar]")" "  $progress%"
                if [[ "$state_text" == "Wird heruntergeladen..." ]]; then
                    gum style "Geschwindigkeit: $speed | Verbleibend: $eta"
                fi
            else
                gum style "Warte auf Start..."
            fi

            local queue_count
            queue_count=$(wc -l < "$DOWNLOAD_QUEUE_FILE")
            if [ "$queue_count" -gt 1 ]; then
                local remaining_count=$((queue_count - 1))
                echo -e "\n$(gum style --bold "$remaining_count") weitere(s) Spiel(e) in der Warteschlange:"
                tail -n +2 "$DOWNLOAD_QUEUE_FILE" | awk -F'|' '{print "  - " $2 " (" $4 ")"}'
            fi
        fi
        
        # Zeige Steuerungsoptionen an
        local status_msg=""
        if [ -f "$QUEUE_PAUSE_FILE" ]; then
            status_msg="$(gum style --foreground 3 "PAUSIERT") - "
        fi
        gum style --align center "${status_msg}$(gum style --foreground 212 "[p] Pause/Weiter  [c] Abbrechen  [q] Zurück")"

        tput ed # Lösche den Rest des Bildschirms

        # Check user input
        if read -t 1 -n 1 key; then
            case "$key" in
                p|P)
                    if [ -f "$QUEUE_PAUSE_FILE" ]; then
                        rm "$QUEUE_PAUSE_FILE"
                    else
                        touch "$QUEUE_PAUSE_FILE"
                    fi
                    ;;
                c|C)
                    # Cursor wiederherstellen für gum confirm
                    tput cnorm 
                    tput cup $(tput lines) 0
                    if gum confirm "Warteschlange wirklich abbrechen?" --affirmative="Ja" --negative="Nein"; then
                        # Warteschlange leeren
                        > "$DOWNLOAD_QUEUE_FILE"
                        
                        # Laufenden Download (wget) killen, falls vorhanden
                        # Suche nach dem wget Prozess, der in das Log schreibt
                         local pids
                         pids=$(pgrep -f "wget -P $DOWNLOAD_DIR.*${BASE_URL}")
                         if [ -n "$pids" ]; then
                            kill $pids 2>/dev/null
                         fi
                         
                        # Pause-Datei entfernen, falls vorhanden, damit der Prozess sauber aufräumen kann
                        rm -f "$QUEUE_PAUSE_FILE"
                        
                        gum style --foreground 10 "Warteschlange wurde abgebrochen."
                        sleep 1
                        break
                    fi
                    # Cursor wieder verstecken
                    tput civis
                    ;;
                q|Q|e|E) # e/E for potential typos or if someone thinks 'exit'
                     break 
                     ;;
            esac
        fi
    done
    tput cnorm # Cursor wieder anzeigen
}

select_console_and_download() {
    local consoles_list
    consoles_list=$(gum spin --spinner dot --title "Lade Konsolenliste..." -- bash -c 'get_links "/files/Redump/" | grep "^[^|]*/|" | sort')
    # grep '^\S\+/\s' filtert nach Zeilen, bei denen das erste Wort (der Pfad) mit einem / endet,
    # was auf ein Verzeichnis hinweist. Korrigiert, um auf das erste Feld zu prüfen, das mit / endet.
    mapfile -t consoles < <(get_links "/files/Redump/" | grep '^[^|]*/|' | sort)

    if [ ${#consoles[@]} -eq 0 ]; then
        echo "Keine Konsolen im Verzeichnis /files/Redump/ gefunden."
        return 1
    fi

    # Extrahiere nur die Anzeigenamen für gum filter
    local display_names
    display_names=$(printf '%s\n' "${consoles[@]}" | cut -d'|' -f2)

    local console_display_name
    console_display_name=$(printf '%s\n' "$display_names" | gum filter --placeholder "Konsole auswählen..." --no-limit)

    if [[ -z "$console_display_name" ]]; then
        return # User pressed escape
    fi

    # Finde den vollständigen Eintrag für den ausgewählten Namen
    local selected_console_entry
    selected_console_entry=$(printf '%s\n' "${consoles[@]}" | grep -F -- "|${console_display_name}|")
    local console_path
    console_path=$(echo "$selected_console_entry" | cut -d'|' -f1)
    search_and_download_games "$console_path"
}

search_and_download_games() {
    local console_path="$1"
    if [[ -z "$console_path" ]]; then return; fi
    
    # Extrahiere den sauberen Konsolennamen für das Protokoll
    local console_name=$(url_decode "$console_path" | sed -e 's|^/files/Redump/||' -e 's|/$||')
    
    local all_games_raw
    # gum spin wrapper removed to prevent potential pipe/output buffer issues
    echo -e "${C_CYAN}Lade Spieleliste für $(url_decode "$console_path")...${C_RESET}"
    # Call function directly - no need for subshell or export issues
    all_games_raw=$(get_links "$console_path" | grep -v '^[^|]*/|' | sort -u)
    mapfile -t all_games < <(echo "$all_games_raw")
    
    # DEBUG: Log content
    echo "DEBUG: Found ${#all_games[@]} games. First item: '${all_games[0]}'" >> "$PROJECT_ROOT/debug_log.txt"
    
    # DEBUG: Log the number of games found
    echo "DEBUG: Found ${#all_games[@]} games for console $console_name" >> "$PROJECT_ROOT/debug_log.txt"



        if [ ${#all_games[@]} -eq 0 ]; then
            echo "Keine Spiele in diesem Verzeichnis gefunden."
            # Anstatt zu beenden, zurück zur Konsolenauswahl
            read -n 1 -s -r -p "Drücken Sie eine beliebige Taste, um fortzufahren..."
            return
        fi

        while true; do
            clear
            gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Spiele für $(url_decode "$console_path") durchsuchen"
            game_keyword=$(gum input --placeholder "Suchbegriff eingeben (oder leer lassen, um zurückzukehren)...")

            # 'q' is no longer needed, empty input returns
            if [[ -z "$game_keyword" ]]; then
                return
            fi

            if [ ${#game_keyword} -eq 2 ]; then
                echo -e "${C_CYAN}Suche nach Sprachcode '${C_WHITE}$game_keyword${C_CYAN}'...${C_RESET}"
                # Regex: sucht nach (de, oder (de) oder  de, oder  de) ohne Berücksichtigung der Groß-/Kleinschreibung
                mapfile -t game_results < <(printf '%s\n' "${all_games[@]}" | grep -iE -- "[ (]${game_keyword}[,)]")
            elif [ ${#game_keyword} -eq 1 ]; then
                echo -e "${C_CYAN}Suche nach Spielen, die mit '${C_WHITE}$game_keyword${C_CYAN}' beginnen...${C_RESET}"
                # Verwende awk für robustes Filtern. index(...) == 1 bedeutet "beginnt mit".
                # Wir müssen sicherstellen, dass wir das zweite Feld (Titel) prüfen.
                mapfile -t game_results < <(printf '%s\n' "${all_games[@]}" | awk -F '|' -v kw="$game_keyword" 'BEGIN{kw=tolower(kw)} index(tolower($2), kw) == 1')
            else
                echo -e "${C_CYAN}Suche nach Spielen, die '${C_WHITE}$game_keyword${C_CYAN}' enthalten...${C_RESET}"
                mapfile -t game_results < <(printf '%s\n' "${all_games[@]}" | awk -F '|' -v kw="$game_keyword" 'BEGIN{kw=tolower(kw)} index(tolower($2), kw) > 0')
            fi

            # Wende den optionalen Regionsfilter an, wenn er gesetzt ist
            if [[ -n "$SEARCH_REGIONS" ]]; then
                echo -e "${C_CYAN}Filtere Ergebnisse nach Region(en): '${C_WHITE}$SEARCH_REGIONS${C_CYAN}'...${C_RESET}"
                # Erstelle ein Regex-Muster wie (Region1|Region2|...)
                local region_pattern=$(echo "$SEARCH_REGIONS" | sed 's/ /|/g')
                # Filtere die bisherigen Ergebnisse
                mapfile -t game_results < <(printf '%s\n' "${game_results[@]}" | grep -iE "$region_pattern")
            fi

            # Wende den optionalen Ausschlussfilter an, wenn er gesetzt ist
            if [[ -n "$SEARCH_EXCLUDE_KEYWORDS" ]]; then
                echo -e "${C_CYAN}Filtere Ergebnisse, um auszuschließen: '${C_WHITE}$SEARCH_EXCLUDE_KEYWORDS${C_CYAN}'...${C_RESET}"
                # Erstelle ein Regex-Muster wie (Wort1|Wort2|...)
                local exclude_pattern=$(echo "$SEARCH_EXCLUDE_KEYWORDS" | sed 's/ /|/g')
                # Filtere die bisherigen Ergebnisse mit grep -v (invert match)
                mapfile -t game_results < <(printf '%s\n' "${game_results[@]}" | grep -viE "$exclude_pattern")
            fi


            if [ ${#game_results[@]} -eq 0 ]; then
                echo -e "${C_YELLOW}Keine Spiele mit diesem Namen gefunden.${C_RESET}"
                continue
            fi

            local display_results=()
            for item in "${game_results[@]}"; do
                local display_name size marker on_watchlist is_downloaded color
                display_name=$(echo "$item" | cut -d'|' -f2)
                size=$(echo "$item" | cut -d'|' -f3)
                color="$C_RESET" # Standardfarbe

                on_watchlist=false
                [ -f "$WATCHLIST_FILE" ] && grep -q -F -- "|$display_name|" "$WATCHLIST_FILE" && on_watchlist=true

                is_downloaded=false
                [ -f "$DOWNLOAD_HISTORY_LOG" ] && grep -q -F -- "$display_name" "$DOWNLOAD_HISTORY_LOG" && is_downloaded=true

                if $is_downloaded; then
                    marker="✔"; color="$C_GREEN" # Bereits heruntergeladen -> Grün
                elif $on_watchlist; then
                    marker="★"; color="$C_YELLOW" # Auf der Merkliste -> Orange/Gelb
                else
                    marker=" " # Weder noch
                fi

                display_results+=("${color}$marker $display_name ${C_GRAY}($size)${C_RESET}")
            done

            local selections
            selections=$(printf '%s\n' "${display_results[@]}" | fzf --multi --ansi --prompt="Spiele auswählen (Tab) und mit Enter bestätigen > " || true)

            if [[ -n "$selections" ]]; then
                local selected_full_items=()
                mapfile -t selected_lines < <(echo "$selections")
                for line in "${selected_lines[@]}"; do
                    # Extrahiere den reinen Dateinamen, um den ursprünglichen Eintrag zu finden
                    # sed 1: Entfernt ANSI-Farbcodes.
                    # sed 2: Entfernt das Präfix (z.B. "[✔] ").
                    # sed 3: Entfernt das Suffix (z.B. " (123 MiB)").
                    local clean_name 
                    clean_name=$(echo "$line" | sed -e "s/$(printf '\033')\\[[0-9;]*[mK]//g" -e 's/^. //' -e 's/ ([^)]*)$//')
                    # Finde den passenden Eintrag in den ursprünglichen Ergebnissen
                    local original_entry=""
                    original_entry=$(printf '%s\n' "${game_results[@]}" | grep -F -- "|$clean_name|" || true)
                    if [[ -n "$original_entry" ]]; then
                        selected_full_items+=("$original_entry")
                    fi
                done

                if [ ${#selected_full_items[@]} -gt 0 ]; then
                    local action
                    action=$(gum choose "Herunterladen" "Zur Merkliste hinzufügen" "Abbrechen" || true)

                    case "$action" in
                        "Herunterladen")
                            if gum confirm "Downloads im Hintergrund ausführen?"; then
                                echo "Starte Downloads im Hintergrund (Maximal $MAX_CONCURRENT_DOWNLOADS gleichzeitig)..."
                                local count=0
                                for game_choice in "${selected_full_items[@]}"; do
                                    # Warte, wenn die maximale Anzahl an Prozessen erreicht ist
                                    if [[ $count -ge $MAX_CONCURRENT_DOWNLOADS ]]; then
                                        echo -e "${C_CYAN}Warte auf einen freien Download-Slot...${C_RESET}"
                                        wait -n
                                        ((count-=1))
                                    fi
                                    local path name
                                    path=$(echo "$game_choice" | cut -d'|' -f1)
                                    name=$(echo "$game_choice" | cut -d'|' -f2)
                                    # Eindeutige Log-Datei für jeden Download
                                    mkdir -p "$PROJECT_ROOT/logs"
                                    log_file="$PROJECT_ROOT/logs/$(basename "$name").log"

                                    echo -e "${C_CYAN}Starte Hintergrund-Download für: ${C_WHITE}$name${C_RESET}" 
                                    wget -b -c -P "$DOWNLOAD_DIR" --limit-rate="$DOWNLOAD_SPEED_LIMIT" --progress=bar:force:noscroll -o "$log_file" -- "${BASE_URL}${path}" &
                                    ((count+=1))
                                done
                                echo "Alle Downloads wurden in die Warteschlange gestellt. Warten bis alle fertig sind..."
                                wait # Warte auf alle Hintergrundprozesse in dieser Schleife
                                # Protokolliere die abgeschlossenen Downloads
                                gum spin --title "Protokolliere abgeschlossene Hintergrund-Downloads..." -- sleep 1
                                for game_choice in "${selected_full_items[@]}"; do
                                    local name=$(echo "$game_choice" | cut -d'|' -f2)
                                    mkdir -p "$(dirname "$DOWNLOAD_HISTORY_LOG")"
                                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] - [$console_name] - $name" >> "$DOWNLOAD_HISTORY_LOG"
                                done
                                if [[ "$AUTO_EXTRACT" == "yes" ]]; then
                                    for game_choice in "${selected_full_items[@]}"; do
                                        extract_archive "$DOWNLOAD_DIR/$(basename "$(echo "$game_choice" | cut -d'|' -f2)")"
                                    done
                                fi
                                echo -e "${C_GREEN}Alle Hintergrund-Downloads dieser Sitzung sind abgeschlossen.${C_RESET}"
                            else
                                echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
                                for game_choice in "${selected_full_items[@]}"; do
                                    path=$(echo "$game_choice" | cut -d'|' -f1)
                                    name=$(echo "$game_choice" | cut -d'|' -f2)
                                    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
                                    gum style --border normal --padding "0 1" --border-foreground 212 "Starte Download für: $(gum style --bold "$name")"
                                    if wget -q -P "$DOWNLOAD_DIR" -c --limit-rate="$DOWNLOAD_SPEED_LIMIT" --show-progress "${BASE_URL}${path}"; then
                                        gum style --foreground 10 "Download von '$name' abgeschlossen."
                                        # Protokolliere den erfolgreichen Download
                                        mkdir -p "$(dirname "$DOWNLOAD_HISTORY_LOG")"
                                        echo "[$(date '+%Y-%m-%d %H:%M:%S')] - [$console_name] - $name" >> "$DOWNLOAD_HISTORY_LOG"
                                        # Lösche die Log-Datei, falls eine durch einen vorherigen fehlgeschlagenen Versuch existiert
                                        rm -f "$PROJECT_ROOT/logs/$(basename "$name").log" 2>/dev/null
                                        
                                        verify_file_integrity "$DOWNLOAD_DIR/$name"
                                        
                                        if [[ "$AUTO_EXTRACT" == "yes" ]]; then
                                            extract_archive "$DOWNLOAD_DIR/$name"
                                        fi
                                    fi # End of if wget successful
                                done
                            fi
                            ;;
                        "Zur Merkliste hinzufügen")
                            add_to_watchlist "$console_name" "${selected_full_items[@]}"
                            ;;
                        "Abbrechen")
                            continue
                            ;;
                    esac
                fi
            fi
        done # Ende der Spielesuche-Schleife
}

# Starte die Hauptfunktion
# Stellt sicher, dass das Skript auch bei Strg+C sauber beendet wird.
trap "echo; echo 'Skript abgebrochen.'; exit 0" INT TERM
main
