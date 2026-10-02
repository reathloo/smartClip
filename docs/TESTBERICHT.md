# SmartClip – Testbericht und reproduzierbare Prüfung

Stand: 02.10.2026. Grundlage: [Plan.md](../Plan.md).

## Ergebnis

Der abschließende automatisierte Lauf wird über `zsh scripts/test.sh` ausgeführt. Die Suite umfasst **96 benannte Prüffälle** mit mehreren Einzelassertionen. Ergebnisse sind maschinenlesbar in `.build/test-results/core.json`, Konsolenausgabe in `.build/test-results/core.log`.

Der erste Lauf mit 54 Fällen hatte fünf reproduzierte Fehler (49 bestanden). Nach den Korrekturen und Ergänzung weiterer Integrationsprüfungen bestanden 64/64. UI-Prüfungen sind separat und zählen nicht zu diesen automatisierten Fällen.

Die Tests verwenden zufällige temporäre Datenbanken, eigene UserDefaults-Suites, eigene benannte Pasteboards und erzeugte Schlüssel. Sie lesen keine echten Verlaufsinhalte und rufen den echten Schlüsselbund nicht auf. Der Kürzeltest registriert vorübergehend ⌃⌥⇧⌘F18/F19 und gibt beide Kombinationen anschließend frei. Sind diese bereits extern belegt, schlägt der Test mit einer entsprechenden Meldung fehl.

## Behobene Fehler

1. Nullfolgen wurden allein wegen einer passenden Luhn-Summe als Kreditkartennummer erkannt; nun ausgeschlossen.
2. URLs ohne zusätzliche Text-Repräsentation wurden ignoriert; `public.url` wird nun berücksichtigt.
3. Beschädigte Bilddaten wurden als Bild gespeichert; nun mit erklärtem Grund übersprungen.
4. Eine unmarkierte Wiederholung konnte einen sensiblen Eintrag unmaskieren; automatische Erfassung stuft nicht mehr herab. Manuelles Umstufen bleibt möglich.
5. Ein bereits abgelaufener sensibler Eintrag konnte vor dem nächsten Timer-Tick erneut kopiert und verlängert werden; Ablauf wird nun direkt beim Abruf geprüft.
6. Schlüsselbund-Wartezeiten blockierten die Hauptschleife; Schlüsselabruf läuft nun abseits des UI-Threads. Wartender Abruf, Fehler und Wiederöffnung sind mit kontrollierten Schlüssel-Ladern getestet. Die echte macOS-Freigabe ist damit nicht getestet.
7. Nach Anheften konnten Zeilen einen veralteten Knopfzustand behalten. Zeilenaktionen und Beschriftungen lesen nun den aktuellen Modelleinstieg. Anheften und anschließendes Lösen wurden direkt in der Test-App geprüft.
8. Enter während der Suche übernahm sofort den ersten Treffer. Jetzt bestätigt Enter die Suche; erst eine ausdrückliche Auswahl per Pfeiltaste aktiviert das Übernehmen per Enter. Direkt in der Test-App geprüft.

Zusätzlich: sensible Inhalte erhalten beim Zurückkopieren einen ConcealedType-Marker; Hotkey-Handler und Timer werden beim Freigeben ihrer Besitzer aufgeräumt. Beide Einstellungsfenster verwenden dasselbe Modell.

## Automatisierte Abdeckung

