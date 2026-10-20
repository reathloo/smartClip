# SmartClip installieren

## Voraussetzungen

- Mac mit Apple Silicon (M1 oder neuer)
- macOS 14 oder neuer

## Installation

1. `SmartClip-0.1.0-beta.1-macOS-arm64.dmg` herunterladen.
2. Optional die Prüfsumme im Terminal kontrollieren:

   ```sh
   shasum -a 256 -c SmartClip-0.1.0-beta.1-macOS-arm64.dmg.sha256
   ```

3. Das DMG öffnen und **SmartClip.app** auf **Programme** ziehen.
4. SmartClip in Programme einmal öffnen. macOS meldet, dass der Entwickler nicht verifiziert werden kann.
5. **Systemeinstellungen → Datenschutz & Sicherheit** öffnen und bei SmartClip **Dennoch öffnen** wählen.
6. Im folgenden Dialog erneut **Öffnen** wählen.

Diese Bestätigung ist nötig, weil die kostenlose Beta keine Apple Developer ID und keine Apple-Notarisierung besitzt. Sie gilt anschließend als lokale Ausnahme für diese App. Apples Beschreibung dieses Ablaufs: [Eine App eines unbekannten Entwicklers öffnen](https://support.apple.com/de-de/guide/mac-help/mh40616/mac).

## Erster Start

- Zwischenablage-Aufzeichnung aktivieren.
- Ein globales Tastenkürzel wählen; SmartClip schlägt `⌘⇧V` vor.
- „Nur kopieren“ funktioniert ohne Bedienungshilfen-Freigabe.
- Automatisches Einfügen benötigt die Freigabe unter **Datenschutz & Sicherheit → Bedienungshilfen**.
- Autostart ist optional und lässt sich in SmartClip aktivieren.

## Aktualisieren

SmartClip beenden, das neue DMG öffnen und die vorhandene App in Programme ersetzen. Verlauf und Einstellungen liegen außerhalb des App-Pakets und bleiben dabei erhalten.

## Deinstallieren

SmartClip beenden, Autostart vorher deaktivieren und die App aus Programme löschen. Verlauf und Einstellungen werden dadurch nicht automatisch entfernt.
