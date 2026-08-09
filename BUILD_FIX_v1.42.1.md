# Build Fix v1.42.1 – Reiseflughöhe

## Fehler

Die Hin- und Rückflughöhe wurden intern mit 5.000 ft initialisiert. Dieser Wert
kommt in keiner der beiden kursabhängigen VFR-Höhenlisten vor. Dadurch konnte
der Höhen-Picker beim ersten Rendern einen ungültigen beziehungsweise leeren
Auswahlzustand zeigen, während Berechnungen bereits mit 5.000 ft liefen.

## Korrektur

- Gemeinsamer gültiger Startwert: 3.500 ft
- Zentrale Höhenregeln in `FlightAltitudeRules`
- Bestehende kursabhängige Listen unverändert
- Regressionstests für beide Kursgruppen und die Normalisierung des alten
  5.000-ft-Werts
