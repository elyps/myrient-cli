#!/bin/bash

# ==============================================================================
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

# --- Farben ---
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_PURPLE='\033[0;35m'
C_CYAN='\033[0;36m'
C_WHITE='\033[1;37m'
C_GRAY='\033[0;90m'
C_BOLD='\033[1m'
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
        -e 's/.*<a href="\([^"]*\)"[^>]*>\([^<]*\)<\/a><\/td><td class="size">\([^<]*\)<\/td>.*/\1|\2|\3/p' | \
        while IFS='|' read -r encoded_path display_name size; do
            # Filtere Navigations-Links heraus
            if [[ "$display_name" != "./" && "$display_name" != "../" && "$display_name" != "Parent directory/" ]]; then
                # Ausgabe: Vollständiger KODIERTER Pfad | Anzeigename (bereits dekodiert) | Größe
                echo "${current_path}${encoded_path}|${display_name}|${size}"
            fi
        done
}

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
    local no_save="$1"
    clear
    echo -e "${HEADLINE_COLOR}Download-Verzeichnis festlegen${C_RESET}"
    read -r -p "$(echo -e "${C_YELLOW}Neues Download-Verzeichnis eingeben (aktuell: ${C_WHITE}$DOWNLOAD_DIR${C_YELLOW}): ${C_RESET}")" new_dir

    # Wenn die Eingabe leer ist, keine Änderung
    if [[ -z "$new_dir" ]]; then
        echo "Keine Änderung vorgenommen."
        return
    fi

    # Tilde-Expansion manuell durchführen (z.B. ~/Downloads)
    eval new_dir="$new_dir"

    # Prüfen, ob das Verzeichnis existiert
    if [[ ! -d "$new_dir" ]]; then
        read -r -p "$(echo -e "Verzeichnis '${C_WHITE}$new_dir${C_RESET}' existiert nicht. Erstellen? (${C_GREEN}j${C_RESET}/${C_RED}n${C_RESET}) ")" create_choice
        if [[ "$create_choice" == "j" || "$create_choice" == "J" ]]; then
            mkdir -p "$new_dir"
            if [[ $? -eq 0 ]]; then
                echo -e "${C_GREEN}Verzeichnis '$new_dir' wurde erstellt.${C_RESET}"
                DOWNLOAD_DIR="$new_dir"
            else
                echo -e "${C_RED}Fehler beim Erstellen des Verzeichnisses. Keine Änderung vorgenommen.${C_RESET}"
            fi
        else
            echo -e "${C_YELLOW}Keine Änderung vorgenommen.${C_RESET}"
        fi
    else
        DOWNLOAD_DIR="$new_dir"
        echo -e "${C_GREEN}Download-Verzeichnis auf '$DOWNLOAD_DIR' gesetzt.${C_RESET}"
        if [[ "$no_save" != "no_save" ]]; then
            save_config "suppress_message"
        fi
    fi
    echo
    read -n 1 -s -r -p "Drücken Sie eine beliebige Taste, um fortzufahren..."
}

