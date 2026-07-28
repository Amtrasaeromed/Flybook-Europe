# Build fix v1.38.11

Das Flybook Image Studio ermittelt den Projektordner jetzt unabhängig vom Xcode-Arbeitsverzeichnis.

Behoben:
- `Flybook_Master.csv couldn't be opened because there is no such file.`
- Xcode startet Swift-Package-Executables aus DerivedData; der frühere Code suchte deshalb am falschen Ort.
- Der Projektpfad wird nun zuverlässig aus `#filePath` abgeleitet, mit Fallbacks für `swift run` und die `.command`-Datei.
- Das Studio validiert weiterhin exakt 35 Ziele.
