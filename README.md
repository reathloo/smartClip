# SmartClip

<img src="Resources/AppIcon.png" alt="SmartClip App-Icon" width="128">

Lokaler Zwischenablage-Verlauf für macOS 14 und neuer. SmartClip läuft als Menüleisten-App und speichert Text, URLs, E-Mail-Adressen, Bilder sowie Verweise auf kopierte Dateien. Inhalte und Dateipfade werden verschlüsselt; der Schlüssel liegt im macOS-Schlüsselbund.

## Funktionen

- Durchsuchbarer Verlauf mit Typfiltern, Code- und Spracherkennung.
- Favoriten, Listen- und Kartenansicht, Hell- und Dunkelmodus.
- Frei wählbares globales Tastenkürzel, pausierbare Erfassung und App-Ausschlüsse.
- Verschlüsselte lokale Speicherung und einstellbare Löschfristen.
- Maskierung sensibler Inhalte anhand bekannter Vertraulichkeitsmarker und Kreditkarten-Prüfziffern; keine universelle Passworterkennung.
- Menüleistenbetrieb, optionaler Autostart und optionales direktes Einfügen.

## Voraussetzungen

macOS 14 oder neuer und eine Swift-Toolchain, die den Quellcode unterstützt. Lokal geprüft wurde der Build mit den installierten Command Line Tools und dem macOS-26.5-SDK. Für XCTest wird vollständiges Xcode benötigt. Es gibt keine externen Swift-Paketabhängigkeiten; verwendet werden Apple-Frameworks und das mitgelieferte SQLite.

## Lokal starten

```sh
zsh scripts/build-app.sh
open dist/SmartClip.app
```

Beim ersten Start öffnet sich die Einrichtung. Dort kannst du `⌘⇧V` übernehmen oder ein anderes Kürzel aufnehmen und anschließend die Aufzeichnung starten. Das Kürzel wird nicht automatisch belegt. Automatisches Einfügen ist optional und benötigt die Bedienungshilfen-Freigabe. Bei neueren macOS-Versionen kann zusätzlich eine Freigabe für das Lesen der Zwischenablage erscheinen.

Die Datenbank liegt unter `~/Library/Application Support/SmartClip/`. Dateieinträge enthalten Verweise auf die Originaldateien; verschobene oder gelöschte Dateien lassen sich nicht mehr aus dem Verlauf kopieren. Bilder über 20 MB werden übersprungen. Die angezeigte Quell-App ist eine Schätzung zum Zeitpunkt der Erfassung. SmartClip ermittelt keine Browser-Tab-URL und kann sehr schnelle Kopierfolgen zwischen zwei Abfragen der Zwischenablage verpassen.

## Entwicklung und Prüfung

```sh
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift build
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift run SmartClip --self-test
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift run SmartClip --render-design
```

`--render-design` erstellt Vorschauen der echten SwiftUI-Ansichten in `.build/design-previews/`, mit Beispieldaten für Hell- und Dunkelmodus. Dabei startet keine Clipboard-Aufzeichnung.

Die `SDKROOT`-Angabe ist ein Workaround für die hier installierten Command Line Tools. Mit vollständigem Xcode kann `swift test` zusätzlich die XCTest-Suite ausführen. Die lokale App ist nicht für die Verteilung signiert oder notarisiert. Ein GitHub-Release ist ein späterer Schritt.

## Projektstruktur

| Pfad | Inhalt |
| --- | --- |
| `Sources/SmartClip/` | App, Oberfläche, Erfassung, Speicherung und Test-Runner |
| `Sources/CSQLite/` | Anbindung an das systemeigene SQLite |
| `Tests/SmartClipTests/` | XCTest-Anbindung der gemeinsamen Testsuite |
| `Resources/` | App-Icon und Bundle-Konfiguration |
| `scripts/` | App-, Icon- und Test-Builds |
| `docs/TESTBERICHT.md` | Testabdeckung und offene Systemprüfungen |
| `Plan.md` | Funktionsumfang und Abnahmekriterien |

Build-Ausgaben, lokale Einstellungen, Signierschlüssel und Datenbankdateien sind über `.gitignore` ausgeschlossen. Das App-Icon ist fertig als `.icns` enthalten; nach Änderungen am Originalbild lässt es sich mit `zsh scripts/build-icon.sh` neu erzeugen.

## Vollständige Funktionsprüfung

```sh
zsh scripts/test.sh
```

Die 96 automatisierten Prüffälle verwenden isolierte Daten, Einstellungen und eine private Zwischenablage. Ergebnisse: `.build/test-results/core.json` und `core.log`. Planabgleich, behobene Fehler und noch ausstehende Systemtests: [Testbericht](docs/TESTBERICHT.md), [Plan](Plan.md).

Für manuelle Bedienungstests ohne echte Verlaufsdaten:

```sh
zsh scripts/build-ui-test-app.sh
open '.build/SmartClip Test.app'
```

Diese separate Test-App verwendet Beispieldaten; Autostart, automatisches Einfügen und Browseröffnung sind darin deaktiviert. Sie benötigt keinen Schlüsselbundzugriff.

Bei einer Suche bestätigt Enter den Suchbegriff und lässt das Fenster offen. Mit ↓ einen Treffer auswählen und anschließend Enter drücken, um ihn zu übernehmen. Ein direkter Klick übernimmt ihn ebenfalls. Escape oder ⌘W blendet den Verlauf aus.

## Code erkennen

Der Filter **Code** zeigt erkannte Codeausschnitte mit automatisch geschätzter Sprache und einer Monospace-Vorschau. Die Erkennung läuft vollständig lokal: Python, JavaScript, TypeScript, Swift, Shell, JSON, HTML, CSS, SQL, Go, Rust, Java, C, C++, C# und PHP. Sprachangaben in Markdown-Codeblöcken werden berücksichtigt. Mehrdeutiger Code erhält „Sprache unklar“; kurze Ausschnitte ohne charakteristische Syntax können normaler Text bleiben. Suche nach einer Sprache (z. B. `Python`) ist ebenfalls möglich.

Bestehende Texteinträge werden beim Lesen mit erkannt. Erneutes Kopieren erzeugt dabei keine zusätzlichen Duplikate. Formatierung und Inhalt bleiben beim Zurückkopieren unverändert; Code wird nicht ausgeführt. Sensible Einträge bleiben maskiert.
