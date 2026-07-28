# Flybook Europe Native v1.38.7

Der CSV-Parser iteriert jetzt über Unicode-Scalars statt über `Character`.
Swift kann `\r\n` als ein gemeinsames Graphem behandeln; dadurch wurde zuvor
keine Zeile erkannt und die gesamte Datei als Kopfzeile gelesen. Der neue Parser
unterstützt CRLF, LF, CR, UTF-8-BOM, quoted fields, eingebettete Trennzeichen,
Zeilenumbrüche in quoted fields und escaped quotes.

Geprüft mit der eingebetteten Masterdatei:
- 36 CSV-Zeilen
- 1 Kopfzeile
- 35 Ziele
- 30 Spalten je Zeile

## v1.38.6
- Flugplatzhöhe in der Unterzeile der Zielüberschrift ergänzt.


## v1.38.7
- Vollständiger Batch-Workflow für KI-generierte Bilder aller 35 Ziele ergänzt.
- Einheitlicher Flybook-Stilprompt und automatisch individualisierte Zielprompts.
- Standardmäßig drei WebP-Kandidaten pro Ziel in 1536 × 1024 Pixeln.
- Unterbrechungsfester Wiederaufnahme-Modus, Retry-Logik und JSONL-Manifest.
- Technische Kandidatenprüfung und CSV-basierte manuelle Freigabe.
- Automatisches Kopieren der 35 freigegebenen Bilder in die Swift-Package-Ressourcen.
- API-Schlüssel wird ausschließlich aus `OPENAI_API_KEY` gelesen und nie gespeichert.

## Flybook Image Studio (v1.38.9)

Für die grafische KI-Bildproduktion liegt im Projektstamm **Flybook Image Studio.command**. Das native SwiftUI-Hilfstool speichert den OpenAI-API-Schlüssel im macOS-Schlüsselbund, startet den Batchgenerator, zeigt alle Kandidaten und übernimmt die 35 gewählten Favoriten in die App-Ressourcen. Details: `IMAGE_STUDIO_README.md`.