| Bereich | Nachweis | Grenze |
| --- | --- | --- |
| Text/URL/E-Mail | Positive und negative Typfälle, Unicode/NUL-Roundtrip, Clipboard-Repräsentationen | Keine semantische Prüfung, ob eine URL erreichbar ist |
| Passwortmanager/Kreditkarte | Concealed/Transient/1Password-Marker, gültige und ungültige Luhn-Nummern, Negativfälle | Beliebige unmarkierte Passwörter werden nicht zuverlässig erkannt |
| Bilder | PNG/TIFF lesen, zurückkopieren, gültiges Bild decodieren, >20-MiB-Ablehnung, defekte Daten | Keine Tests aller denkbaren Bildformate oder riesiger dekomprimierter Bilder |
| Dateien | Mehrere Originalreferenzen, fehlende Originale, Roundtrip, vorhandene Zwischenablage bei Fehler erhalten | Finder-End-to-End noch offen |
| Verschlüsselung | Leere/kleine/1-MiB-Daten, zufällige Nonces, falscher Schlüssel, Manipulation, abgeschnittene Daten | Kein unabhängiges Sicherheitsaudit |
| Speicherung | Alle Arten in SQLite, zweite Verbindung/Wiederöffnung, verschlüsselte Texte/Bilddaten/Pfade in DB und WAL, korrupter Datensatz | Technische Metadaten wie Typ, Datum und App-Name bleiben unverschlüsselt |
| Duplikate/Favoriten | Text/Bild/Dateigruppen, Zähler, Zeit/Quelle, Pin erhalten, Sensibilität erhalten, Anheften/Lösen | UI-Reihenfolge zusätzlich interaktiv geprüft |
| Suche/Filter | Inhalt und App-Name, Groß-/Kleinschreibung, Typfilter, Limit, Treffer hinter erster Seite | Sensible Inhalte absichtlich nicht im Klartext durchsuchbar |
| Löschfristen | Alle angebotenen Fristen an exakter Grenze, niemals, Favoriten, sensible Favoriten, Wiederholung, Einstellungswechsel, abgelaufener Abruf | Zeit wird kontrolliert vorgegeben; kein tagelanger Echtzeitlauf |
| Überwachung | Onboarding, Pause/Fortsetzen, changeCount, Ausschlüsse, verweigerter Zugriff, eigene Kopien nicht doppelt erfassen | Der OS-Zugriffsstatus wird simuliert; echte Freigabe separat prüfen |
| Einstellungen | Sichere Defaults, persistente Ansicht/Pause/Fristen/Ausschlüsse/Onboarding, leere Ausschlüsse | Autostart und Accessibility-Freigabe nicht automatisch verändert |
| Kopieren | Originaltext und maskiertes Geheimnis, URL/E-Mail/Bild/Datei, Concealed-Marker, Fehlererhalt, Schließ-Callback | Automatisches Einfügen in Fremdprogramme nicht im isolierten Lauf |
| Tastenkürzel | Native Registrierung, Konflikt, fehlgeschlagener Austausch erhält altes Kürzel, Entfernen/Freigeben, Callback | Globales physisches Tastenrouting separat prüfen |
| Fenster | Native Schließen-/Minimieren-Knöpfe aktiviert, verschiebbar/veränderbar, Mindestgröße, wiederverwendbares Panel | Sichtbarkeit/Drag/Minimieren/Wiederöffnen nicht durch diese Strukturassertionen bewiesen |
| Start | Schlüssel-Ladefehler, UI-Thread bleibt während Wartezeit verfügbar, vorhandenen Verlauf mit gleichem Schlüssel öffnen | Echte Keychain-ACL und macOS-Neustart offen |

## Direkte UI-Prüfung mit Beispieldaten

Geprüft in `.build/SmartClip Test.app`, Dark Mode:

- Suche nach `Testnotiz`: genau ein passender Treffer.
- Suche + Enter: Verlauf bleibt offen, Fußzeile zeigt „Suchen“.
- Danach ↓: Fußzeile wechselt auf „Kopieren“; Enter blendet den Verlauf aus und Status bestätigt Kopieren.
- Textfilter zeigt normale und maskierte sensible Texte.
- Listen-/Kartenumschaltung: Auswahlzustand und Darstellung wechseln.
- Anheften verschiebt den Treffer nach oben; nach Korrektur wechselt der Knopf zu „Lösen“, erneuter Klick löst ihn.
- Sensibler Inhalt ist auch in Accessibility-Beschriftung maskiert.
- „Als normal einstufen“ öffnet Bestätigungsdialog; nach Bestätigung wird nur der synthetische Testwert sichtbar.
- Einstellungen öffnen; empfohlenes Kürzel lässt sich in der Testinstanz registrieren.
- Escape im Suchfeld blendet das Verlaufsfenster aus.

Die Computersteuerung aktivierte nach dem Ausblenden teils das zusätzliche SwiftUI-Einstellungsfenster. Deshalb wird aus diesem Ablauf **kein vollständiger Nachweis für globales Wiederöffnen/Minimieren oder Fensterposition** abgeleitet. Diese Punkte bleiben in der manuellen Checkliste offen.

## Noch offene Systemabnahme

Diese Tests benötigen einen interaktiven Mac mit den jeweiligen Freigaben. Sie sind nicht als bestanden markiert:

