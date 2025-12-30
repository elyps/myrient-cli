# Myrient CLI (Unofficial)

```text
                           _____            _____             __________ 
 _______ ________  ___________(_)_____________  /_      _________  /__(_)
 __  __ `__ \_  / / /_  ___/_  /_  _ \_  __ \  __/_______  ___/_  /__  /
 _  / / / / /  /_/ /_  /   _  / /  __/  / / / /_ _/_____/ /__ _  / _  /
 /_/ /_/ /_/_\__, / /_/    /_/  \___//_/ /_/\__/        \___/ /_/  /_/
            /____/
```

![Version](https://img.shields.io/badge/version-1.0.0-blue.svg?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-green.svg?style=flat-square)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-lightgrey.svg?style=flat-square)
![Bash](https://img.shields.io/badge/language-Bash-4EAA25.svg?style=flat-square&logo=gnu-bash&logoColor=white)

> **Ein leistungsstarkes Kommandozeilen-Tool zum Durchsuchen und Herunterladen von Inhalten aus dem Myrient-Archiv.**

---

## 📖 Über das Projekt

**Myrient CLI** ist ein nicht-offizielles, benutzerfreundliches Terminal-Tool, das den Zugriff auf das umfangreiche Myrient-Archiv erleichtert. Es bietet eine intuitive Oberfläche, um nach Spielen zu suchen, Downloads zu verwalten und Ihre Sammlung zu organisieren – alles bequem von der Kommandozeile aus.

### ✨ Hauptfunktionen

*   **🖥️ Interaktive UI**: Moderne, menügesteuerte Navigation dank [Gum](https://github.com/charmbracelet/gum).
*   **🔍 Intelligente Suche**: Suchen Sie nach Spielen, filtern Sie nach Regionen und schließen Sie unerwünschte Ergebnisse (z.B. "Demo", "Beta") aus.
*   **🚀 Download-Manager**: Parallele Downloads im Hintergrund oder interaktiv im Vordergrund.
*   **⚙️ Vollständig Konfigurierbar**: Passen Sie Pfade, Limits, automatische Entpack-Regeln und mehr an.
*   **🛡️ Sicherheit & Integrität**: Automatische Überprüfung von MD5/SHA1-Prüfsummen.
*   **📦 Automatisierung**: Automatisches Entpacken (.zip, .7z) und Bereinigen von Archiven.

---

## 🛠️ Voraussetzungen

Das Skript benötigt einige Standard-Tools sowie **Gum** für die Benutzeroberfläche.

Myrient CLI prüft beim Start auf fehlende Abhängigkeiten und bietet bei den meisten (inklusive `gum`) eine automatische Installation an.

*   **[Gum](https://github.com/charmbracelet/gum)** (Essenziell für das UI)
*   `wget` & `curl` (Download & Netzwerk)
*   `md5sum` & `sha1sum` (Integrität)
*   `bc` (Berechnungen)
*   `unzip` & `7z` (Paket `p7zip` oder `p7zip-full` für Archiv-Management)

---

## 🚀 Installation & Start

### 1. Repository klonen

```bash
git clone https://github.com/elyps/myrient-cli.git
cd myrient-cli
```

### 2. Einrichtung (Optional aber empfohlen)

Nutzen Sie das `manage.sh` Skript, um einen systemweiten Alias (`myrient`) zu erstellen:

```bash
./manage.sh install
```
*Starten Sie danach Ihr Terminal neu oder laden Sie die Config (`source ~/.bashrc` / `source ~/.zshrc`).*

### 3. Starten

Wenn Sie den Alias installiert haben:
```bash
myrient
```

Andernfalls direkt über das Skript:
```bash
./start.sh
```

---

## 🎮 Verwendung

Nach dem Start werden Sie durch ein interaktives Menü geführt.

1.  **Konsole auswählen**: Wählen Sie das gewünschte System (z.B. "Sony - PlayStation 2").
2.  **Suchen**: Geben Sie einen Suchbegriff ein (z.B. "Metal Gear").
3.  **Auswählen**: Markieren Sie die gewünschten Titel mit `Leertaste` und bestätigen Sie mit `Enter`.
4.  **Download**: Wählen Sie zwischen Vordergrund- oder Hintergrund-Download.

### Management-Skript (`manage.sh`)

Das Hilfsskript für Wartungsaufgaben:

| Befehl | Beschreibung |
| :--- | :--- |
| `./manage.sh update` | Prüft auf Updates und aktualisiert das Skript. |
| `./manage.sh backup` | Erstellt ein vollständiges Backup des Projektordners. |
| `./manage.sh clean` | Bereinigt Logs, Cache und temporäre Dateien. |
| `./manage.sh status` | Zeigt Installationsstatus und Pfade an. |

---

## 📂 Projektstruktur

```text
myrient-cli/
├── config/          # Konfiguration (.myrient_cli_rc)
├── downloads/       # Standard-Downloadverzeichnis
├── logs/            # Logs und Download-Historie
├── src/             # Quellcode
├── backups/         # Erstellte Backups
├── manage.sh        # Verwaltungstool
└── start.sh         # Startskript
```

---

## ⚠️ Haftungsausschluss

Dieses Projekt ist eine unabhängige Entwicklung und steht in **keiner Verbindung** zu Myrient oder Erista.

*   Die Nutzung erfolgt auf eigene Gefahr.
*   Der Nutzer ist für die Einhaltung lokaler Urheberrechtsgesetze verantwortlich.
*   Das Tool ist nur für legale Zwecke und Sicherungskopien eigener Originale gedacht.

---

## 📄 Lizenz

Lizenziert unter der **MIT Lizenz**.
Konzept und Umsetzung basieren auf Open-Source-Tools.

---

<p align="center">
  <sub>Erstellt mit ❤️ für die Retro-Gaming-Community.</sub>
</p>