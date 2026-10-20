# Release-Ablauf

SmartClip wird derzeit kostenlos ohne Apple Developer ID und ohne Notarisierung verteilt.

## Paket erzeugen

```sh
zsh scripts/package-release.sh v0.1.0-beta.1
```

Das Skript führt die 113 Kernprüfungen aus, erstellt die Produktions-App, baut ein DMG und prüft Prüfsumme, Inhalt, Architektur, Mindestversion und die erwartete Gatekeeper-Ablehnung. Die Dateien landen unter `dist/release/`.

## Vor Veröffentlichung

- Offene Systemtests aus [TESTBERICHT.md](TESTBERICHT.md) auf einem echten Mac durchführen.
- Sicherstellen, dass der Git-Arbeitsbaum sauber ist und das Paket zum Release-Commit gehört.
- Release-Notizen und Versionsnummer prüfen.
- DMG auf einem separaten Benutzerkonto nach [INSTALLATION.md](INSTALLATION.md) installieren.

## GitHub Release

1. Tag `v0.1.0-beta.1` am geprüften Commit erstellen.
2. GitHub Release mit Titel **SmartClip v0.1.0-beta.1** als **Pre-release** anlegen.
3. Diese Dateien hochladen:
   - `SmartClip-0.1.0-beta.1-macOS-arm64.dmg`
   - `SmartClip-0.1.0-beta.1-macOS-arm64.dmg.sha256`
   - `SmartClip-0.1.0-beta.1-macOS-arm64.txt`
4. Inhalt aus [releases/v0.1.0-beta.1.md](releases/v0.1.0-beta.1.md) als Beschreibung verwenden.

Bei einem privaten Repository können nur berechtigte GitHub-Nutzer das Release herunterladen.
