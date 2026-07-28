# Flybook-Zielbilder: Batch-Produktion

Der Workflow erzeugt für alle **35 Ziele** standardmäßig je drei Kandidaten und
legt sie unter `ImageProduction/Candidates/<ICAO>/` ab. Bereits vorhandene Bilder
werden übersprungen; ein abgebrochener Lauf kann daher einfach erneut gestartet
werden.

## 1. API-Schlüssel nur lokal setzen

```bash
export OPENAI_API_KEY="sk-..."
```

Der Schlüssel wird weder in Dateien geschrieben noch in die ZIP aufgenommen.

## 2. Alle 105 Kandidaten erzeugen

Per Doppelklick auf macOS:

```text
Tools/run_image_pipeline.command
```

oder im Terminal:

```bash
python3 Tools/generate_destination_images.py
python3 Tools/review_destination_images.py
python3 Tools/approve_destination_images.py --create-template
```

Ein einzelnes Ziel lässt sich so neu erzeugen:

```bash
python3 Tools/generate_destination_images.py --icao EHTX --force
```

Ein reiner Test ohne API-Aufruf:

```bash
python3 Tools/generate_destination_images.py --dry-run
```

## 3. Favoriten auswählen

In `ImageProduction/selections.csv` je Ziel die Kandidatennummer 1–3 eintragen
und `approved` auf `yes` setzen. Anschließend:

```bash
python3 Tools/approve_destination_images.py
```

Das Skript verlangt standardmäßig exakt 35 Freigaben und kopiert die Bilder als
`<ICAO>.webp` nach `Sources/FlybookEurope/Resources/regions/`. Die App findet sie
bereits über den vorhandenen `ImageCatalog`.

## Dateien

- `Tools/image_generation_config.json`: Modell, Format, Auflösung, Qualität, Anzahl
- `Tools/prompts/flybook_style.txt`: einheitlicher visueller Masterstil
- `ImageProduction/generation_manifest.jsonl`: revisionssicheres Erzeugungsprotokoll
- `ImageProduction/Reports/candidate_review.csv`: technische Vollständigkeitsprüfung
- `ImageProduction/selections.csv`: manuelle Endauswahl

## Kostenkontrolle

Der Standardlauf erzeugt 105 Bilder. Modell, Qualität und Anzahl können vor dem
Start zentral in `Tools/image_generation_config.json` reduziert werden. Für einen
kleinen Testlauf zuerst beispielsweise nur ein Ziel starten:

```bash
python3 Tools/generate_destination_images.py --icao EHTX --count 1
```