# Funktion zum Anzeigen laufender Hintergrund-Downloads
show_background_downloads() {
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    echo -e "${HEADLINE_COLOR}Suche nach laufenden Hintergrund-Downloads...${C_RESET}"

    # pgrep -f sucht nach Prozessen, deren Kommandozeile dem Muster entspricht.
    # Wir suchen nach den .log Dateien, um den Fortschritt zu parsen
    local log_files
    log_files=$(find "$DOWNLOAD_DIR" -maxdepth 1 -type f -name "*.log")

    if [ -z "$log_files" ]; then
        echo -e "${C_YELLOW}Keine laufenden Hintergrund-Downloads gefunden.${C_RESET}"
    else
        echo -e "${HEADLINE_COLOR}Folgende Hintergrund-Downloads sind aktiv:${C_RESET}"
        echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
        printf "${C_BOLD}%-40s | %-8s | %-12s | %-10s${C_RESET}\n" "DATEI" "FORTSCHRITT" "GESCHWINDIGKEIT" "VERBLEIBEND"
        echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"

        for log_file in $log_files; do
            # Extrahiere den Dateinamen ohne .log
            local filename
            filename=$(basename "$log_file" .log)
            
            # Extrahiere die letzte Fortschrittszeile aus dem Log
            local last_line
            last_line=$(tail -n 1 "$log_file" 2>/dev/null | tr -d '\r')

            # Parse die Zeile, um Fortschritt, Geschwindigkeit und ETA zu erhalten
            local progress eta speed
            progress=$(echo "$last_line" | sed -n 's/.* \([0-9]\+%\).*/\1/p')
            speed=$(echo "$last_line" | sed -n 's/.* \([0-9.,]*[KMGT]B\/s\).*/\1/p')
            eta=$(echo "$last_line" | sed -n 's/.*eta \([0-9ms h]*\).*/\1/p')

            printf "${C_WHITE}%-40.40s${C_RESET} | ${C_GREEN}%-8s${C_RESET} | ${C_CYAN}%-12s${C_RESET} | ${C_YELLOW}%-10s${C_RESET}\n" "$filename" "$progress" "$speed" "$eta"
        done
    fi
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    read -n 1 -s -r -p "Drücken Sie eine beliebige Taste, um zum Hauptmenü zurückzukehren..."
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

# Funktion zum Abbrechen aller laufenden Hintergrund-Downloads
cancel_background_downloads() {
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    echo -e "${HEADLINE_COLOR}Suche nach laufenden Hintergrund-Downloads zum Abbrechen...${C_RESET}"

    local pids
    pids=$(pgrep -f "wget -b -q -c -P .*${BASE_URL}")

    if [ -z "$pids" ]; then
        echo -e "${C_YELLOW}Keine laufenden Hintergrund-Downloads gefunden.${C_RESET}"
    else
        echo -e "${HEADLINE_COLOR}Folgende Hintergrund-Downloads sind aktiv:${C_RESET}"
        ps -o pid,args -p "$pids" | grep "${BASE_URL}"
        echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
        read -r -p "$(echo -e "Möchten Sie wirklich alle diese Downloads abbrechen? (${C_GREEN}j${C_RESET}/${C_RED}n${C_RESET}) ")" confirm
        if [[ "$confirm" == "j" || "$confirm" == "J" ]]; then
            kill $pids 2>/dev/null
            echo -e "${C_GREEN}Alle laufenden Hintergrund-Downloads wurden abgebrochen.${C_RESET}"
        else
            echo -e "${C_YELLOW}Vorgang abgebrochen.${C_RESET}"
        fi
    fi
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    read -n 1 -s -r -p "Drücken Sie eine beliebige Taste, um zum Hauptmenü zurückzukehren..."
}

# Funktion zum Leeren der wget-Log-Datei
clear_download_log() {
    local log_file="$DOWNLOAD_DIR/wget-log"
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    if [ -f "$log_file" ]; then
        read -r -p "$(echo -e "Möchten Sie die Log-Datei '${C_WHITE}$log_file${C_RESET}' wirklich leeren? (${C_GREEN}j${C_RESET}/${C_RED}n${C_RESET}) ")" confirm
        if [[ "$confirm" == "j" || "$confirm" == "J" ]]; then
            rm "$log_file"
            echo -e "${C_GREEN}Log-Datei wurde geleert.${C_RESET}"
        else
            echo -e "${C_YELLOW}Vorgang abgebrochen.${C_RESET}"
        fi
    else
        echo -e "${C_YELLOW}Keine Log-Datei ('$log_file') zum Leeren gefunden.${C_RESET}"
    fi
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    read -n 1 -s -r -p "Drücken Sie eine beliebige Taste, um zum Hauptmenü zurückzukehren..."
}

# Funktion zum Entfernen alter Log-Dateien von abgeschlossenen Downloads
cleanup_stale_logs() {
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    echo -e "${HEADLINE_COLOR}Suche nach abgeschlossenen Download-Logs zum Entfernen...${C_RESET}"
    mkdir -p "$PROJECT_ROOT/logs"
    # Finde alle .log Dateien im Download-Verzeichnis
    local log_files
    log_files=$(find "$DOWNLOAD_DIR" -maxdepth 1 -type f -name "*.log")

    if [ -z "$log_files" ]; then
        echo -e "${C_YELLOW}Keine Log-Dateien zum Entfernen gefunden.${C_RESET}"
    else
        echo "Die folgenden Log-Dateien werden entfernt:"
        printf "  - %s\n" "$log_files" | xargs -d '\n' -I {} basename {}
        read -r -p "$(echo -e "Möchten Sie wirklich fortfahren? (${C_GREEN}j${C_RESET}/${C_RED}n${C_RESET}) ")" confirm
        if [[ "$confirm" == "j" || "$confirm" == "J" ]]; then
            rm -f $log_files && echo -e "${C_GREEN}Alle gefundenen Log-Dateien wurden entfernt.${C_RESET}"
        fi
    fi
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    read -n 1 -s -r -p "Drücken Sie eine beliebige Taste, um zum Hauptmenü zurückzukehren..."
}
# Funktion zur Überprüfung von Abhängigkeiten
check_dependencies() {
    for cmd in "$@"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${C_YELLOW}Warnung: Das benötigte Programm '$cmd' ist nicht installiert.${C_RESET}"
            read -r -p "$(echo -e "Soll versucht werden, es jetzt zu installieren? (${C_GREEN}j${C_RESET}/${C_RED}n${C_RESET}) ")" install_confirm
            if [[ "$install_confirm" == "j" || "$install_confirm" == "J" ]]; then
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
    clear
    echo -e "${HEADLINE_COLOR}Konfiguration zurücksetzen${C_RESET}\n"
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${C_YELLOW}Keine Konfigurationsdatei ($CONFIG_FILE) zum Zurücksetzen gefunden.${C_RESET}"
    else
        read -r -p "$(echo -e "Möchten Sie die Konfiguration wirklich auf die Standardwerte zurücksetzen? (${C_GREEN}j${C_RESET}/${C_RED}n${C_RESET}) ")" confirm
        if [[ "$confirm" == "j" || "$confirm" == "J" ]]; then
            rm -f "$CONFIG_FILE"
            echo "Konfigurationsdatei wurde entfernt."
            # Reset runtime variables to default
            DOWNLOAD_DIR="./downloads"
            AUTO_VERIFY="no"
            MAX_CONCURRENT_DOWNLOADS=3
            DELETE_ARCHIVE_AFTER_EXTRACT="yes"
            AUTO_EXTRACT="no"
            AUTO_UPDATE_CHECK="no"
            SEARCH_REGIONS=""
            DISCLAIMER_ACCEPTED="no"
            SEARCH_EXCLUDE_KEYWORDS="Demo Beta"
            DOWNLOAD_SPEED_LIMIT="0"
            RE_DOWNLOAD_POLICY="ask"
            echo -e "${C_GREEN}Einstellungen auf Standardwerte zurückgesetzt.${C_RESET}"
        else
            echo -e "${C_YELLOW}Vorgang abgebrochen.${C_RESET}"
        fi
    fi
    echo
    read -n 1 -s -r -p "Drücken Sie eine beliebige Taste, um zum Hauptmenü zurückzukehren..."
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
        echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
        echo "Fehler: Kein Editor gefunden. Bitte setzen Sie die EDITOR-Umgebungsvariable."
        echo "z.B. export EDITOR=nano"
        echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
        read -n 1 -s -r -p "Drücken Sie eine beliebige Taste, um zum Hauptmenü zurückzukehren..."
        return
    fi

    echo "Öffne Konfigurationsdatei '$CONFIG_FILE' mit '$editor'..."
    "$editor" "$CONFIG_FILE"

    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    echo -e "${HEADLINE_COLOR}Konfiguration wird neu geladen...${C_RESET}"
    load_config
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    read -n 1 -s -r -p "Drücken Sie eine beliebige Taste, um zum Hauptmenü zurückzukehren..."
}

# Funktion zum Sichern der Konfiguration
backup_config() {
    clear
    echo -e "${HEADLINE_COLOR}Konfiguration sichern${C_RESET}\n"
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
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    read -n 1 -s -r -p "Drücken Sie eine beliebige Taste, um zum Hauptmenü zurückzukehren..."
}

# Funktion zum Anzeigen der Gesamtgröße aller heruntergeladenen Dateien
show_total_download_size() {
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    echo -e "${HEADLINE_COLOR}Berechne die Gesamtgröße des Download-Verzeichnisses...${C_RESET}"

    if [ ! -d "$DOWNLOAD_DIR" ]; then
        echo -e "${C_YELLOW}Download-Verzeichnis '$DOWNLOAD_DIR' nicht gefunden.${C_RESET}"
    else
        # du -sb gibt die Gesamtgröße in Bytes aus
        local total_bytes
        total_bytes=$(du -sb "$DOWNLOAD_DIR" | awk '{print $1}')
        
        if [ -z "$total_bytes" ]; then
            echo -e "${C_RED}Größe konnte nicht berechnet werden.${C_RESET}"
        else
            echo -e "Gesamtgröße aller Dateien in '${C_WHITE}$DOWNLOAD_DIR${C_RESET}': ${C_GREEN}$(format_size_from_bytes "$total_bytes")${C_RESET}"
        fi
    fi
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    read -n 1 -s -r -p "Drücken Sie eine beliebige Taste, um zum Hauptmenü zurückzukehren..."
}

# Funktion zum Wiederherstellen einer Konfiguration
restore_config() {
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    echo -e "${HEADLINE_COLOR}Suche nach Konfigurations-Backups...${C_RESET}"
    # Finde alle .bak Dateien, die zum Config-File gehören
    mapfile -t backup_files < <(find "$PROJECT_ROOT/backups" -maxdepth 1 -type f -name "$(basename "$CONFIG_FILE").*.bak" | sort -r)

    if [ ${#backup_files[@]} -eq 0 ]; then
        echo -e "${C_YELLOW}Keine Backup-Dateien gefunden.${C_RESET}"
    else
        echo "Bitte wählen Sie eine wiederherzustellende Backup-Datei aus:"
        select backup_file in "${backup_files[@]}" "Abbrechen"; do
            if [[ "$backup_file" == "Abbrechen" ]]; then
                echo -e "${C_YELLOW}Vorgang abgebrochen.${C_RESET}"
                break
            elif [[ -n "$backup_file" ]]; then
                read -r -p "$(echo -e "Möchten Sie '${C_WHITE}$CONFIG_FILE${C_RESET}' wirklich mit '${C_WHITE}$(basename "$backup_file")${C_RESET}' überschreiben? (${C_GREEN}j${C_RESET}/${C_RED}n${C_RESET}) ")" confirm
                if [[ "$confirm" == "j" || "$confirm" == "J" ]]; then
                    cp "$backup_file" "$CONFIG_FILE"
                    echo -e "${C_GREEN}Konfiguration wurde wiederhergestellt. Lade Einstellungen neu...${C_RESET}"
                    load_config
                else
                    echo -e "${C_YELLOW}Wiederherstellung abgebrochen.${C_RESET}"
                fi
                break
            else
                echo "Ungültige Auswahl."
            fi
        done
    fi
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    read -n 1 -s -r -p "Drücken Sie eine beliebige Taste, um zum Hauptmenü zurückzukehren..."
}

# Funktion zum Festlegen der maximalen Anzahl gleichzeitiger Downloads
set_max_downloads() {
    local no_save="$1"
    clear
    echo -e "${HEADLINE_COLOR}Maximale Anzahl gleichzeitiger Downloads${C_RESET}\n"
    read -r -p "$(echo -e "${C_YELLOW}Anzahl eingeben (aktuell: ${C_WHITE}$MAX_CONCURRENT_DOWNLOADS${C_YELLOW}): ${C_RESET}")" new_max

    if [[ -z "$new_max" ]]; then
        echo -e "${C_YELLOW}Keine Änderung vorgenommen.${C_RESET}"
    elif ! [[ "$new_max" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${C_RED}Ungültige Eingabe. Bitte geben Sie eine positive Zahl ein.${C_RESET}"
    else
        MAX_CONCURRENT_DOWNLOADS=$new_max
        echo -e "${C_GREEN}Maximale Anzahl gleichzeitiger Downloads auf ${C_WHITE}$MAX_CONCURRENT_DOWNLOADS${C_GREEN} gesetzt.${C_RESET}"
        if [[ "$no_save" != "no_save" ]]; then
            save_config "suppress_message"
        fi
    fi
}

# Funktion zum Umschalten der automatischen Verifizierung
toggle_auto_verify() {
    local no_save="$1"
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    if [[ "$AUTO_VERIFY" == "yes" ]]; then
        AUTO_VERIFY="no"
        echo -e "Automatische Prüfsummen-Verifizierung ist jetzt ${C_RED}DEAKTIVIERT${C_RESET}."
    else
        AUTO_VERIFY="yes"
        echo -e "Automatische Prüfsummen-Verifizierung ist jetzt ${C_GREEN}AKTIVIERT${C_RESET}."
    fi
    if [[ "$no_save" != "no_save" ]]; then
        save_config "suppress_message"
    fi
}

# Funktion zum Löschen veralteter Backups
cleanup_backups() {
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    echo -e "${HEADLINE_COLOR}Suche nach Konfigurations-Backups zum Aufräumen...${C_RESET}"
    mapfile -t backup_files < <(find "$PROJECT_ROOT/backups" -maxdepth 1 -type f -name "$(basename "$CONFIG_FILE").*.bak" | sort -r)

    if [ ${#backup_files[@]} -lt 2 ]; then
        echo -e "${C_YELLOW}Nicht genügend Backups zum Aufräumen gefunden (weniger als 2).${C_RESET}"
    else
        echo "Gefundene Backups: ${#backup_files[@]}"
        read -r -p "$(echo -e "${C_YELLOW}Wie viele der neuesten Backups möchten Sie behalten? ${C_RESET}")" num_to_keep

        if ! [[ "$num_to_keep" =~ ^[0-9]+$ ]]; then
            echo -e "${C_RED}Ungültige Eingabe. Bitte geben Sie eine Zahl ein.${C_RESET}"
        elif [ "${#backup_files[@]}" -le "$num_to_keep" ]; then
            echo -e "${C_YELLOW}Anzahl der Backups (${#backup_files[@]}) ist bereits kleiner oder gleich der zu behaltenden Anzahl ($num_to_keep). Nichts zu tun.${C_RESET}"
        else
            # Die Liste ist von neu nach alt sortiert. Wir löschen alle nach den ersten 'num_to_keep'.
            local files_to_delete=("${backup_files[@]:$num_to_keep}")
            
            echo "Die folgenden ${#files_to_delete[@]} veralteten Backup-Dateien werden gelöscht:"
            printf "  - %s\n" "${files_to_delete[@]}" | xargs -d '\n' -I {} basename {} | sed 's/^/  - /'

            read -r -p "$(echo -e "Möchten Sie wirklich fortfahren? (${C_GREEN}j${C_RESET}/${C_RED}n${C_RESET}) ")" confirm
            if [[ "$confirm" == "j" || "$confirm" == "J" ]]; then
                for file in "${files_to_delete[@]}"; do
                    rm "$file" && echo -e "${C_GREEN}Gelöscht: $(basename "$file")${C_RESET}"
                done
                echo -e "${C_GREEN}Veraltete Backups wurden gelöscht.${C_RESET}"
            else
                echo -e "${C_YELLOW}Vorgang abgebrochen.${C_RESET}"
            fi
        fi
    fi
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    read -n 1 -s -r -p "Drücken Sie eine beliebige Taste, um zum Hauptmenü zurückzukehren..."
}

# Funktion zur Überprüfung der Dateiintegrität mittels Prüfsumme
verify_file_integrity() {
    local local_filepath="$1"
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
            read -r -p "$(echo -e "Prüfsummendatei gefunden. '${C_WHITE}$filename${C_RESET}' verifizieren? (${C_GREEN}j${C_RESET}/${C_RED}n${C_RESET}) ")" verify_choice
            if [[ "$verify_choice" != "j" && "$verify_choice" != "J" ]]; then
                return
            fi
        else
            echo -e "${C_CYAN}Automatische Verifizierung wird für '${C_WHITE}$filename${C_CYAN}' durchgeführt...${C_RESET}"
        fi

        local checksum_remote_path
        checksum_remote_path=$(echo "$checksum_file_entry" | awk '{print $1}')
        local temp_checksum_file
        temp_checksum_file=$(mktemp)

        echo -e "${C_CYAN}Lade Prüfsummendatei herunter...${C_RESET}"        
        wget -q -O "$temp_checksum_file" --limit-rate="$DOWNLOAD_SPEED_LIMIT" -- "${BASE_URL}${checksum_remote_path}"

        echo -e "${C_CYAN}Verifiziere Datei (dies kann dauern)...${C_RESET}"
        # Prüfsumme aus Datei extrahieren (erster Block)
        local expected_checksum
        expected_checksum=$(cut -d' ' -f1 < "$temp_checksum_file")

        # cd in das Verzeichnis, da manche .md5/.sha1-Dateien nur den Dateinamen enthalten
        (cd "$DOWNLOAD_DIR" && "${checksum_type}sum" -c <(echo "$expected_checksum  $filename"))
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

    local title="Myrient-CLI v${VERSION} (unofficial)"
    #local author=""
    local date_str
    date_str=$(date "+%Y")
    
    echo -e "${HEADLINE_COLOR}                          _____            _____             __________v${VERSION}${C_RESET}"
    echo -e "${HEADLINE_COLOR}_______ ________  ___________(_)_____________  /_      _________  /__(_)${C_RESET}"
    echo -e "${HEADLINE_COLOR}__  __ \`__ \\_  / / /_  ___/_  /_  _ \\_  __ \\  __/_______  ___/_  /__  /${C_RESET}"
    echo -e "${HEADLINE_COLOR}_  / / / / /  /_/ /_  /   _  / /  __/  / / / /_ _/_____/ /__ _  / _  /${C_RESET}"
    echo -e "${HEADLINE_COLOR}/_/ /_/ /_/_\__, / /_/    /_/  \\___//_/ /_/\__/        \\___/ /_/  /_/${C_RESET}"
    echo -e "${HEADLINE_COLOR}           /____/${C_RESET}"
    
    printf "\n"
    echo "$title"
    #echo "$author"    
    # Zeige IP-Informationen an, wenn sie verfügbar sind
    if [[ -n "$IP_ADDRESS" ]]; then
        echo -e "Ihre IP: ${C_WHITE}$IP_ADDRESS${C_RESET} (${C_WHITE}$IP_LOCATION${C_RESET})"
    fi

    echo -e "${HEADLINE_COLOR}$(print_horizontal_line)${C_RESET}"
    echo
    echo -e "${HEADLINE_COLOR}Aktuelle Konfiguration:${C_RESET}"
    echo -e "  - Download-Verzeichnis: ${C_WHITE}$DOWNLOAD_DIR${C_RESET}"
    if [[ "$AUTO_VERIFY" == "yes" ]]; then
        echo -e "  - Automatische Verifizierung: ${C_GREEN}Aktiviert${C_RESET}"
    else
        echo -e "  - Automatische Verifizierung: ${C_RED}Deaktiviert${C_RESET}"
    fi
    echo -e "  - Max. gleichzeitige Downloads: ${C_WHITE}$MAX_CONCURRENT_DOWNLOADS${C_RESET}"
    if [[ "$AUTO_EXTRACT" == "yes" ]]; then
        echo -e "  - Automatisches Entpacken: ${C_GREEN}Aktiviert${C_RESET}"
    else
        echo -e "  - Automatisches Entpacken: ${C_RED}Deaktiviert${C_RESET}"
    fi
    if [[ "$DELETE_ARCHIVE_AFTER_EXTRACT" == "yes" ]]; then
        echo -e "  - Archiv nach Entpacken löschen: ${C_GREEN}Aktiviert${C_RESET}"
    else
        echo -e "  - Archiv nach Entpacken löschen: ${C_RED}Deaktiviert${C_RESET}"
    fi
    echo -e "  - Bevorzugte Regionen: ${C_WHITE}${SEARCH_REGIONS:-Keine}${C_RESET}"
    echo -e "  - Ausgeschlossene Schlüsselwörter: ${C_WHITE}${SEARCH_EXCLUDE_KEYWORDS:-Keine}${C_RESET}"
    if [[ "$DOWNLOAD_SPEED_LIMIT" == "0" ]]; then
        echo -e "  - Download-Geschwindigkeit: ${C_GREEN}Unbegrenzt${C_RESET}"
    else
        echo -e "  - Download-Geschwindigkeit: ${C_YELLOW}${DOWNLOAD_SPEED_LIMIT}${C_RESET}"
    fi
    if [[ "$DISCLAIMER_ACCEPTED" == "yes" ]]; then
        local policy_display=""
        case "$RE_DOWNLOAD_POLICY" in
            "ask") policy_display="${C_YELLOW}Nachfragen${C_RESET}" ;;
            "always") policy_display="${C_GREEN}Immer${C_RESET}" ;;
            "skip") policy_display="${C_CYAN}Überspringen${C_RESET}" ;;
            *) policy_display="${C_RED}Unbekannt${C_RESET}" ;;
        esac
        echo -e "  - Erneut herunterladen: $policy_display"
        if [[ "$AUTO_UPDATE_CHECK" == "yes" ]]; then
            echo -e "  - Automatische Update-Prüfung: ${C_GREEN}Aktiviert${C_RESET}"
        else
            echo -e "  - Automatische Update-Prüfung: ${C_RED}Deaktiviert${C_RESET}"
        fi

        echo -e "  - Haftungsausschluss: ${C_GREEN}Akzeptiert${C_RESET}"
    else
        echo -e "  - Haftungsausschluss: ${C_RED}Nicht akzeptiert${C_RESET}"
    fi
    echo ""
}

# Funktion für die Ersteinrichtung
initial_setup() {
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    echo -e "${HEADLINE_COLOR}Willkommen zur Ersteinrichtung von myrient-cli.${C_RESET}"
    echo "Wir werden nun einige Grundeinstellungen vornehmen."
    
    set_download_directory "no_save"
    
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    while true; do
        read -r -p "$(echo -e "Maximale Anzahl gleichzeitiger Downloads festlegen (Standard: ${C_WHITE}3${C_RESET}): ")" max_dl
        max_dl=${max_dl:-3} # Standardwert 3, wenn die Eingabe leer ist
        if [[ "$max_dl" =~ ^[1-9][0-9]*$ ]]; then
            MAX_CONCURRENT_DOWNLOADS=$max_dl
            echo "Maximale Anzahl gleichzeitiger Downloads auf '$MAX_CONCURRENT_DOWNLOADS' gesetzt."
            break
        else
            echo -e "${C_RED}Ungültige Eingabe. Bitte geben Sie eine positive Zahl ein.${C_RESET}"
        fi
    done

    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    read -r -p "$(echo -e "Sollen heruntergeladene Dateien automatisch verifiziert werden? (${C_GREEN}J${C_RESET}/n): ")" choice
    if [[ -z "$choice" || "$choice" == "j" || "$choice" == "J" ]]; then
        AUTO_VERIFY="yes"
        echo "Automatische Verifizierung ist AKTIVIERT."
    else
        AUTO_VERIFY="no"
        echo "Automatische Verifizierung ist DEAKTIVIERT."
    fi

    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    read -r -p "$(echo -e "Soll beim Start automatisch nach Updates gesucht werden? (${C_GREEN}J${C_RESET}/n): ")" update_choice
    if [[ -z "$update_choice" || "$update_choice" == "j" || "$update_choice" == "J" ]]; then
        AUTO_UPDATE_CHECK="yes"
        echo "Automatische Update-Prüfung ist AKTIVIERT."
    else
        AUTO_UPDATE_CHECK="no"
        echo "Automatische Update-Prüfung ist DEAKTIVIERT."
    fi
    
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    read -r -p "$(echo -e "Sollen heruntergeladene Archive (.zip, .7z) automatisch entpackt werden? (${C_GREEN}J${C_RESET}/n): ")" extract_choice
    if [[ -z "$extract_choice" || "$extract_choice" == "j" || "$extract_choice" == "J" ]]; then
        AUTO_EXTRACT="yes"
        echo "Automatisches Entpacken ist AKTIVIERT."
    else
        AUTO_EXTRACT="no"
        echo "Automatisches Entpacken ist DEAKTIVIERT."
    fi

    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    read -r -p "$(echo -e "Sollen Archive nach dem Entpacken automatisch gelöscht werden? (${C_GREEN}J${C_RESET}/n): ")" delete_choice
    if [[ -z "$delete_choice" || "$delete_choice" == "j" || "$delete_choice" == "J" ]]; then
        DELETE_ARCHIVE_AFTER_EXTRACT="yes"
        echo "Automatisches Löschen von Archiven ist AKTIVIERT."
    else
        DELETE_ARCHIVE_AFTER_EXTRACT="no"
        echo "Automatisches Löschen von Archiven ist DEAKTIVIERT."
    fi
    
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    read -r -p "$(echo -e "Bevorzugte Regionen für die Suche eingeben (z.B. 'Europe Germany', Enter für keine): ")" regions
    SEARCH_REGIONS="${regions:-}"
    echo "Bevorzugte Regionen auf '$SEARCH_REGIONS' gesetzt."
    
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    read -r -p "$(echo -e "Schlüsselwörter aus der Suche ausschließen (Standard: '${C_WHITE}Demo Beta${C_RESET}'): ")" exclude_keywords
    SEARCH_EXCLUDE_KEYWORDS="${exclude_keywords:-$SEARCH_EXCLUDE_KEYWORDS}"
    DISCLAIMER_ACCEPTED="yes" # Bei der Ersteinrichtung wird der Disclaimer als akzeptiert gesetzt
    echo "Ausgeschlossene Schlüsselwörter auf '$SEARCH_EXCLUDE_KEYWORDS' gesetzt."
    
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    read -r -p "$(echo -e "Download-Geschwindigkeitsbegrenzung festlegen (z.B. 500k, 2m, Enter für unbegrenzt): ")" speed_limit
    DOWNLOAD_SPEED_LIMIT="${speed_limit:-0}"
    if [[ "$DOWNLOAD_SPEED_LIMIT" == "0" ]]; then
        echo "Keine Download-Geschwindigkeitsbegrenzung festgelegt (unbegrenzt)."
    else
        echo "Download-Geschwindigkeit auf '$DOWNLOAD_SPEED_LIMIT' begrenzt."
    fi
    
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    echo "Wie soll mit Spielen verfahren werden, die bereits im Verlauf existieren?"
    echo "  1) Nachfragen (Standard)"
    echo "  2) Immer erneut herunterladen"
    echo "  3) Überspringen"
    read -r -p "$(echo -e "${C_YELLOW}Ihre Wahl (1-3): ${C_RESET}")" policy_choice
    case "$policy_choice" in
        2) RE_DOWNLOAD_POLICY="always" ;;
        3) RE_DOWNLOAD_POLICY="skip" ;;
        *) RE_DOWNLOAD_POLICY="ask" ;;
    esac
    echo "Richtlinie für erneute Downloads auf '$RE_DOWNLOAD_POLICY' gesetzt."


    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    echo "Die Einrichtung ist abgeschlossen. Speichere die Konfiguration..."
    save_config # Nachricht unterdrücken
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    read -n 1 -s -r -p "Drücken Sie eine beliebige Taste, um zum Hauptmenü fortzufahren..."
}

