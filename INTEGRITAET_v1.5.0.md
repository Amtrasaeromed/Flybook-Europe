# Flybook Europe v1.5.0 – Release- und Integritätsprüfung

**Prüfdatum:** 17. August 2026  
**Ergebnis:** PASS für produktive Rechenwege, Laufzeitquellen, Datenfluss,
Persistenz, macOS und iPad-Simulatorbuild.

## Datenbestand

| Prüfung | Ergebnis |
|---|---:|
| Flugplätze | 144 |
| Touristische Zielprofile | 106 |
| TechStop-Profile | 37 |
| Merkmalszeilen | 1.008, exakt 7 je Platz |
| Services | 794 |
| Kraftstoffzeilen | 547 |
| Preiszeilen | 157 |
| Doppelte/verwaiste Schlüssel | 0 |
| Max. EDFZ-Distanzabweichung | 1,92 NM |

Unbekannte Kraftstoffpreise bleiben sichtbar als `?`; fehlende Werte werden
nicht erfunden. Zwei inaktive Reserve-ICAOs im historischen JSON-Bestand sind
nicht Teil des produktiven Airportbestands.

## Rechen- und Programmprüfung

- 206 Swift-Tests: 0 Fehler, 3 bewusst deaktivierte Live-Quellentests
- 37 unabhängige Release-Rechenprüfungen: PASS
- Datenimport, Fremdschlüssel und technische Airportdaten: PASS
- Persistenz und stabile macOS-Bundle-ID: PASS
- Datenfluss: 24 Prüfungen, einschließlich gemeinsamem macOS-/iPad-Netzwerkgate
- macOS-App und signierter iPad-Release-Gerätebuild: PASS

Geprüft sind unter anderem Flugzeit und Blockzeit, Wind, Best Level,
Kraftstoffverbrauch und Reserve, Refueling-Stops, Charterrundung,
Lande-/Park-/Zoll-/Handlingkosten, Währungsumrechnung, TOW/Landing Weight,
Dichtehöhe sowie Start- und Landestrecken einschließlich Sicherheitsmarge.

## Externe Quellen

Alle 15 zur Laufzeit verwendeten Wetter-, Karten-, Kraftstoff- und
Referenzzugänge waren beim Release-Audit erreichbar und lieferten den
erwarteten Inhalt. Ein zusätzlicher Audit aller 591 in den Masterdaten
gespeicherten Herkunftslinks ergab 498 erreichbare, 28 automatisiert
geschützte/gedrosselte und 65 historisch veraltete oder technisch nicht
erreichbare Nachweise. Diese Herkunftslinks werden von der App nicht zur
Laufzeit abgerufen und bleiben bis zu einer redaktionell verifizierten
Ersatzquelle unverändert, damit keine Quellenbelege erfunden werden.

AIP:Aero wurde für alle 144 produktiven Plätze abgefragt. 139 Detailseiten
waren verfügbar; EGHN, EGHJ, EPJA, ESMH und LFRF sind dort nicht gelistet und
behalten deshalb ausschließlich ihre vorhandenen Quellen. Es gab keine
Netzwerkfehler. Koordinaten-, Höhen- und Pistenabweichungen stehen mit beiden
Rohwerten im Audit und wurden nicht automatisch in die kuratierten
Airport-Stammdaten übernommen.

Bei EDTG stimmten AIP:Aero, AeroPS und Spritpreisliste mit 2,99 EUR/l AVGAS,
2,36 EUR/l MOGAS und 2,49 EUR/l Jet A-1 überein. Abweichende Werte von
2,04/1,77/2,03 EUR/l stammten aus einer Seite mit tatsächlichem Update vom
11.12.2020, obwohl sie 2026 als bestätigt bezeichnet wurden. Diese undatierten
Laufzeitwerte werden nicht mehr übernommen; der alte Preis-Cache wird durch
eine Validierungsversion verworfen.

## Gemeinsame Mac-/iPad-Pfade

Das iPad-Projekt bindet `airports.csv`, `features.csv`, `fuels.csv` und
`fuel_prices.csv` direkt aus `Sources/FlybookEurope/Resources` ein. Nicht
verwendete Kopien wurden entfernt. Auch das iPad-Korridorwetter verwendet nun
`FlightNetwork` mit globaler Verbindungsbegrenzung, niedriger Priorität und
dem gemeinsamen Open-Meteo-Circuit-Breaker.

Flybook bleibt eine Planungshilfe. AIP, NOTAM, PPR, offizielles
Flugwetterbriefing, Masse/Schwerpunkt und Flughandbuch sind vor jedem Flug
verbindlich zu prüfen.
