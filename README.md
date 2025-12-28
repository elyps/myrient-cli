# Myrient CLI

                          _____            _____             __________ 
 _______ ________  ___________(_)_____________  /_      _________  /__(_)
 __  __ `__ \_  / / /_  ___/_  /_  _ \_  __ \  __/_______  ___/_  /__  /
 _  / / / / /  /_/ /_  /   _  / /  __/  / / / /_ _/_____/ /__ _  / _  /
 /_/ /_/ /_/_\__, / /_/    /_/  \___//_/ /_/\__/        \___/ /_/  /_/
            /____/

Ein Kommandozeilen-Tool zum Durchsuchen und Herunterladen von Inhalten aus dem Myrient-Archiv.

---

## Inhaltsverzeichnis

- Funktionen
- Projektstruktur
- Voraussetzungen
- Installation & Start
- Verwendung des Hauptskripts (`myrient-cli`)
  - Hauptmenü
  - Download-Prozess
  - Konfiguration
- Verwendung des Management-Skripts (`manage.sh`)
- Haftungsausschluss
- Lizenz

## Funktionen

- **Interaktives Menü**: Einfache Navigation durch Konsolen und Spiele.
- **Umfassende Suche**: Suchen Sie nach Spielen und filtern Sie die Ergebnisse nach Regionen oder schließen Sie Schlüsselwörter aus.
- **Download-Management**: Laden Sie einzelne oder mehrere Dateien gleichzeitig herunter, wahlweise im Vorder- oder Hintergrund.
- **Konfiguration**: Passen Sie Einstellungen wie das Download-Verzeichnis, gleichzeitige Downloads, Geschwindigkeitsbegrenzungen und mehr an.
- **Automatisierung**:
  - **Automatische Verifizierung**: Überprüft die Integrität heruntergeladener Dateien mittels Prüfsummen (MD5/SHA1).
  - **Automatisches Entpacken**: Entpackt `.zip`- und `.7z`-Archive nach dem Download.
  - **Automatisches Löschen**: Löscht Archive nach dem erfolgreichen Entpacken.
- **Verlauf**: Protokolliert alle Downloads und ermöglicht das Durchsuchen und Leeren des Verlaufs.
- **System-Integration**: Ein Management-Skript zur einfachen systemweiten Installation (Alias).
- **Self-Update**: Das Skript kann sich selbst auf die neueste Version von GitHub aktualisieren.
- **Backup & Restore**: Sichern und Wiederherstellen der Konfiguration oder des gesamten Projekts.

## Projektstruktur

Das Projekt ist in mehrere Verzeichnisse unterteilt, um eine klare Struktur zu gewährleisten:

```
myrient-cli/
├── backups/         # Speichert Backups der Konfiguration und des gesamten Projekts.
├── config/          # Enthält die zentrale Konfigurationsdatei (.myrient_cli_rc).
├── downloads/       # Standardverzeichnis für heruntergeladene Dateien.
├── logs/            # Enthält den Download-Verlauf und temporäre wget-Logs.
├── src/             # Enthält das Hauptskript (myrient-cli.sh) und die VERSION-Datei.
├── manage.sh        # Skript zur Verwaltung der Installation, Updates und Backups.
├── start.sh         # Startskript, das das Hauptskript aufruft.
└── README.md        # Diese Datei.
```

## Voraussetzungen

Stellen Sie sicher, dass die folgenden Kommandozeilen-Tools auf Ihrem System installiert sind. Das Skript wird versuchen, fehlende Abhängigkeiten zu installieren, wenn es auf einem unterstützten System (Debian, Arch, Fedora, macOS) ausgeführt wird.

- `wget`
- `curl`
- `md5sum` & `sha1sum`
- `bc`
- `unzip`
- `7z` (vom Paket `p7zip` oder `p7zip-full`)

## Installation & Start

1.  **Klonen Sie das Repository:**

    ```bash
    git clone https://github.com/elyps/myrient-cli.git
    cd myrient-cli
    ```

2.  **Führen Sie das Management-Skript aus, um einen Alias zu erstellen:**

    Dies erstellt den Befehl `myrient` in Ihrer Shell, sodass Sie das Skript von überall aus starten können.

    ```bash
    ./manage.sh install
    ```

    Öffnen Sie danach ein neues Terminal oder laden Sie Ihre Shell-Konfiguration neu (`source ~/.bashrc` oder `source ~/.zshrc`).

3.  **Starten Sie das Skript:**

    ```bash
    myrient
    ```

    Beim ersten Start werden Sie durch eine Ersteinrichtung geführt, um die wichtigsten Einstellungen vorzunehmen.

## Verwendung des Hauptskripts (`myrient-cli`)

Nach dem Start mit `myrient` gelangen Sie in das Hauptmenü.

### Hauptmenü

Das Hauptmenü bietet Zugriff auf alle Funktionen des Skripts:

- **Konsole auswählen**: Startet den Browser- und Download-Vorgang.
- **Konfigurationseinstellungen**: Passen Sie alle Aspekte des Skripts an (siehe Konfiguration).
- **Download-Verwaltung**: Zeigen Sie laufende Downloads an, brechen Sie sie ab oder sehen Sie sich den Verlauf an.
- **Wartung**: Suchen Sie nach Updates, verwalten Sie Backups oder bereinigen Sie Protokolldateien.

### Download-Prozess

1.  Wählen Sie im Hauptmenü `Konsole auswählen`.
2.  Wählen Sie die gewünschte Konsole aus der Liste.
3.  Geben Sie einen Suchbegriff für das Spiel ein, das Sie finden möchten.
4.  Die Ergebnisse werden gefiltert nach Ihren Voreinstellungen (Regionen, ausgeschlossene Schlüsselwörter) angezeigt. Bereits heruntergeladene Spiele sind mit `[✔]` markiert.
5.  Geben Sie die Nummern der gewünschten Spiele ein (z.B. `1 3 5` oder `all` für alle).
6.  Wählen Sie, ob die Downloads im Vorder- oder Hintergrund ausgeführt werden sollen.

### Konfiguration

Alle Einstellungen werden in der Datei `config/.myrient_cli_rc` gespeichert. Sie können diese entweder direkt bearbeiten oder die Menüpunkte im Hauptskript verwenden.

Wichtige Optionen sind:

- **Download-Verzeichnis**: Wo Ihre Dateien gespeichert werden.
- **Gleichzeitige Downloads**: Wie viele Dateien parallel heruntergeladen werden dürfen.
- **Geschwindigkeitslimit**: Begrenzen Sie die Download-Bandbreite (z.B. `2m` für 2 MB/s).
- **Filter**: Legen Sie bevorzugte Regionen fest oder schließen Sie Begriffe wie `Beta` oder `Demo` aus.
- **Automatisierung**: Aktivieren/Deaktivieren Sie die automatische Verifizierung, das Entpacken und das Löschen von Archiven.

## Verwendung des Management-Skripts (`manage.sh`)

Das `manage.sh`-Skript dient zur Verwaltung der Skript-Installation und zur Durchführung von Wartungsaufgaben von außerhalb des Hauptskripts.

**Verwendung:** `./manage.sh [befehl]`

| Befehl | Beschreibung | Beispiel |
| :--- | :--- | :--- |
| `install` | Fügt den `myrient`-Alias zu Ihrer Shell-Konfiguration hinzu. | `./manage.sh install` |
| `uninstall` | Entfernt den `myrient`-Alias. | `./manage.sh uninstall` |
| `status` | Zeigt die installierte Version, den Alias-Status und das Vorhandensein von Konfigurationsdateien an. | `./manage.sh status` |
| `update` | Sucht nach einer neuen Version auf GitHub und führt ein Update durch. | `./manage.sh update` |
| `clean` | Löscht Konfigurations-, Verlaufs-, Download- und Backup-Dateien (fragt vor jeder Aktion nach). | `./manage.sh clean` |
| `backup` | Erstellt ein `.zip`-Backup des gesamten Projektverzeichnisses (außer dem `backups`-Ordner selbst). | `./manage.sh backup` |
| `restore` | Stellt das Projekt aus einem zuvor erstellten `.zip`-Backup wieder her. | `./manage.sh restore` |

## Haftungsausschluss

1.  **Keine Zugehörigkeit**: Der Entwickler dieses Skripts steht in keinerlei Verbindung zu den Betreibern von Myrient. Das Skript ist ein unabhängiges Projekt.
2.  **Rechtliche Verantwortung**: Sie als Nutzer sind allein für die Einhaltung der geltenden Gesetze in Ihrem Land verantwortlich. Das Herunterladen von urheberrechtlich geschütztem Material kann illegal sein.
3.  **Distanzierung von illegalen Aktivitäten**: Der Entwickler distanziert sich ausdrücklich von jeglicher Form illegaler Downloads. Das Skript ist nicht für rechtswidrige Zwecke bestimmt.
4.  **Nutzung auf eigene Gefahr**: Die Nutzung des Skripts erfolgt auf Ihr eigenes Risiko. Es wird keine Garantie für Funktionalität oder Sicherheit übernommen.

Indem Sie das Skript verwenden, bestätigen Sie, diesen Haftungsausschluss gelesen zu haben und das Skript ausschließlich für legale Zwecke zu verwenden.

## Lizenz

Dieses Projekt steht unter der MIT-Lizenz.

---

## Beispiele

### Ein Spiel herunterladen

1.  Starten Sie das Skript:
    ```bash
    myrient
    ```
2.  Wählen Sie `1` (Konsole auswählen).
3.  Wählen Sie z.B. `Sony - PlayStation 2`.
4.  Geben Sie als Suchbegriff `Metal Gear Solid` ein.
5.  Wählen Sie aus den Ergebnissen die Nummer für `Metal Gear Solid 3 - Snake Eater (Europe) (En,Fr,De,Es,It)`.
6.  Bestätigen Sie den Download.

### Den Installationsstatus prüfen

```bash
./manage.sh status
```

**Ausgabe:**
```
Überprüfe den Status von myrient-cli...
--------------------------------------------------
Version:
  - myrient-cli Version: 1.0.0

Alias-Status:
  - Alias 'myrient' ist in /home/user/.bashrc installiert.

Datei-Status:
  - Konfigurationsdatei: Gefunden (/path/to/myrient-cli/config/.myrient_cli_rc)
  - Verlaufsdatei:       Gefunden (/path/to/myrient-cli/logs/.download_history)
  - Download-Verzeichnis: Gefunden (/path/to/myrient-cli/downloads)
--------------------------------------------------
```

### Das Skript aktualisieren

```bash
./manage.sh update
```

**Ausgabe bei einem verfügbaren Update:**
```
Suche nach Updates für myrient-cli...
Eine neue Version (1.1.0) ist verfügbar! (Ihre Version: 1.0.0)
Möchten Sie das Skript jetzt aktualisieren? (j/n) j
Lade neues Skript herunter...
Update erfolgreich auf Version 1.1.0 abgeschlossen!
```

### Ein vollständiges Backup erstellen

```bash
./manage.sh backup
```

**Ausgabe:**
```
Erstelle ein Backup des gesamten Projektverzeichnisses...
Das Backup wird als 'myrient-cli-backup-2025-12-27_18-30-00.zip' im Verzeichnis 'backups' gespeichert.
Backup erfolgreich erstellt!
```