# Funktion zum Anzeigen des Haftungsausschlusses und Einholen der Zustimmung
show_disclaimer_and_get_agreement() {
    if [[ "$DISCLAIMER_ACCEPTED" == "yes" ]]; then
        return 0
    fi

    clear
    echo -e "${C_YELLOW}=================================================================${C_RESET}"
    echo -e "${C_WHITE}${C_BOLD}Haftungsausschluss und Nutzungsbedingungen${C_RESET}"
    echo -e "${C_YELLOW}=================================================================${C_RESET}"
    echo
    echo -e "${C_BOLD}Bitte lesen Sie die folgenden Hinweise sorgfältig durch:${C_RESET}"
    echo
    echo -e "1. ${C_BOLD}Keine Zugehörigkeit:${C_RESET} Der Entwickler dieses Skripts steht in keinerlei"
    echo -e "   Verbindung zu den Betreibern von Myrient. Das Skript ist ein unabhängiges Projekt."
    echo
    echo -e "2. ${C_BOLD}Rechtliche Verantwortung:${C_RESET} Sie als Nutzer sind allein für die Einhaltung"
    echo -e "   der geltenden Gesetze in Ihrem Land verantwortlich. Das Herunterladen von"
    echo -e "   urheberrechtlich geschütztem Material kann illegal sein."
    echo
    echo -e "3. ${C_BOLD}Distanzierung von illegalen Aktivitäten:${C_RESET} Der Entwickler distanziert sich"
    echo -e "   ausdrücklich von jeglicher Form illegaler Downloads. Das Skript ist nicht"
    echo -e "   für rechtswidrige Zwecke bestimmt."
    echo
    echo -e "4. ${C_BOLD}Nutzung auf eigene Gefahr:${C_RESET} Die Nutzung des Skripts erfolgt auf Ihr eigenes"
    echo -e "   Risiko. Es wird keine Garantie für Funktionalität oder Sicherheit übernommen."
    echo
    echo -e "${C_YELLOW}=================================================================${C_RESET}"
    echo
    echo -e "Indem Sie fortfahren, bestätigen Sie, diesen Haftungsausschluss gelesen zu"
    echo -e "haben und das Skript ausschließlich für legale Zwecke zu verwenden."
    echo
    
    read -r -p "$(echo -e "Stimmen Sie diesen Bedingungen zu? (${C_GREEN}ja${C_RESET}/${C_RED}nein${C_RESET}): ")" confirm

    if [[ "$confirm" == "ja" || "$confirm" == "j" || "$confirm" == "yes" || "$confirm" == "y" ]]; then
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
    clear
    echo -e "${HEADLINE_COLOR}Haftungsausschluss-Zustimmung widerrufen${C_RESET}\n"
    echo -e "${C_YELLOW}Wenn Sie Ihre Zustimmung widerrufen, wird die Konfiguration gespeichert"
    echo -e "und das Skript wird beendet. Beim nächsten Start müssen Sie dem"
    echo -e "Haftungsausschluss erneut zustimmen, um das Skript verwenden zu können.${C_RESET}"
    echo
    read -r -p "$(echo -e "Möchten Sie Ihre Zustimmung wirklich widerrufen? (${C_GREEN}j${C_RESET}/${C_RED}n${C_RESET}) ")" confirm
    if [[ "$confirm" == "j" || "$confirm" == "J" ]]; then
        DISCLAIMER_ACCEPTED="no"
        save_config "suppress_message"
        echo -e "${C_GREEN}Ihre Zustimmung wurde widerrufen. Das Skript wird jetzt beendet.${C_RESET}"
        sleep 3
        exit 0
    else
        echo -e "${C_YELLOW}Vorgang abgebrochen. Ihre Zustimmung bleibt bestehen.${C_RESET}"
    fi
}

