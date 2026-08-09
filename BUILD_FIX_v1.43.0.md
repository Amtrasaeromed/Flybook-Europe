# BUILD FIX v1.43.0

## Behobene Fehler

1. Die App lud nur 86 Zeilen aus `destinations.csv`; jetzt werden alle 111 Zeilen aus `airports.csv` geladen.
2. `techstops.csv` wurde bisher verworfen; jetzt ergänzt es operative Details und das gleichrangige Merkmal `TechStop`.
3. TechStop, Strand/Meer, See/Natur, Berge/Wandern und Wellness sind fünf unabhängige Merkmale.
4. Reine TechStops erhalten keine touristischen Merkmale oder künstlichen touristischen Inhalte.
5. 80 fehlende Höhenwerte wurden nicht mehr als `0 ft` interpretiert. Alle 111 Höhen sind befüllt; fehlende Pflichtwerte stoppen den Import mit einer verständlichen Fehlermeldung.
6. Die Schema-Validierung umfasst jetzt auch `techstops.csv`.
7. Zielzählung und Tests wurden auf 111 Ziele plus EDFZ aktualisiert; der veraltete EDDV-Test wurde entfernt.
8. Der Destination Finder bietet einen gleichrangigen Merkmalsfilter. Mehrfachauswahl arbeitet als ODER-Filter.
9. Die Halbkreis-Höhenkorrektur aus v1.42.2 bleibt unverändert enthalten.

## Erwartetes Ergebnis

- 112 auswählbare Flugplätze in der App: 111 Ziele plus EDFZ
- 111 eindeutige Nicht-Heimatziele
- 555 Feature-Zeilen
- keine fehlenden Flugplatzhöhen
