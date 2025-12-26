# Myrient-CLI (unofficial)

<div align="center">

```
                          _____            _____             __________ 
_______ ________  ___________(_)_____________  /_      _________  /__(_)
__  __ `__ \_  / / /_  ___/_  /_  _ \_  __ \  __/_______  ___/_  /__  / 
_  / / / / /  /_/ /_  /   _  / /  __/  / / / /_ _/_____/ /__ _  / _  /  
/_/ /_/ /_/_\__, / /_/    /_/  \___//_/ /_/\__/        \___/ /_/  /_/   
           /____/                                                       
```

**Ein Kommandozeilen-Tool zum Durchsuchen und Herunterladen von Inhalten aus dem Myrient-Archiv.**


[![Lizenz: MIT](https://img.shields.io/badge/Lizenz-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell-Skript](https://img.shields.io/badge/Shell-Bash-blue)](https://www.gnu.org/software/bash/)
[![Version](https://img.shields.io/badge/Version-1.0.0-green.svg)](https://github.com/elyps/myrient-cli)

</div>

---

## 🌟 Überblick

`myrient-cli` ist ein leistungsstarkes und benutzerfreundliches Bash-Skript, das eine interaktive Kommandozeilenschnittstelle (CLI) für das Durchsuchen und Herunterladen von Spiele-Archiven von Myrient bietet. Es wurde entwickelt, um den Prozess zu vereinfachen, die gewünschten Dateien zu finden und effizient herunterzuladen.

## ✨ Features

- **Interaktives Menü**: Eine einfach zu bedienende Menüführung zur Auswahl von Konsolen und zur Durchführung von Aktionen.
- **Suchen & Herunterladen**: Suchen Sie nach Spielen innerhalb einer ausgewählten Konsole und laden Sie einzelne oder mehrere Dateien gleichzeitig herunter.
- **Hintergrund-Downloads**: Führen Sie Downloads im Hintergrund aus, um die Konsole weiter nutzen zu können, und überwachen Sie deren Fortschritt.
- **Automatische Verifizierung**: Überprüft automatisch die Integrität heruntergeladener Dateien mithilfe von MD5- oder SHA1-Prüfsummen, falls verfügbar.
- **Automatisches Entpacken**: Entpackt `.zip`- und `.7z`-Archive nach einem erfolgreichen Download automatisch.
- **Konfigurationsmanagement**: Speichert Ihre Einstellungen (Download-Verzeichnis, etc.) in einer Konfigurationsdatei. Bietet Optionen zum Sichern, Wiederherstellen und Zurücksetzen.
- **Abhängigkeitsprüfung**: Überprüft beim Start, ob alle erforderlichen Tools installiert sind, und bietet an, diese zu installieren.
- **Self-Update**: Das Skript kann sich selbst auf die neueste Version von GitHub aktualisieren.

## 📋 Anforderungen

Das Skript ist für Linux- und macOS-Systeme konzipiert. Die folgenden Befehlszeilen-Tools werden benötigt:

- `bash` (Version 4.0 oder neuer empfohlen)
- `wget`
- `curl`
- `md5sum` (oder `md5` auf macOS)
- `sha1sum` (oder `shasum` auf macOS)
- `bc`
- `unzip`
- `7z` (vom `p7zip`-Paket)

Das Skript versucht, fehlende Abhängigkeiten mithilfe des erkannten Paketmanagers (APT, Pacman, DNF, Yum, Homebrew) zu installieren.

## 🚀 Installation

1.  **Klonen Sie das Repository:**
    ```sh
    git clone https://github.com/elyps/myrient-cli.git
    cd myrient-cli
    ```
    *Alternativ können Sie das Skript `myrient-cli.sh` auch direkt herunterladen.*

2.  **Machen Sie das Skript ausführbar:**
    ```sh
    chmod +x myrient-cli.sh
    ```

## ⚙️ Verwendung

1.  **Starten Sie das Skript:**
    ```sh
    ./myrient-cli.sh
    ```

2.  **Ersteinrichtung:**
    Beim ersten Start führt Sie das Skript durch eine kurze Ersteinrichtung, bei der Sie das Download-Verzeichnis und andere grundlegende Einstellungen festlegen.

3.  **Hauptmenü:**
    Nach dem Start wird das Hauptmenü angezeigt. Von hier aus können Sie:
    - Eine Konsole auswählen, um Spiele zu durchsuchen.
    - Ihre Konfiguration anpassen.
    - Laufende Downloads verwalten.
    - Nach Updates für das Skript suchen.
    - Und vieles mehr!

## 🔧 Konfiguration

Ihre Einstellungen werden in der Datei `.myrient_cli_rc` im selben Verzeichnis wie das Skript gespeichert. Sie können diese Datei direkt bearbeiten oder die Menüoptionen im Skript verwenden, um Ihre Konfiguration zu ändern.

Die wichtigsten Konfigurationsoptionen sind:

- `DOWNLOAD_DIR`: Das Verzeichnis, in dem Ihre Dateien gespeichert werden.
- `MAX_CONCURRENT_DOWNLOADS`: Die maximale Anzahl von Downloads, die gleichzeitig im Hintergrund laufen können.
- `AUTO_VERIFY`: `yes` oder `no`. Aktiviert die automatische Überprüfung von Prüfsummen.
- `AUTO_EXTRACT`: `yes` oder `no`. Aktiviert das automatische Entpacken von Archiven.
- `AUTO_UPDATE_CHECK`: `yes` oder `no`. Sucht beim Start automatisch nach Skript-Updates.

## 🤝 Mitwirken

Beiträge sind willkommen! Wenn Sie Vorschläge für neue Funktionen haben, einen Fehler gefunden haben oder den Code verbessern möchten, fühlen Sie sich frei, ein Issue zu erstellen oder einen Pull Request zu öffnen.

## 📜 Lizenz

Dieses Projekt steht unter der MIT-Lizenz.

---

## ⚖️ Haftungsausschluss

Dieses Projekt ist ein inoffizielles Community-Tool und steht in keiner Verbindung zu den Betreibern von Myrient.