# Funktion zum einmaligen Abrufen der IP-Adresse und des Standorts
fetch_ip_info() {
    # Führe dies nur aus, wenn die IP-Adresse noch nicht bekannt ist
    if [[ -z "$IP_ADDRESS" ]]; then
        local response
        # Verwende einen Timeout, um das Skript nicht zu blockieren
        response=$(curl -s --connect-timeout 5 "ipinfo.io/json")

        if [[ $? -eq 0 && -n "$response" ]]; then
            # Extrahiere die Daten aus der JSON-Antwort
            IP_ADDRESS=$(echo "$response" | grep -o '"ip": *"[^"]*"' | cut -d'"' -f4)
            local city=$(echo "$response" | grep -o '"city": *"[^"]*"' | cut -d'"' -f4)
            local region=$(echo "$response" | grep -o '"region": *"[^"]*"' | cut -d'"' -f4)
            local country=$(echo "$response" | grep -o '"country": *"[^"]*"' | cut -d'"' -f4)
            IP_LOCATION="${city}, ${region}, ${country}"
        fi
    fi
}

# Funktion zum Festlegen der Download-Geschwindigkeitsbegrenzung
set_download_speed_limit() {
    local no_save="$1"
    clear
    echo -e "${HEADLINE_COLOR}Download-Geschwindigkeit festlegen${C_RESET}\n"
    echo "Geben Sie ein Limit für die Download-Geschwindigkeit an."
    echo "Verwenden Sie 'k' für Kilobytes und 'm' für Megabytes pro Sekunde (z.B. '500k', '1.5m')."
    local current_limit_display
    if [[ "$DOWNLOAD_SPEED_LIMIT" == "0" ]]; then
        current_limit_display="Unbegrenzt"
    else
        current_limit_display="$DOWNLOAD_SPEED_LIMIT"
    fi
    read -r -p "$(echo -e "${C_YELLOW}Limit eingeben (aktuell: ${C_WHITE}$current_limit_display${C_YELLOW}, leer für unbegrenzt): ${C_RESET}")" new_limit

    # Wenn die Eingabe leer ist, auf unbegrenzt (0) setzen
    DOWNLOAD_SPEED_LIMIT="${new_limit:-0}"

    echo -e "${C_GREEN}Download-Geschwindigkeitsbegrenzung auf '${DOWNLOAD_SPEED_LIMIT}' gesetzt.${C_RESET}"
    if [[ "$no_save" != "no_save" ]]; then
        save_config "suppress_message"
    fi
}

