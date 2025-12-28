#!/bin/bash

# ==============================================================================
#
# manage.sh - Installation & Uninstallation Manager
#
# Description:   This script manages the system-wide installation (alias)
#                of the myrient-cli script.
#
# Usage:         ./manage.sh [install|uninstall|clean|status|update|backup]
#
# ==============================================================================

# --- Gemeinsame Variablen & Farben ---
C_RESET='\033[0m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_CYAN='\033[0;36m'
C_RED='\033[0;31m'
C_WHITE='\033[1;37m'

# Das Verzeichnis, in dem sich dieses Skript befindet (das Projekt-Stammverzeichnis)
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
LAUNCHER_SCRIPT="$SCRIPT_DIR/start.sh"
ALIAS_NAME="myrient"
ALIAS_COMMAND="alias $ALIAS_NAME='bash \"$LAUNCHER_SCRIPT\"'"

# --- Funktionen ---

do_install() {
    echo -e "${C_CYAN}Füge Alias zum Starten von myrient-cli zu ${C_YELLOW}$RC_FILE${C_CYAN} hinzu...${C_RESET}"

    if [ ! -f "$RC_FILE" ]; then
        echo -e "${C_YELLOW}Die Konfigurationsdatei ${C_WHITE}$RC_FILE${C_YELLOW} wurde nicht gefunden.${C_RESET}"
        read -r -p "$(echo -e "Soll sie erstellt werden? (${C_GREEN}j${C_RESET}/${C_RED}n${C_RESET}) ")" create_rc
        if [[ "$create_rc" != "j" && "$create_rc" != "J" ]]; then
            echo -e "${C_RED}Installation abgebrochen.${C_RESET}"
            exit 1
        fi
        touch "$RC_FILE"
        echo -e "${C_GREEN}Datei ${C_WHITE}$RC_FILE${C_GREEN} wurde erstellt.${C_RESET}"
    fi

    if grep -q "alias $ALIAS_NAME=" "$RC_FILE"; then
        echo -e "${C_YELLOW}Warnung: Ein Alias mit dem Namen '$ALIAS_NAME' existiert bereits in Ihrer ${C_WHITE}$RC_FILE${C_YELLOW}. Es werden keine Änderungen vorgenommen.${C_RESET}"
    else
        echo -e "\n# Alias für myrient-cli (hinzugefügt durch manage.sh)" >> "$RC_FILE"
        echo "$ALIAS_COMMAND" >> "$RC_FILE"
        echo -e "${C_GREEN}Installation erfolgreich!${C_RESET}"
        echo -e "Sie können das Skript jetzt von überall mit dem Befehl '${C_YELLOW}$ALIAS_NAME${C_RESET}' starten."
        echo -e "Bitte laden Sie Ihre Konfiguration neu mit '${C_YELLOW}source $RC_FILE${C_RESET}' oder öffnen Sie ein neues Terminalfenster."
    fi
}

do_uninstall() {
    echo -e "${C_CYAN}Überprüfe ${C_YELLOW}$RC_FILE${C_CYAN} auf den myrient-cli Alias...${C_RESET}"

    if [ ! -f "$RC_FILE" ] || ! grep -q "alias $ALIAS_NAME=" "$RC_FILE"; then
        echo -e "${C_YELLOW}Der Alias wurde in ${C_WHITE}$RC_FILE${C_YELLOW} nicht gefunden. Es ist nichts zu tun.${C_RESET}"
    else
        sed -i.bak -e "/^# Alias für myrient-cli (hinzugefügt durch manage.sh)/d" -e "/^alias $ALIAS_NAME='.*myrient.sh.*'/d" "$RC_FILE"
        echo -e "${C_GREEN}Deinstallation erfolgreich!${C_RESET}"
        echo -e "Der Alias '${C_YELLOW}$ALIAS_NAME${C_RESET}' wurde aus Ihrer Konfigurationsdatei entfernt."
        echo -e "Ein Backup Ihrer vorherigen Konfiguration wurde als '${C_YELLOW}$RC_FILE.bak${C_RESET}' gespeichert."
        echo -e "Bitte laden Sie Ihre Konfiguration neu mit '${C_YELLOW}source $RC_FILE${C_RESET}' oder öffnen Sie ein neues Terminalfenster."
    fi
}

do_clean() {
    echo -e "${C_CYAN}Suche nach Konfigurations- und Verlaufsdateien zum Bereinigen...${C_RESET}"

    local config_file="$SCRIPT_DIR/config/.myrient_cli_rc"
    local history_file="$SCRIPT_DIR/logs/.download_history"
    local download_dir="$SCRIPT_DIR/downloads" # Standard-Download-Verzeichnis
    local files_to_delete=()

    if [ -f "$config_file" ]; then
        files_to_delete+=("$config_file")
    fi
    if [ -f "$history_file" ]; then
        files_to_delete+=("$history_file")
    fi

    # Lese das Download-Verzeichnis aus der Konfigurationsdatei, falls vorhanden
    if [ -f "$config_file" ]; then
        # Extrahiere den Pfad aus der Konfigurationsdatei, ohne sie zu sourcen
        config_download_dir=$(grep '^DOWNLOAD_DIR=' "$config_file" | cut -d'=' -f2 | tr -d '"')
        [ -n "$config_download_dir" ] && download_dir="$config_download_dir"
    fi

    if [ ${#files_to_delete[@]} -eq 0 ] && [ ! -d "$download_dir" ]; then
        echo -e "${C_YELLOW}Keine Konfigurations-, Verlaufs- oder Download-Dateien gefunden. Nichts zu tun.${C_RESET}"
        return
    fi

    echo -e "${C_YELLOW}Warnung: Diese Aktion ist nicht umkehrbar!${C_RESET}"
    echo "Die folgenden Dateien werden ${C_RED}permanent gelöscht${C_RESET}:"
    for file in "${files_to_delete[@]}"; do
        echo "  - $file"
    done
    read -r -p "$(echo -e "Möchten Sie wirklich fortfahren? (${C_GREEN}j${C_RESET}/${C_RED}n${C_RESET}) ")" confirm

    if [[ "$confirm" == "j" || "$confirm" == "J" ]]; then
        for file in "${files_to_delete[@]}"; do
            rm -f "$file" && echo -e "${C_GREEN}Gelöscht: $file${C_RESET}"
        done
    else
        echo -e "${C_YELLOW}Vorgang für Konfigurationsdateien abgebrochen.${C_RESET}"
    fi

    # Frage separat nach dem Leeren des Download-Verzeichnisses
    if [ -d "$download_dir" ] && [ -n "$(ls -A "$download_dir")" ]; then
        echo
        echo -e "${C_YELLOW}Das Download-Verzeichnis '${C_WHITE}$download_dir${C_YELLOW}' ist nicht leer.${C_RESET}"
        read -r -p "$(echo -e "Möchten Sie den ${C_RED}gesamten Inhalt${C_RESET} dieses Verzeichnisses löschen? (${C_GREEN}j${C_RESET}/${C_RED}n${C_RESET}) ")" clean_downloads_confirm
        if [[ "$clean_downloads_confirm" == "j" || "$clean_downloads_confirm" == "J" ]]; then
            echo -e "${C_CYAN}Leere Download-Verzeichnis...${C_RESET}"
            rm -rf "${download_dir:?}"/* && echo -e "${C_GREEN}Download-Verzeichnis wurde geleert.${C_RESET}"
        fi
    fi

    # Frage separat nach dem Löschen der Backup-Dateien
    mapfile -t backup_files < <(find "$SCRIPT_DIR/backups" -maxdepth 1 -type f \( -name "*.zip" -o -name "*.bak" \))
    if [ ${#backup_files[@]} -gt 0 ]; then
        echo
        echo -e "${C_YELLOW}Es wurden ${#backup_files[@]} Backup-Dateien (.zip, .bak) gefunden.${C_RESET}"
        read -r -p "$(echo -e "Möchten Sie diese ${C_RED}ebenfalls löschen${C_RESET}? (${C_GREEN}j${C_RESET}/${C_RED}n${C_RESET}) ")" clean_backups_confirm
        if [[ "$clean_backups_confirm" == "j" || "$clean_backups_confirm" == "J" ]]; then
            echo -e "${C_CYAN}Lösche Backup-Dateien...${C_RESET}"
            for file in "${backup_files[@]}"; do
                rm -f "$file" && echo -e "${C_GREEN}Gelöscht: $(basename "$file")${C_RESET}"
            done
        fi
    fi

    # Eine abschließende Meldung, wenn mindestens eine Aktion durchgeführt wurde.
    # Die Variable 'confirm' stammt aus der ersten Abfrage.
    if [[ "$confirm" == "j" || "$confirm" == "J" ]] || [[ "$clean_downloads_confirm" == "j" || "$clean_downloads_confirm" == "J" ]] || [[ "$clean_backups_confirm" == "j" || "$clean_backups_confirm" == "J" ]]; then
        echo -e "${C_GREEN}Bereinigungsvorgang abgeschlossen.${C_RESET}"
    fi

}

do_backup() {
    echo -e "${C_CYAN}Erstelle ein Backup des gesamten Projektverzeichnisses...${C_RESET}"

    if ! command -v zip &> /dev/null; then
        echo -e "${C_RED}Fehler: Das Programm 'zip' wurde nicht gefunden. Bitte installieren Sie es, um Backups zu erstellen.${C_RESET}"
        return
    fi

    mkdir -p "$SCRIPT_DIR/backups"
    local backup_filename="myrient-cli-backup-$(date +%Y-%m-%d_%H-%M-%S).zip"
    
    echo -e "Das Backup wird als '${C_WHITE}$backup_filename${C_RESET}' im Verzeichnis 'backups' gespeichert."

    # -r: rekursiv, .: aktuelles Verzeichnis, -x: schließe Muster aus
    if zip -r "$SCRIPT_DIR/backups/$backup_filename" . -x "backups/*" -x "*.bak" -x "*.tmp" -x "*/__pycache__/*"; then
        echo -e "${C_GREEN}Backup erfolgreich erstellt!${C_RESET}"
    else
        echo -e "${C_RED}Fehler beim Erstellen des Backups.${C_RESET}"
    fi
}

do_restore() {
    echo -e "${C_CYAN}Suche nach Backup-Archiven zum Wiederherstellen...${C_RESET}"

    if ! command -v unzip &> /dev/null; then
        echo -e "${C_RED}Fehler: Das Programm 'unzip' wurde nicht gefunden. Bitte installieren Sie es, um Backups wiederherzustellen.${C_RESET}"
        return
    fi

    mapfile -t backup_files < <(find "$SCRIPT_DIR/backups" -maxdepth 1 -type f -name "myrient-cli-backup-*.zip" | sort -r)

    if [ ${#backup_files[@]} -eq 0 ]; then
        echo -e "${C_YELLOW}Keine Backup-Archive (*.zip) im Verzeichnis 'backups' gefunden.${C_RESET}"
        return
    fi

    echo "Bitte wählen Sie ein Backup-Archiv zur Wiederherstellung aus:"
    select backup_file in "${backup_files[@]}" "Abbrechen"; do
        if [[ "$backup_file" == "Abbrechen" ]]; then
            echo -e "${C_YELLOW}Vorgang abgebrochen.${C_RESET}"
            break
        elif [[ -n "$backup_file" ]]; then
            echo -e "${C_RED}${C_BOLD}WARNUNG:${C_RESET} ${C_YELLOW}Diese Aktion überschreibt alle vorhandenen Dateien im Projektverzeichnis mit dem Inhalt von '$(basename "$backup_file")'.${C_RESET}"
            read -r -p "$(echo -e "Möchten Sie wirklich fortfahren? (${C_GREEN}j${C_RESET}/${C_RED}n${C_RESET}) ")" confirm
            if [[ "$confirm" == "j" || "$confirm" == "J" ]]; then
                echo -e "${C_CYAN}Erstelle zuerst ein automatisches Backup des aktuellen Zustands...${C_RESET}"
                do_backup
                echo -e "\n${C_CYAN}Stelle nun das ausgewählte Backup wieder her...${C_RESET}"
                # -o: overwrite, -d: destination directory
                if unzip -o "$backup_file" -d "$SCRIPT_DIR"; then
                    echo -e "\n${C_GREEN}Wiederherstellung erfolgreich abgeschlossen!${C_RESET}"
                else
                    echo -e "${C_RED}Fehler bei der Wiederherstellung.${C_RESET}"
                fi
            fi
            break
        fi
    done
}

do_update() {
    echo -e "${C_CYAN}Suche nach Updates für myrient-cli...${C_RESET}"

    local local_version_file="$SCRIPT_DIR/src/VERSION"
    local local_script_path="$SCRIPT_DIR/src/myrient-cli.sh"
    local temp_script_path="$local_script_path.tmp"
    
    local repo_url="https://raw.githubusercontent.com/elyps/myrient-cli/main"
    local remote_version_url="${repo_url}/src/VERSION"
    local remote_script_url="${repo_url}/src/myrient-cli.sh"

    # 1. Lokale Version holen
    if [ ! -f "$local_version_file" ]; then
        echo -e "${C_RED}Fehler: Lokale VERSION-Datei nicht gefunden. Update kann nicht durchgeführt werden.${C_RESET}"
        return
    fi
    local local_version
    local_version=$(grep '^VERSION=' "$local_version_file" | cut -d'=' -f2)

    # 2. Remote-Version holen
    local remote_version_content
    remote_version_content=$(curl -sL "$remote_version_url")
    if [ $? -ne 0 ]; then
        echo -e "${C_RED}Fehler: Konnte Update-Informationen nicht von GitHub abrufen. Bitte prüfen Sie Ihre Internetverbindung.${C_RESET}"
        return
    fi
    local remote_version
    remote_version=$(echo "$remote_version_content" | grep '^VERSION=' | cut -d'=' -f2)

    # 3. Versionen vergleichen
    if [[ "$local_version" == "$remote_version" ]]; then
        echo -e "${C_GREEN}Sie verwenden bereits die neueste Version ($local_version).${C_RESET}"
    else
        echo -e "${C_YELLOW}Eine neue Version (${C_GREEN}$remote_version${C_YELLOW}) ist verfügbar! (Ihre Version: ${C_RED}$local_version${C_YELLOW})${C_RESET}"
        read -r -p "$(echo -e "Möchten Sie das Skript jetzt aktualisieren? (${C_GREEN}j${C_RESET}/${C_RED}n${C_RESET}) ")" confirm
        if [[ "$confirm" == "j" || "$confirm" == "J" ]]; then
            echo -e "${C_CYAN}Lade neues Skript herunter...${C_RESET}"
            curl -sL "$remote_script_url" -o "$temp_script_path"
            curl -sL "$remote_version_url" -o "$local_version_file"
            chmod +x "$temp_script_path"
            mv "$temp_script_path" "$local_script_path"
            echo -e "${C_GREEN}Update erfolgreich auf Version ${remote_version} abgeschlossen!${C_RESET}"
        fi
    fi
}

do_status() {
    echo -e "${C_CYAN}Überprüfe den Status von myrient-cli...${C_RESET}"
    echo -e "${C_WHITE}--------------------------------------------------${C_RESET}"

    # 1. Version
    echo -e "${C_WHITE}${C_BOLD}Version:${C_RESET}"
    local version_file="$SCRIPT_DIR/src/VERSION"
    if [ -f "$version_file" ]; then
        local version
        version=$(grep '^VERSION=' "$version_file" | cut -d'=' -f2)
        echo -e "  - myrient-cli Version: ${C_GREEN}${version:-nicht gefunden}${C_RESET}"
    else
        echo -e "  - myrient-cli Version: ${C_RED}Unbekannt (VERSION-Datei nicht gefunden)${C_RESET}"
    fi
    echo

    # 2. Alias-Status
    echo -e "${C_WHITE}${C_BOLD}Alias-Status:${C_RESET}"
    if [ -f "$RC_FILE" ] && grep -q "alias $ALIAS_NAME=" "$RC_FILE"; then
        echo -e "  - Alias '${C_YELLOW}$ALIAS_NAME${C_RESET}' ist in ${C_GREEN}$RC_FILE${C_RESET} installiert."
    else
        echo -e "  - Alias '${C_YELLOW}$ALIAS_NAME${C_RESET}' ist ${C_RED}nicht installiert${C_RESET}."
    fi
    echo

    # 3. Datei-Status
    echo -e "${C_WHITE}${C_BOLD}Datei-Status:${C_RESET}"
    local config_file="$SCRIPT_DIR/config/.myrient_cli_rc"
    local history_file="$SCRIPT_DIR/logs/.download_history"
    local download_dir_path="$SCRIPT_DIR/downloads" # Standard

    if [ -f "$config_file" ]; then
        echo -e "  - Konfigurationsdatei: ${C_GREEN}Gefunden${C_RESET} (${C_WHITE}$config_file${C_RESET})"
        # Lese das Download-Verzeichnis aus der Konfiguration
        config_download_dir=$(grep '^DOWNLOAD_DIR=' "$config_file" | cut -d'=' -f2 | tr -d '"')
        eval expanded_dir="$config_download_dir" # Tilde-Expansion
        [ -n "$expanded_dir" ] && download_dir_path="$expanded_dir"
    else
        echo -e "  - Konfigurationsdatei: ${C_RED}Nicht gefunden${C_RESET} (${C_WHITE}$config_file${C_RESET})"
    fi

    [ -f "$history_file" ] && echo -e "  - Verlaufsdatei:       ${C_GREEN}Gefunden${C_RESET} (${C_WHITE}$history_file${C_RESET})" || echo -e "  - Verlaufsdatei:       ${C_RED}Nicht gefunden${C_RESET} (${C_WHITE}$history_file${C_RESET})"
    [ -d "$download_dir_path" ] && echo -e "  - Download-Verzeichnis: ${C_GREEN}Gefunden${C_RESET} (${C_WHITE}$download_dir_path${C_RESET})" || echo -e "  - Download-Verzeichnis: ${C_RED}Nicht gefunden${C_RESET} (${C_WHITE}$download_dir_path${C_RESET})"

    echo -e "${C_WHITE}--------------------------------------------------${C_RESET}"
}

# --- Hauptlogik ---

# 1. Erkennen der Shell und der RC-Datei
RC_FILE=""
if [[ "$SHELL" == *"zsh"* ]]; then
    RC_FILE="$HOME/.zshrc"
elif [[ "$SHELL" == *"bash"* ]]; then
    RC_FILE="$HOME/.bashrc"
else
    echo -e "${C_YELLOW}Warnung: Konnte die Shell nicht eindeutig als bash oder zsh identifizieren.${C_RESET}"
    echo -e "Versuche es mit ${C_YELLOW}$HOME/.bashrc${C_RESET}. Sie müssen den Alias möglicherweise manuell anpassen."
    RC_FILE="$HOME/.bashrc"
fi

# 2. Ausführen der angeforderten Aktion
case "$1" in
    install)
        do_install
        ;;
    uninstall)
        do_uninstall
        ;;
    clean)
        do_clean
        ;;
    status)
        do_status
        ;;
    update)
        do_update
        ;;
    backup)
        do_backup
        ;;
    restore)
        do_restore
        ;;
    *)
        echo -e "Verwendung: ${C_YELLOW}./manage.sh [install|uninstall|clean|status|update|backup|restore]${C_RESET}"
        echo -e "  ${C_GREEN}install${C_RESET}    - Fügt den 'myrient' Alias zu Ihrer Shell-Konfiguration hinzu."
        echo -e "  ${C_RED}uninstall${C_RESET}  - Entfernt den 'myrient' Alias aus Ihrer Shell-Konfiguration."
        echo -e "  ${C_CYAN}clean${C_RESET}      - Löscht die Konfigurations- und Verlaufsdateien."
        echo -e "  ${C_WHITE}status${C_RESET}     - Zeigt den aktuellen Installationsstatus an."
        echo -e "  ${C_YELLOW}update${C_RESET}     - Sucht nach einer neuen Version und aktualisiert das Skript."
        echo -e "  ${C_BLUE}backup${C_RESET}     - Erstellt ein ZIP-Archiv des gesamten Projektverzeichnisses."
        echo -e "  ${C_PURPLE}restore${C_RESET}    - Stellt das Projekt aus einem Backup-Archiv wieder her."
        exit 1
        ;;
esac