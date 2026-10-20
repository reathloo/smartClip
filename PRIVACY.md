# Datenschutz

SmartClip verarbeitet den Zwischenablage-Verlauf lokal auf dem Mac. Es gibt kein Konto, keine Telemetrie, keine Cloud-Synchronisierung und keinen Server-Upload.

- Inhalte, Bilddaten, Dateipfade und Favoritennamen werden verschlüsselt in SQLite gespeichert.
- Der Schlüssel liegt im macOS-Schlüsselbund.
- Technische Metadaten wie Zeitpunkt, Typ und geschätzte Quell-App sind nicht verschlüsselt.
- Aufbewahrungsfristen löschen Einträge aus SmartClip, nicht den aktuellen Inhalt der macOS-Zwischenablage oder Daten in Backups.
- Dateien werden nicht dupliziert; SmartClip speichert verschlüsselte Verweise auf die Originale.
- Automatisches Einfügen benötigt Bedienungshilfen-Zugriff. „Nur kopieren“ funktioniert ohne diese Freigabe.
- Sensitivitätserkennung erkennt bekannte Markierungen und eindeutige Kreditkartennummern. Sie kann nicht jedes Passwort zuverlässig erkennen.