# Funktion zum Festlegen der Richtlinie für erneute Downloads
set_re_download_policy() {
    local no_save="$1"
    clear
    echo -e "${HEADLINE_COLOR}Richtlinie für erneute Downloads festlegen${C_RESET}\n"
    echo "Legen Sie fest, wie das Skript verfahren soll, wenn ein Spiel"
    echo "bereits im Download-Verlauf vorhanden ist.\n"
    echo -e "  1) ${C_YELLOW}Nachfragen${C_RESET} (ask): Vor dem erneuten Download fragen. (Standard)"
    echo -e "  2) ${C_GREEN}Immer${C_RESET} (always): Immer ohne Nachfrage erneut herunterladen."
    echo -e "  3) ${C_CYAN}Überspringen${C_RESET} (skip): Den Download automatisch überspringen.\n"

    read -r -p "$(echo -e "${C_YELLOW}Ihre Wahl (aktuell: ${C_WHITE}$RE_DOWNLOAD_POLICY${C_YELLOW}): ${C_RESET}")" policy_choice

    case "$policy_choice" in
        1|ask) RE_DOWNLOAD_POLICY="ask" ;;
        2|always) RE_DOWNLOAD_POLICY="always" ;;
        3|skip) RE_DOWNLOAD_POLICY="skip" ;;
        *)
            echo -e "${C_RED}Ungültige Auswahl. Keine Änderung vorgenommen.${C_RESET}"
            read -n 1 -s -r -p "Drücken Sie eine beliebige Taste..."
            return
            ;;
    esac
    echo -e "${C_GREEN}Richtlinie für erneute Downloads auf '${C_WHITE}$RE_DOWNLOAD_POLICY${C_GREEN}' gesetzt.${C_RESET}"
    save_config "suppress_message"
}

# Funktion zum Anzeigen des Download-Verlaufs
show_download_history() {
    clear
    echo -e "${HEADLINE_COLOR}Download-Verlauf${C_RESET}\n"
    if [ -f "$DOWNLOAD_HISTORY_LOG" ]; then
        read -r -p "$(echo -e "Möchten Sie den Verlauf durchsuchen? (${C_GREEN}j${C_RESET} zum Suchen, ${C_RED}n${C_RESET} zum Anzeigen aller Einträge) ")" search_choice
        if [[ "$search_choice" == "j" || "$search_choice" == "J" ]]; then
            read -r -p "$(echo -e "${C_YELLOW}Suchbegriff eingeben: ${C_RESET}")" search_term
            if [[ -n "$search_term" ]]; then
                echo -e "${C_CYAN}Suche nach '${C_WHITE}$search_term${C_CYAN}' im Verlauf...${C_RESET}"
                echo -e "${C_GRAY}$(print_horizontal_line)${C_RESET}"
                local search_results
                mapfile -t search_results < <(grep -i "$search_term" "$DOWNLOAD_HISTORY_LOG")
                if [ ${#search_results[@]} -gt 0 ]; then
                    printf '%s\n' "${search_results[@]}"
                else
                    echo -e "${C_YELLOW}Keine Einträge für '$search_term' gefunden.${C_RESET}"
                fi
                echo -e "${C_GRAY}$(print_horizontal_line)${C_RESET}"
            else
                 echo -e "${C_YELLOW}Kein Suchbegriff eingegeben. Vorgang abgebrochen.${C_RESET}"
            fi
        else
            echo "Die folgenden Dateien wurden bisher heruntergeladen:"
            echo -e "${C_GRAY}$(print_horizontal_line)${C_RESET}"
            # Verwende 'less' für eine bessere Ansicht bei langen Listen
            if [ "$(wc -l < "$DOWNLOAD_HISTORY_LOG")" -gt 20 ]; then
                less "$DOWNLOAD_HISTORY_LOG"
            else
                cat "$DOWNLOAD_HISTORY_LOG"
            fi
            echo -e "${C_GRAY}$(print_horizontal_line)${C_RESET}"
        fi
        echo
        read -r -p "$(echo -e "Möchten Sie den Verlauf leeren? (${C_GREEN}j${C_RESET}/${C_RED}n${C_RESET}) ")" clear_choice
        if [[ "$clear_choice" == "j" || "$clear_choice" == "J" ]]; then
            rm "$DOWNLOAD_HISTORY_LOG"
            echo -e "${C_GREEN}Der Download-Verlauf wurde geleert.${C_RESET}"
        fi
    else
        echo -e "${C_YELLOW}Es wurden noch keine Downloads protokolliert.${C_RESET}"
    fi
    read -n 1 -s -r -p "Drücken Sie eine beliebige Taste, um zum Hauptmenü zurückzukehren..."
}

# Funktion zum Entfernen doppelter Einträge aus dem Download-Verlauf
deduplicate_download_history() {
    clear
    echo -e "${HEADLINE_COLOR}Doppelte Einträge im Download-Verlauf entfernen${C_RESET}\n"

    if [ ! -f "$DOWNLOAD_HISTORY_LOG" ]; then
        echo -e "${C_YELLOW}Download-Verlauf nicht gefunden. Nichts zu tun.${C_RESET}"
    else
        local original_lines
        original_lines=$(wc -l < "$DOWNLOAD_HISTORY_LOG")
        
        local temp_history_file
        temp_history_file=$(mktemp)

        # Sortiere und entferne Duplikate, behalte die ursprüngliche Reihenfolge der ersten Vorkommen bei
        awk '!seen[$0]++' "$DOWNLOAD_HISTORY_LOG" > "$temp_history_file"

        local unique_lines
        unique_lines=$(wc -l < "$temp_history_file")
        local duplicates_found=$((original_lines - unique_lines))

        if [ "$duplicates_found" -gt 0 ]; then
            echo -e "Es wurden ${C_YELLOW}$duplicates_found${C_RESET} doppelte(r) Eintrag(e) gefunden."
            read -r -p "$(echo -e "Möchten Sie diese entfernen? (${C_GREEN}j${C_RESET}/${C_RED}n${C_RESET}) ")" confirm
            if [[ "$confirm" == "j" || "$confirm" == "J" ]]; then
                mv "$temp_history_file" "$DOWNLOAD_HISTORY_LOG"
                echo -e "${C_GREEN}Doppelte Einträge wurden erfolgreich entfernt.${C_RESET}"
            else
                rm "$temp_history_file"
                echo -e "${C_YELLOW}Vorgang abgebrochen.${C_RESET}"
            fi
        else
            rm "$temp_history_file"
            echo -e "${C_GREEN}Keine doppelten Einträge im Verlauf gefunden.${C_RESET}"
        fi
    fi
    read -n 1 -s -r -p "Drücken Sie eine beliebige Taste, um zum Hauptmenü zurückzukehren..."
}

# Funktion zum Exportieren des Download-Verlaufs in eine CSV-Datei
export_download_history_to_csv() {
    clear
    echo -e "${HEADLINE_COLOR}Download-Verlauf als CSV exportieren${C_RESET}\n"

    if [ ! -f "$DOWNLOAD_HISTORY_LOG" ]; then
        echo -e "${C_YELLOW}Download-Verlauf nicht gefunden. Nichts zu exportieren.${C_RESET}"
    else
        local default_csv_file="$SCRIPT_DIR/myrient_download_history.csv"
        read -r -p "$(echo -e "Dateiname für den CSV-Export eingeben (Standard: ${C_WHITE}$default_csv_file${C_YELLOW}): ${C_RESET}")" csv_file
        
        csv_file="${csv_file:-$default_csv_file}"
        eval csv_file="$csv_file"

        if [ -f "$csv_file" ]; then
            read -r -p "$(echo -e "Datei '${C_WHITE}$csv_file${C_RESET}' existiert bereits. Überschreiben? (${C_GREEN}j${C_RESET}/${C_RED}n${C_RESET}) ")" overwrite_confirm
            if [[ "$overwrite_confirm" != "j" && "$overwrite_confirm" != "J" ]]; then
                echo -e "${C_YELLOW}Export abgebrochen.${C_RESET}"
                read -n 1 -s -r -p "Drücken Sie eine beliebige Taste..."
                return
            fi
        fi

        echo -e "${C_CYAN}Exportiere Verlauf nach '${C_WHITE}$csv_file${C_CYAN}'...${C_RESET}"
        echo '"Timestamp","Console","Game"' > "$csv_file"

        local lines_exported=0
        while IFS= read -r line; do
            local timestamp console game
            timestamp=$(echo "$line" | sed -n 's/^\[\([^]]*\)\].*/\1/p')
            console=$(echo "$line" | sed -n 's/.* - \[\([^]]*\)\] - .*/\1/')
            game=$(echo "$line" | sed -n 's/.* - \[.*\] - \(.*\)/\1/p')
            
            echo "\"$timestamp\",\"$console\",\"$game\"" >> "$csv_file"
            ((lines_exported++))
        done < "$DOWNLOAD_HISTORY_LOG"

        echo -e "${C_GREEN}Erfolgreich ${C_WHITE}$lines_exported${C_GREEN} Einträge nach '${C_WHITE}$csv_file${C_GREEN}' exportiert.${C_RESET}"
    fi
    read -n 1 -s -r -p "Drücken Sie eine beliebige Taste, um zum Hauptmenü zurückzukehren..."
}
# Funktion "Über das Skript"
show_about() {
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    echo -e "${HEADLINE_COLOR}Über Myrient CLI:${C_RESET}"
    echo -e "  ${C_CYAN}Version:${C_RESET} ${C_WHITE}$VERSION${C_RESET}"
    echo -e "  ${C_CYAN}Beschreibung:${C_RESET} Ein Kommandozeilen-Tool zum Suchen und Herunterladen von Spielen"
    echo "                aus dem Myrient-Archiv."
    echo -e "  ${C_CYAN}GitHub Repository:${C_RESET} ${C_WHITE}https://github.com/${GITHUB_REPO}${C_RESET}"
    echo -e "  ${C_CYAN}Lizenz:${C_RESET} ${C_WHITE}MIT${C_RESET}"
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    read -n 1 -s -r -p "Drücken Sie eine beliebige Taste, um zum Hauptmenü zurückzukehren..."
}

# Funktion zum automatischen Entpacken von Archiven
extract_archive() {
    local filepath="$1"
    local filename
    filename=$(basename "$filepath")
    local extract_dir
    extract_dir="${filepath%.*}" # Verzeichnisname = Dateiname ohne Endung

    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    echo "Prüfe, ob '$filename' entpackt werden kann..."

    case "$filename" in
        *.zip)
            echo "ZIP-Archiv erkannt. Entpacke nach '$extract_dir'..."
            mkdir -p "$extract_dir"
            if unzip -o "$filepath" -d "$extract_dir"; then
                echo -e "${C_GREEN}Entpacken erfolgreich.${C_RESET}"
                if [[ "$DELETE_ARCHIVE_AFTER_EXTRACT" == "yes" ]]; then
                    rm "$filepath" && echo -e "${C_GREEN}Archiv '$filename' wurde gelöscht.${C_RESET}"
                fi
            fi
            ;;
        *.7z)
            echo "7-Zip-Archiv erkannt. Entpacke nach '$extract_dir'..."
            mkdir -p "$extract_dir"
            if 7z x "$filepath" -o"$extract_dir" -y; then
                echo -e "${C_GREEN}Entpacken erfolgreich.${C_RESET}"
                if [[ "$DELETE_ARCHIVE_AFTER_EXTRACT" == "yes" ]]; then
                    rm "$filepath" && echo -e "${C_GREEN}Archiv '$filename' wurde gelöscht.${C_RESET}"
                fi
            fi
            ;;
        *)
            echo "Kein unterstütztes Archivformat (.zip, .7z) für '$filename' gefunden."
            ;;
    esac
}

