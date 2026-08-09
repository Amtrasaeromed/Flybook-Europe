# Build Fix v1.42.2 – kursabhängige Reiseflughöhen

## Fehler

In v1.42.1 war 3.500 ft als gemeinsamer Startwert auch in die westliche
Kursgruppe aufgenommen worden. Dadurch enthielt die Auswahl für Kurse
180–359° eine falsche Halbkreisflughöhe.

## Korrektur

- gemeinsamer gültiger Startwert: 2.500 ft
- Kurse 000–179°: 2.500, 3.500, 5.500, 7.500 und 9.500 ft
- Kurse 180–359°: 2.500, 4.500, 6.500 und 8.500 ft
- Regressionstest gegen 3.500 ft in der westlichen und 4.500 ft in der östlichen Liste
- Normalisierung des früheren 5.000-ft-Werts bleibt erhalten
