#!/bin/bash

# ==============================================================================
#
# myrient.sh - Launcher
#
# Description:   This script acts as a simple launcher for the main
#                myrient-cli.sh script located in the /src directory.
#
# ==============================================================================

# Ermittle das Verzeichnis, in dem sich dieses Startskript befindet (das Projekt-Stammverzeichnis)
LAUNCHER_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# Der Pfad zum eigentlichen Hauptskript
MAIN_SCRIPT="$LAUNCHER_DIR/src/myrient-cli.sh"

# Prüfe, ob das Hauptskript existiert, bevor es ausgeführt wird
if [ ! -f "$MAIN_SCRIPT" ]; then
    echo "Fehler: Das Hauptskript konnte nicht unter dem erwarteten Pfad gefunden werden:" >&2
    echo "$MAIN_SCRIPT" >&2
    echo "Bitte stellen Sie sicher, dass die Projektstruktur korrekt ist." >&2
    exit 1
fi

# Führe das Hauptskript aus und übergebe alle Argumente, die an dieses Skript übergeben wurden
exec bash "$MAIN_SCRIPT" "$@"