# Funktion zum Durchführen des Self-Updates
perform_self_update() {
    local base_url="https://raw.githubusercontent.com/elyps/myrient-cli/refs/heads/main"
    local new_script_url="${base_url}/myrient-cli.sh"
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

    echo "Lade neue VERSION-Datei von $new_version_url herunter..."
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

    echo "Update erfolgreich abgeschlossen!"
    echo "Bitte starten Sie das Skript neu, um die Änderungen zu übernehmen."
    exit 0
}

# Funktion zum Suchen nach Skript-Updates auf GitHub
check_for_updates() {
    local mode="$1" # "auto" oder leer
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    echo -e "${HEADLINE_COLOR}Suche nach Updates auf GitHub...${C_RESET}"

    if [[ -z "$GITHUB_REPO" || "$GITHUB_REPO" == "Benutzername/Repo-Name" ]]; then
        echo "Information: Die GitHub-Repository-Variable ist nicht konfiguriert."
        echo "Bitte passen Sie die 'GITHUB_REPO' Variable am Anfang des Skripts an."
        echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
        read -n 1 -s -r -p "Drücken Sie eine beliebige Taste, um zum Hauptmenü zurückzukehren..."
        return
    fi

    # Annahme: Die Version steht in einer Datei namens 'VERSION' im Hauptverzeichnis des Repos.
    # Extrahiere 'user/repo' aus verschiedenen URL-Formaten
    local repo_path
    repo_path=$(echo "$GITHUB_REPO" | sed -e 's|https://github.com/||' -e 's|\.git$||')
    local version_url="https://raw.githubusercontent.com/elyps/myrient-cli/refs/heads/main/src/VERSION"
    local response
    response=$(curl -sL -w "\n%{http_code}" "$version_url")
    local http_code
    http_code=$(echo "$response" | tail -n1)
    local latest_version
    latest_version=$(echo "$response" | sed '$d')

    if [[ "$http_code" -ne 200 ]]; then
        echo "Fehler: Konnte die neueste Version nicht von GitHub abrufen (HTTP-Status: $http_code)."
        echo "Bitte überprüfen Sie Ihre Internetverbindung und den Repository-Namen."
    else
        # Extrahiere die Versionsnummer aus "VERSION=1.2.3"
        latest_version=$(echo "$latest_version" | cut -d'=' -f2)
        # Verwende sort -V für einen robusten Versionsvergleich. Wenn die aktuelle Version die gleiche oder neuer ist, dann ist es aktuell.
        if [[ "$(printf '%s\n' "$VERSION" "$latest_version" | sort -V | tail -n 1)" == "$VERSION" ]] && [[ "$VERSION" == "$latest_version" ]]; then
            echo -e "${C_GREEN}Sie verwenden bereits die neueste Version ($VERSION).${C_RESET}"
        else
            echo -e "${C_YELLOW}Eine neue Version (${C_GREEN}$latest_version${C_YELLOW}) ist verfügbar! (Ihre Version: ${C_RED}$VERSION${C_YELLOW})${C_RESET}"
            read -r -p "$(echo -e "Möchten Sie das Skript jetzt automatisch aktualisieren? (${C_GREEN}j${C_RESET}/${C_RED}n${C_RESET}) ")" update_confirm
            if [[ "$update_confirm" == "j" || "$update_confirm" == "J" ]]; then
                perform_self_update
            else
                echo -e "${C_YELLOW}Update abgebrochen. Sie können manuell von https://github.com/${GITHUB_REPO} aktualisieren.${C_RESET}"
                if [[ "$mode" == "auto" ]]; then
                    read -n 1 -s -r -p "Drücken Sie eine beliebige Taste, um fortzufahren..."
                fi
            fi
        fi
    fi

    # Im manuellen Modus immer auf eine Eingabe warten
    if [[ "$mode" != "auto" ]]; then
        echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
        read -n 1 -s -r -p "Drücken Sie eine beliebige Taste, um zum Hauptmenü zurückzukehren..."
    fi
}

# Funktion zum Festlegen der bevorzugten Suchregionen
set_search_regions() {
    local no_save="$1"
    clear
    echo -e "${HEADLINE_COLOR}Bevorzugte Suchregionen festlegen${C_RESET}\n"
    echo "Geben Sie eine oder mehrere Regionen durch Leerzeichen getrennt ein (z.B. 'Europe Germany')."
    echo "Die Suche wird dann nur Ergebnisse anzeigen, die eine dieser Regionen im Namen enthalten."
    echo "Lassen Sie die Eingabe leer, um den Filter zu deaktivieren."
    read -r -p "$(echo -e "${C_YELLOW}Regionen eingeben (aktuell: ${C_WHITE}${SEARCH_REGIONS:-Keine}${C_YELLOW}): ${C_RESET}")" new_regions

    # Trim leading/trailing whitespace
    new_regions=$(echo "$new_regions" | sed 's/^[ \t]*//;s/[ \t]*$//')

    SEARCH_REGIONS="$new_regions"
    echo -e "${C_GREEN}Bevorzugte Suchregionen auf '${SEARCH_REGIONS:-Keine}' gesetzt.${C_RESET}"
    if [[ "$no_save" != "no_save" ]]; then
        save_config "suppress_message"
    fi
}