- [ ] Echte Keychain-Freigabe akzeptieren; nach Beenden/Neustart denselben Verlauf öffnen. Keine Schlüssel neu erzeugen, wenn Zugriff verweigert wird.
- [ ] Browser, Terminal und Finder: neue Kopien erscheinen genau einmal; Quell-App plausibel und als Schätzung behandeln.
- [ ] Echte Bildkopie und mehrere Finder-Dateien, Originaldatei verschieben/löschen; fehlende Datei korrekt melden.
- [ ] System-Zwischenablagezugriff verweigern und erneut erlauben: Zustand erklären, keine unerlaubte Erfassung.
- [ ] Kürzel aus einer anderen App: öffnen, erneut ausblenden, Konfliktmeldung; eigenes Kürzel aufnehmen und Escape beim Aufnehmen.
- [ ] Fenster ziehen und skalieren; schließen mit rotem Knopf/⌘W/Escape; gelber Knopf minimiert; Kürzel stellt wieder her; Position bleibt in derselben Sitzung erhalten.
- [ ] „Nur kopieren“ lässt Ziel-App unverändert. Mit erteilter Bedienungshilfen-Freigabe fügt die Option genau einmal in der vorherigen App ein. Ohne Freigabe bleibt kopierter Inhalt verfügbar.
- [ ] URL-Aktion öffnet einen synthetischen HTTP(S)-Testlink im Standardbrowser.
- [ ] Autostart aktivieren, ab-/anmelden, genau eine Menüleisteninstanz; wieder deaktivieren und erneut prüfen.
- [ ] Im Leerlauf CPU/RAM mit echter laufender Überwachung messen; anschließend längeren Verlauf und mehrere große Bilder testen.
- [ ] macOS 14 als Mindestversion auf einem entsprechenden System ausführen.

## Bekannte Plan-Grenzen

- Herkunftsseiten-Metadaten von Browsern werden derzeit nicht ausgewertet. Es wird die geschätzte App und gegebenenfalls die kopierte URL selbst angezeigt. Keine Browser-Tab-Abfrage.
- JSON/Farb/IP-Aktionen, Statistik, Synchronisierung, Signierung/Notarisierung und Veröffentlichung sind laut Plan spätere Ausbaustufen.
- Die Frist löscht SmartClip-Einträge, nicht bereits kopierten Klartext in der systemweiten Zwischenablage; Tests bestätigen diesen Unterschied.
- Keine Behauptung einer universellen Passworterkennung oder physisch forensisch sicheren Löschung aus SSD/Backups.
- `swift test` ist hier wegen fehlendem XCTest-Modul in den aktiven Command Line Tools blockiert. Der gemeinsame Testcode wurde über den Debug-Runner erfolgreich ausgeführt; die XCTest-Anbindung selbst ist erst mit vollständigem Xcode prüfbar.

## Tests selbst ausführen

```sh
zsh scripts/test.sh
zsh scripts/build-ui-test-app.sh
open '.build/SmartClip Test.app'
```

Die Test-App überwacht keine echte Zwischenablage. Kopieren verwendet ein privates Pasteboard; automatisches Einfügen, Browseröffnung und Autostart sind dort deaktiviert. Sie verwirft ihre erzeugten Daten beim normalen Beenden. Bei erzwungenem Abbruch können zufällig benannte `dev.smartclip.uitest.*`-Testreste in temporären Dateien/Einstellungen verbleiben. Nicht mit der normalen App unter `dist/SmartClip.app` verwechseln.

Mit vollständigem Xcode führt `swift test` denselben Kernprüfcode über XCTest aus. Für Designvorschauen:

```sh
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift run SmartClip --render-design
```

## Erweiterung: Code und Spracherkennung

Die Suite wurde um 32 Fälle auf **96 Prüffälle** erweitert: 16 Sprachmuster, mehrdeutige Syntax, Markdown-Codeblöcke, normale Texte als Negativfälle, Speicherung/Filter/Sprachsuche/Kopieren, Erkennung bereits gespeicherter Texte ohne Duplikate sowie maskierter sensibler Code. Die Spracherkennung ist eine lokale Syntaxheuristik und keine Garantie; unklare Sprache wird ausdrücklich gekennzeichnet. Sie führt keinen Code aus und verändert den kopierten Text nicht. Die Vorschau wurde auch in der kleinsten Fensterbreite gerendert.
