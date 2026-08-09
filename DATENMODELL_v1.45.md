# Datenmodell v1.45

## Produktive Tabellen

- `airports.csv`: Stammdaten, Koordinaten, Zeitzone, Referenzpiste, physische Länge, Breite und LDA
- `destinations.csv`: optionale touristische Detailprofile und bester aktiver Höhepunkt
- `features.csv`: sieben Merkmale je Flugplatz
- `services.csv`: Gastronomie und Mobilität; keine Frühstücksdetailplanung
- `fuels.csv`: Kraftstoffverfügbarkeit
- `fuel_prices.csv`: belastbar hinterlegte Preise
- `techstops.csv`: optionale TechStop-Details

## Schlüssel

`airport_id` entspricht dem ICAO-Code. Alle Untertabellen referenzieren einen vorhandenen Flugplatz. Doppelte IDs oder verwaiste Datensätze sind unzulässig.

## Strenge Merkmalsregel

Nur `status_raw = Ja` aktiviert eine Kategorie. Ein Haupt-Highlight darf nur aus einer aktiven Kategorie stammen. Allgemeine Ausflugsziele ohne Kategorienbezug können als Typ `Ausflug` geführt werden.

## Betriebsinformationen

Reguläre Öffnungs- und Betriebszeiten werden nicht importiert. Im Feld `operating_notes` stehen ausschließlich langfristig stabile Besonderheiten. Tagesaktuelle Informationen werden vor jedem Flug extern geprüft.

## Pisteninformationen

`runway_length_m` ist die physische Länge der Referenzpiste. `runway_lda_m` wird separat dargestellt. TORA ist nicht Teil des Flybook-Datenmodells.
