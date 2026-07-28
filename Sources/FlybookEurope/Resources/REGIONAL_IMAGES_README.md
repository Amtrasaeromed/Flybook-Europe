# Regionalbilder

Die App lädt Regionalbilder aus:

`Sources/FlybookEurope/Resources/regions/`

## Standardbenennung

Für jedes Ziel reicht eine JPG-Datei mit dem ICAO-Code als Dateiname:

- `EHTX.jpg`
- `EHMZ.jpg`
- `LOWZ.jpg`

Empfohlen:

- Querformat
- Seitenverhältnis ungefähr 4:3 oder 3:2
- mindestens 1600 × 1000 Pixel
- keine eingeblendeten Logos oder Texte
- Motiv soll Region und Reiseziel zeigen, nicht nur das Flughafengebäude

## Abweichender Dateiname

In `destination_data.json` kann über `region_image` ein anderer Dateiname
hinterlegt werden.

Beispiel:

```json
"EHMZ": {
  "region_image": "regions/midden-zeeland.jpg"
}
```

`MISSING_REGIONAL_IMAGES.txt` enthält alle ICAO-Codes, für die aktuell noch
kein Bild im Ressourcenordner vorhanden ist.

Die Europakarte wird nicht mehr als Bilddatei benötigt. Sie wird automatisch
mit MapKit aus den Zielkoordinaten erzeugt.