# Funktion zum Festlegen der auszuschließenden Suchbegriffe
set_exclude_keywords() {
    local no_save="$1"
    clear
    echo -e "${HEADLINE_COLOR}Auszuschließende Suchbegriffe festlegen${C_RESET}\n"
    echo "Geben Sie ein oder mehrere Wörter durch Leerzeichen getrennt ein (z.B. 'Demo Beta')."
    echo "Die Suche wird dann Ergebnisse ausschließen, die eines dieser Wörter im Namen enthalten."
    echo "Lassen Sie die Eingabe leer, um den Filter zu deaktivieren."
    read -r -p "$(echo -e "${C_YELLOW}Wörter eingeben (aktuell: ${C_WHITE}${SEARCH_EXCLUDE_KEYWORDS:-Keine}${C_YELLOW}): ${C_RESET}")" new_keywords

    # Trim leading/trailing whitespace
    new_keywords=$(echo "$new_keywords" | sed 's/^[ \t]*//;s/[ \t]*$//')

    SEARCH_EXCLUDE_KEYWORDS="$new_keywords"
    echo -e "${C_GREEN}Auszuschließende Suchbegriffe auf '${SEARCH_EXCLUDE_KEYWORDS:-Keine}' gesetzt.${C_RESET}"
    if [[ "$no_save" != "no_save" ]]; then
        save_config "suppress_message"
    fi
}

# Funktion zum Umschalten des automatischen Löschens von Archiven
toggle_delete_archive_after_extract() {
    local no_save="$1"
    echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
    if [[ "$DELETE_ARCHIVE_AFTER_EXTRACT" == "yes" ]]; then
        DELETE_ARCHIVE_AFTER_EXTRACT="no"
        echo -e "Automatisches Löschen von Archiven nach dem Entpacken ist jetzt ${C_RED}DEAKTIVIERT${C_RESET}."
    else
        DELETE_ARCHIVE_AFTER_EXTRACT="yes"
        echo -e "Automatisches Löschen von Archiven nach dem Entpacken ist jetzt ${C_GREEN}AKTIVIERT${C_RESET}."
    fi
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
    # show_header wird jetzt in der Hauptschleife aufgerufen
    echo -e "${HEADLINE_COLOR}${C_BOLD}Hauptmenü:${C_RESET}"
    
    # Manuelle Menüpunkte für bessere Kontrolle über die Anzeige
    local menu_items=(
        "Konsole auswählen"
        "Download-Verzeichnis festlegen"
        "Anzahl gleichzeitiger Downloads festlegen" #3
        "Download-Geschwindigkeit festlegen" # 4
        "Richtlinie für erneute Downloads festlegen" # 5
        "Automatische Verifizierung umschalten"
        "Bevorzugte Suchregionen festlegen"
        "Auszuschließende Suchbegriffe festlegen"
        "Automatisches Entpacken umschalten"
        "Archiv nach Entpacken löschen umschalten"
        "Automatische Update-Prüfung umschalten"
        "Konfigurationsdatei bearbeiten" # 12
        "Konfiguration sichern" # 13
        "Konfiguration wiederherstellen" # 14
        "Veraltete Backups löschen" #14
        "Konfiguration zurücksetzen" # 15
        "Haftungsausschluss-Zustimmung widerrufen" # 16
        "Laufende Downloads anzeigen" #17
        "Gesamtgröße der Downloads anzeigen" #18
        "Download-Verlauf anzeigen" # 19
        "Doppelte Einträge im Verlauf entfernen" # 20
        "Download-Verlauf als CSV exportieren" # 21
        "Abgeschlossene Download-Logs entfernen" # 22
        "Alle Downloads abbrechen" # 23
        "Nach Updates suchen"
        "Über das Skript"
        "Beenden"
    )

    for i in "${!menu_items[@]}"; do
        # Use printf for consistent alignment
        printf "  ${C_YELLOW}%2d)${C_RESET} %s\n" "$((i+1))" "${menu_items[$i]}"
    done
    echo
}

# Hauptfunktion des Skripts
main() {
    check_dependencies wget curl md5sum sha1sum bc unzip 7z
    
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
        show_main_menu
        read -r -p "$(echo -e "${C_YELLOW}Ihre Wahl: ${C_RESET}")" choice

        case $choice in
            1) select_console_and_download ;;
            2) set_download_directory; save_config "suppress_message" ;;
            3) set_max_downloads; save_config "suppress_message" ;;
            4) set_download_speed_limit; save_config "suppress_message" ;;
            5) set_re_download_policy ;;
            6) toggle_auto_verify; save_config "suppress_message" ;;
            7) set_search_regions; save_config "suppress_message" ;;
            8) set_exclude_keywords; save_config "suppress_message" ;;
            9) toggle_auto_extract; save_config "suppress_message" ;;
            10) toggle_delete_archive_after_extract; save_config "suppress_message" ;;
            11) toggle_auto_update_check; save_config "suppress_message" ;;
            12) edit_config_file ;;
            13) backup_config ;;
            14) restore_config ;;
            15) cleanup_backups ;;
            16) reset_config ;;
            17) revoke_disclaimer_agreement ;;
            18) show_background_downloads ;;
            19) show_total_download_size ;;
            20) show_download_history ;;
            21) deduplicate_download_history ;;
            22) export_download_history_to_csv ;;
            23) cleanup_stale_logs ;;
            24) cancel_background_downloads ;;
            25) check_for_updates ;;
            26) show_about ;;
            27) echo "Skript wird beendet."; exit 0 ;;
            *) echo -e "${C_RED}Ungültige Auswahl. Bitte erneut versuchen.${C_RESET}"; read -n 1 -s -r; ;;
        esac
    done
}

