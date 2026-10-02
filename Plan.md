# SmartClip – Plan und Abnahmekriterien für Version 1

Basis: der im Chat freigegebene Plan. Stand: 02.10.2026.
Die konkrete Testabdeckung und verbleibende Grenzen stehen in [docs/TESTBERICHT.md](docs/TESTBERICHT.md).

## Plattform und Bedienung

- Lokale Menüleisten-App, macOS 14+, Swift/AppKit/SwiftUI; kein Konto, Server oder Sync.
- Globales frei wählbares Kürzel; ⌘⇧V nur nach aktiver Auswahl.
- Kompakte Liste und Karten, System-Hell-/Dunkelmodus, Suche und Typfilter.
- Favoriten oben, Kopieren und Löschen, HTTP(S)-URLs öffnen.
- Ergänzung: Codefilter mit lokaler heuristischer Spracherkennung, Sprachkennzeichnung, Sprachsuche und formatgetreuem Kopieren.
- Standard: nur kopieren. Optional in vorherige App einfügen, abhängig von Bedienungshilfen-Freigabe.
- Autostart über SMAppService, pausierbare Aufzeichnung, ausgeschlossene Apps.
- Ergänzung aus dem Feedback: verschiebbares/veränderbares Fenster mit Schließen/Minimieren, Escape und ⌘W; Kürzel blendet ein/aus und stellt minimiertes Fenster wieder her.
- Ergänzung aus dem Feedback: Enter während einer Suche bestätigt nur die Suche. Nach Auswahl mit einer Pfeiltaste übernimmt Enter den Treffer; Klick auf einen Treffer übernimmt ihn ebenfalls.

## Erfassung und Speicherung

- Neue NSPasteboard.changeCount-Werte erfassen; Texte, URLs, E-Mail, Bilder und mehrere Dateireferenzen.
- Geschätzte Quell-App und Zeitstempel; keine Browser-Tabs auslesen. Herkunftsseiten nur mit tatsächlich vorhandenen passenden Metadaten. Eine Auswertung solcher Herkunftsseiten-Metadaten ist noch nicht implementiert.
- Dateien bleiben Referenzen, fehlende Originale anzeigen und nicht erneut kopieren.
- Bilder über 20 MiB ablehnen und Grund anzeigen; beschädigte Bilder nicht speichern.
- SQLite, AES-GCM pro Inhalt einschließlich Bilddaten/Dateipfaden; Schlüssel im lokalen Schlüsselbund.
- Gleichartige identische Inhalte deduplizieren, Datum/Quelle/Zähler aktualisieren, Pin erhalten. Sensibilität bei Wiedererfassung nicht automatisch herabstufen.
- Normale Aufbewahrung 7/30/90/365 Tage oder niemals, ab letztem Kopieren; Standard 30 Tage, Favoriten ausgenommen.

## Sensible Inhalte

- Bekannte Clipboard-Vertraulichkeitsmarker berücksichtigen; Kreditkartennummern anhand Luhn prüfen.
- Keine Behauptung einer zuverlässigen Erkennung beliebiger unmarkierter Passwörter.
- Sensible Vorschauen maskieren, keine Volltextsuche in Geheimnissen.
- Sensible Fristen 5 Minuten/1 Stunde/24 Stunden, Standard 1 Stunde, auch für Favoriten.
- Manuelle Herabstufung nur nach UI-Bestätigung. Erneutes Kopieren schreibt den Originalwert in die Zwischenablage und erhält eine Vertraulichkeitsmarkierung.
- Frist entfernt SmartClip-Eintrag, nicht die macOS-Zwischenablage. Abgelaufene Einträge auch zwischen zwei Bereinigungsintervallen nicht wiederbeleben.

## Prüfung und Ausbaustufen

- Automatisierte Tests: Typen, Sensibilität, Verschlüsselung, Datenbank, Duplikate, Suche, Fristen, Dateien, Erfassung, Einstellungen, Kopierpfad, Kürzelkonflikte und Startfehler.
- Isolierte Test-App für UI-Abnahme; separate Checkliste für echte Systemfreigaben, andere Apps, Autostart und Ressourcenmessung.
- JSON/Farb/IP-Spezialaktionen, Statistik und Synchronisierung sind nicht Bestandteil von Version 1.
- Private Nutzung; Developer-ID-Signierung, Notarisierung, Installer und GitHub-Release folgen später. Keine Veröffentlichung jetzt.
