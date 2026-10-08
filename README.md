# SmartClip

<img src="Resources/AppIcon.png" alt="SmartClip App-Icon" width="96">

Ein lokaler, verschlüsselter Zwischenablage-Verlauf für **macOS 14+** – direkt in der Menüleiste, ohne Konto oder Cloud.

## Funktionen

- Text, Links, E-Mails, Bilder, Dateireferenzen und Code mit Spracherkennung.
- Suche, Typfilter, benannte Favoriten sowie Listen- und Kartenansicht.
- Globales Tastenkürzel, optionaler Autostart und direktes Einfügen.
- Zeitgesteuerte Pausen, direkte App-Ausschlüsse und hilfreiche Wiederherstellungsaktionen.
- Einstellbare Löschfristen und maskierte sensible Inhalte.

## Starten

Voraussetzung: passende Swift-Toolchain über Xcode oder Command Line Tools.

```sh
zsh scripts/build-app.sh
open dist/SmartClip.app
```

Beim ersten Start die Aufzeichnung aktivieren und ein Kürzel wählen, beispielsweise **⌘⇧V**. Direktes Einfügen benötigt die Bedienungshilfen-Freigabe.

## Tests

```sh
zsh scripts/test.sh
```

110 automatisierte Prüffälle mit isolierten Testdaten. Details und offene Systemtests: [Testbericht](docs/TESTBERICHT.md) · [Projektplan](Plan.md).

## Hinweise

Dateien bleiben Verweise auf ihre Originale; Bilder über 20 MB werden übersprungen. Die Spracherkennung ist heuristisch, eine universelle Passworterkennung gibt es nicht. Löschfristen gelten für den Verlauf, nicht für die macOS-Zwischenablage. Die App ist noch nicht signiert oder notarisiert.