select_console_and_download() {
    clear
    echo -e "${HEADLINE_COLOR}Lade Konsolenliste...${C_RESET}"
    # grep '^\S\+/\s' filtert nach Zeilen, bei denen das erste Wort (der Pfad) mit einem / endet,
    # was auf ein Verzeichnis hinweist. Korrigiert, um auf das erste Feld zu prüfen, das mit / endet.
    mapfile -t consoles < <(get_links "/files/Redump/" | grep '^[^|]*/|' | sort)

    if [ ${#consoles[@]} -eq 0 ]; then
        echo "Keine Konsolen im Verzeichnis /files/Redump/ gefunden."
        return 1
    fi

    # Extrahiere nur den Namen der Konsole für eine saubere Ausgabe
    local display_consoles=()
    for item in "${consoles[@]}"; do
        display_consoles+=("$(echo "$item" | cut -d'|' -f2)")
    done

    echo -e "${HEADLINE_COLOR}Bitte wählen Sie eine Konsole aus:${C_RESET}"
    select console_display_name in "${display_consoles[@]}" "Zurück zum Hauptmenü"; do
        if [[ "$console_display_name" == "Zurück zum Hauptmenü" ]]; then
            return
        elif [[ -n "$console_display_name" ]]; then
            # Der Pfad bleibt URL-kodiert für die weitere Verwendung
            # REPLY ist 1-basiert, Arrays sind 0-basiert
            local selected_index=$((REPLY - 1))
            local console_path
            console_path=$(echo "${consoles[$selected_index]}" | cut -d'|' -f1)
            search_and_download_games "$console_path"
            break # Zurück zum Hauptmenü nach der Spielesuche
        else
            echo -e "${C_RED}Ungültige Auswahl. Bitte erneut versuchen.${C_RESET}"
        fi
    done
}

search_and_download_games() {
    local console_path="$1"
    if [[ -z "$console_path" ]]; then return; fi
    
    # Extrahiere den sauberen Konsolennamen für das Protokoll
    local console_name=$(url_decode "$console_path" | sed -e 's|^/files/Redump/||' -e 's|/$||')
    
        echo -n -e "${C_CYAN}Lade Spieleliste für ${C_WHITE}$(url_decode "$console_path")${C_CYAN}... Dies kann einen Moment dauern.${C_RESET}"
        # Start spinner in the background
        spinner &
        SPINNER_PID=$!
        # Ensure spinner is killed on script exit
        trap "kill $SPINNER_PID 2>/dev/null; exit" INT TERM EXIT

        # grep -v '^\S\+/\s' filtert umgekehrt alle Verzeichnisse heraus, sodass nur Dateien (Spiele) übrig bleiben.
        mapfile -t all_games < <(get_links "$console_path" | grep -v '^[^|]*/|' | sort -u)

        # Stop spinner
        kill $SPINNER_PID
        wait $SPINNER_PID 2>/dev/null
        echo -e "\r${C_GREEN}Laden der Spieleliste abgeschlossen.                ${C_RESET}"
        if [ ${#all_games[@]} -eq 0 ]; then
            echo "Keine Spiele in diesem Verzeichnis gefunden."
            # Anstatt zu beenden, zurück zur Konsolenauswahl
            read -n 1 -s -r -p "Drücken Sie eine beliebige Taste, um fortzufahren..."
            return
        fi

        while true; do
            clear
            echo -e "${HEADLINE_COLOR}=================================================================${C_RESET}"
            echo -e "Aktuelle Konsole: ${C_WHITE}$(url_decode "$console_path")${C_RESET}"
            read -r -p "$(echo -e "${C_YELLOW}Geben Sie einen Suchbegriff ein (oder 'q' zum Zurückkehren): ${C_RESET}")" game_keyword

            if [[ "$game_keyword" == "q" ]]; then
                echo -e "${C_YELLOW}Zurück zur Konsolenauswahl...${C_RESET}"
                return
            fi

            if [[ -z "$game_keyword" ]]; then
                echo -e "${C_RED}Suchbegriff darf nicht leer sein.${C_RESET}"
                continue
            fi

            if [ ${#game_keyword} -eq 1 ]; then
                echo -e "${C_CYAN}Suche nach Spielen, die mit '${C_WHITE}$game_keyword${C_CYAN}' beginnen...${C_RESET}"
                mapfile -t game_results < <(printf '%s\n' "${all_games[@]}" | grep -i "^[^|]*|${game_keyword}")
            else
                echo -e "${C_CYAN}Suche nach Spielen, die '${C_WHITE}$game_keyword${C_CYAN}' enthalten...${C_RESET}"
                mapfile -t game_results < <(printf '%s\n' "${all_games[@]}" | grep -iF "$game_keyword")
            fi

            # Wende den optionalen Regionsfilter an, wenn er gesetzt ist
            if [[ -n "$SEARCH_REGIONS" ]]; then
                echo -e "${C_CYAN}Filtere Ergebnisse nach Region(en): '${C_WHITE}$SEARCH_REGIONS${C_CYAN}'...${C_RESET}"
                local filtered_results=()
                # Erstelle ein Regex-Muster wie (Region1|Region2|...)
                local region_pattern
                region_pattern=$(echo "$SEARCH_REGIONS" | sed 's/ /|/g')
                # Filtere die bisherigen Ergebnisse
                mapfile -t filtered_results < <(printf '%s\n' "${game_results[@]}" | grep -iE "$region_pattern")
                game_results=("${filtered_results[@]}")
            fi

            # Wende den optionalen Ausschlussfilter an, wenn er gesetzt ist
            if [[ -n "$SEARCH_EXCLUDE_KEYWORDS" ]]; then
                echo -e "${C_CYAN}Filtere Ergebnisse, um auszuschließen: '${C_WHITE}$SEARCH_EXCLUDE_KEYWORDS${C_CYAN}'...${C_RESET}"
                local excluded_results=()
                # Erstelle ein Regex-Muster wie (Wort1|Wort2|...)
                local exclude_pattern
                exclude_pattern=$(echo "$SEARCH_EXCLUDE_KEYWORDS" | sed 's/ /|/g')
                # Filtere die bisherigen Ergebnisse mit grep -v (invert match)
                mapfile -t excluded_results < <(printf '%s\n' "${game_results[@]}" | grep -viE "$exclude_pattern")
                game_results=("${excluded_results[@]}")
            fi


            if [ ${#game_results[@]} -eq 0 ]; then
                echo -e "${C_YELLOW}Keine Spiele mit diesem Namen gefunden.${C_RESET}"
                continue
            fi

            echo -e "${HEADLINE_COLOR}Gefundene Spiele:${C_RESET}"
            i=0
            # Erstelle ein Anzeige-Array und gib gleichzeitig eine nummerierte Liste aus
            for item in "${game_results[@]}"; do
                local display_name
                display_name=$(echo "$item" | cut -d'|' -f2)
                local size
                size=$(echo "$item" | cut -d'|' -f3)
                i=$((i+1))

                # Prüfe, ob das Spiel bereits im Download-Verlauf existiert
                if [ -f "$DOWNLOAD_HISTORY_LOG" ] && grep -q -F -- "$display_name" "$DOWNLOAD_HISTORY_LOG"; then
                    # Wenn ja, markiere es als heruntergeladen
                    local marker="${C_GREEN}[✔]${C_RESET} "
                    printf "  ${C_YELLOW}%2d)${C_RESET} ${marker}${C_GRAY}%-66.66s${C_RESET} [${C_GREEN}%7s${C_RESET}]\n" "$i" "$display_name" "$size"
                else
                    # Andernfalls zeige es normal an
                    printf "  ${C_YELLOW}%2d)${C_RESET} ${C_WHITE}%-70.70s${C_RESET} [${C_GREEN}%7s${C_RESET}]\n" "$i" "$display_name" "$size"
                fi
            done

            while true; do
                echo
                read -r -p "$(echo -e "${C_YELLOW}Geben Sie die Nummern der Spiele ein (z.B. '1 3 4', 'all', 'q'): ${C_RESET}")" selection

                if [[ "$selection" == "q" ]] || [[ -z "$selection" ]]; then
                    echo -e "${C_YELLOW}Download abgebrochen.${C_RESET}"
                    break
                fi

                local games_to_download=()
                if [[ "$selection" == "all" ]]; then
                    games_to_download=("${game_results[@]}")
                else
                    # Ersetze Kommas und andere Trennzeichen durch Leerzeichen
                    selection_numbers=$(echo "$selection" | tr -s ',;' '  ')
                    for num in $selection_numbers; do
                        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#game_results[@]}" ]; then
                            games_to_download+=("${game_results[$num-1]}")
                        else
                            echo -e "${C_YELLOW}Warnung: Ungültige Nummer '$num' wird ignoriert.${C_RESET}"
                        fi
                    done
                fi

                if [ ${#games_to_download[@]} -gt 0 ]; then
                    read -r -p "$(echo -e "Downloads im Hintergrund ausführen? (${C_GREEN}j${C_RESET}/${C_RED}n${C_RESET}) ")" background_choice

                    if [[ "$background_choice" == "j" || "$background_choice" == "J" ]]; then
                        echo "Starte Downloads im Hintergrund (Maximal $MAX_CONCURRENT_DOWNLOADS gleichzeitig)..."
                        local count=0
                        for game_choice in "${games_to_download[@]}"; do
                            # Warte, wenn die maximale Anzahl an Prozessen erreicht ist
                            if [[ $count -ge $MAX_CONCURRENT_DOWNLOADS ]]; then
                                echo -e "${C_CYAN}Warte auf einen freien Download-Slot...${C_RESET}"
                                wait -n
                                ((count--))
                            fi
                            path=$(echo "$game_choice" | cut -d'|' -f1)
                            name=$(echo "$game_choice" | cut -d'|' -f2)
                            # Eindeutige Log-Datei für jeden Download
                            mkdir -p "$PROJECT_ROOT/logs"
                            log_file="$PROJECT_ROOT/logs/$(basename "$name").log"

                            echo -e "${C_CYAN}Starte Hintergrund-Download für: ${C_WHITE}$name${C_RESET}" 
                            wget -b -c -P "$DOWNLOAD_DIR" --limit-rate="$DOWNLOAD_SPEED_LIMIT" --progress=bar:force:noscroll -o "$log_file" -- "${BASE_URL}${path}" &
                            ((count++))
                        done
                        echo "Alle Downloads wurden in die Warteschlange gestellt. Warten bis alle fertig sind..."
                        wait # Warte auf alle Hintergrundprozesse in dieser Schleife
                        # Protokolliere die abgeschlossenen Downloads
                        echo "Protokolliere abgeschlossene Hintergrund-Downloads..."
                        for game_choice in "${games_to_download[@]}"; do
                            local name=$(echo "$game_choice" | cut -d'|' -f2)
                            mkdir -p "$(dirname "$DOWNLOAD_HISTORY_LOG")"
                            echo "[$(date '+%Y-%m-%d %H:%M:%S')] - [$console_name] - $name" >> "$DOWNLOAD_HISTORY_LOG"
                        done
                        if [[ "$AUTO_EXTRACT" == "yes" ]]; then
                            for game_choice in "${games_to_download[@]}"; do
                                extract_archive "$DOWNLOAD_DIR/$(basename "$(echo "$game_choice" | cut -d'|' -f2)")"
                            done
                        fi
                        echo -e "${C_GREEN}Alle Hintergrund-Downloads dieser Sitzung sind abgeschlossen.${C_RESET}"
                    else
                        echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
                        for game_choice in "${games_to_download[@]}"; do
                            path=$(echo "$game_choice" | cut -d'|' -f1)
                            name=$(echo "$game_choice" | cut -d'|' -f2)
                            echo -e "${C_CYAN}Starte Download für: ${C_WHITE}$name${C_RESET}"
                            if wget -P "$DOWNLOAD_DIR" -c --limit-rate="$DOWNLOAD_SPEED_LIMIT" --show-progress "${BASE_URL}${path}"; then
                                echo -e "${C_GREEN}Download von '$name' abgeschlossen.${C_RESET}"
                                # Protokolliere den erfolgreichen Download
                                mkdir -p "$(dirname "$DOWNLOAD_HISTORY_LOG")"
                                echo "[$(date '+%Y-%m-%d %H:%M:%S')] - [$console_name] - $name" >> "$DOWNLOAD_HISTORY_LOG"
                                # Lösche die Log-Datei, falls eine durch einen vorherigen fehlgeschlagenen Versuch existiert
                                rm -f "$PROJECT_ROOT/logs/$(basename "$name").log" 2>/dev/null
                                if [[ "$AUTO_EXTRACT" == "yes" ]]; then
                                    extract_archive "$DOWNLOAD_DIR/$name"
                                fi
                                verify_file_integrity "$DOWNLOAD_DIR/$name"
                            fi
                            echo -e "${HEADLINE_COLOR}-----------------------------------------------------------------${C_RESET}"
                        done
                    fi
                fi
                break # Verlässt die Auswahl-Schleife nach der Verarbeitung
            done # Ende der Auswahl-Schleife
        done # Ende der Spielesuche-Schleife
}

# Starte die Hauptfunktion
# Stellt sicher, dass das Skript auch bei Strg+C sauber beendet wird.
trap "echo; echo 'Skript abgebrochen.'; exit 0" INT TERM
main
