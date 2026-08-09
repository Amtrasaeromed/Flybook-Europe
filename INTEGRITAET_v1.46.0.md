# Flybook Europe v1.46.0 – Release- und Integritätsprüfung

**Prüfdatum:** 9. August 2026  
**Ergebnis:** PASS für Build, Laufzeitquellen, Daten, Rechenmodell,
Datenfluss und Persistenz.

## Datenbestand

| Prüfung | Ergebnis |
|---|---:|
| Flugplätze / eindeutige IDs | 125 / 125 |
| Touristische Zielprofile | 94 |
| TechStop-Profile | 31 |
| Merkmalszeilen | 875, exakt 7 je Platz |
| Services | 373 |
| Kraftstoffzeilen | 471 |
| Preiszeilen | 36 |
| Doppelte/verwaiste Schlüssel | 0 |
| Fehlende Pistenbreiten/LDA/Zeitzonen | 0 |
| LDA größer als physische Piste | 0 |
| Max. EDFZ-Distanzabweichung | 1,92 NM |

Aktive Merkmale: TechStop 31, Frühstück 9, Stadt 7, Strand/Meer 50,
See/Natur 29, Berge/Wandern 27 und Wellness 33.

Reduzierte LDA: EDKA, EDNH, EDTF, EDXE, EHLE, LOKL, LOLU, LOSM, EDVE und
EDAX. Diese Werte werden bewusst getrennt von der physischen Pistenlänge
geführt.

## Automatisierte Freigabeprüfungen

- Nativer `swift build`: PASS.
- 37 Rechenproben: PASS.
- 18 Datenfluss-/Low-Data-Prüfungen: PASS.
- Laufzeitquellen Open-Meteo DWD/Best Match, MET Norway, Esri, EDFZ,
  Spritpreisliste, Aviation Fuel Prices, Landegut, DWD Open Data und NOAA:
  live erreichbar und inhaltlich validiert.
- ICON-D2- und ICON-EU-Vertikalwind: Richtung, Geschwindigkeit und
  geopotentielle Höhe auf acht Druckflächen plus Bodenwind live validiert.
- Persistenz von Benutzer-, Flugzeug-, Airport- und Vereinsprofilen: statisch
  validiert; Bundle-ID und Profilsuite sind versionsstabil.

## Bekannte Datenpolitik

Ein Rohhinweis `Ja` ohne verifizierten Kraftstoffpreis wird absichtlich als `?`
angezeigt. Erst ein Preis bestätigt Kraftstoff als verfügbar. Historische
Masterquellen können inzwischen umgezogen oder gegen automatisierte Abrufe
geschützt sein; sie sind keine Laufzeitabhängigkeit. Operative Flugplanung muss
immer aktuelle offizielle Luftfahrtinformationen verwenden.

## Vor iPad-/iPhone-Veröffentlichung

Für die Portierung verbleiben Xcode-Archive, Signierung, iOS-/iPadOS-spezifische
Layouts, Berechtigungen, Hintergrund-/Offlineverhalten und reale Tests mit
gedrosselter bzw. abbrechender Mobilverbindung. Diese Punkte sind nicht durch
den macOS-SwiftPM-Build abgedeckt.
