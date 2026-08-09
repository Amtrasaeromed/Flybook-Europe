# Flybook Europe Native v1.46.0

Native macOS-App zur Zielauswahl, Flugzeit-, Kraftstoff- und Charterkalkulation
für VFR-Reisen. Die App bleibt ein Planungswerkzeug und ersetzt weder AIP,
NOTAM, PPR, Flugwetterbriefing noch die operative Flugleistungsrechnung.

## Aktueller Umfang

- 125 Flugplätze in `airports.csv`
- 94 touristische Zielprofile und 31 TechStop-Profile
- 875 Merkmalszeilen: exakt sieben je Flugplatz
- 373 Service-, 471 Kraftstoff- und 36 Preisdatensätze
- Flugzeug-, Vereins-, Benutzer- und Airportprofile dauerhaft in `UserDefaults`
- Benutzerprofile Stephan und Maria in der stabilen Suite
  `de.flybook.europe.user-profiles`

## Wetter und Datenverkehr

- **NOW!** umgeht bewusst alle Wetter-Caches und aktualisiert Flugplatzwetter,
  Langfristprognose, Streckenwind, Korridorrisiko, Föhn und Alternates. Dieser
  Modus verursacht den maximalen Wetterdatenverkehr.
- **Update** im Hinflugfeld ist der datensparende Modus für den Flug: Er lädt
  nur die bis zu vier Flugplanungsplätze und die Alternates neu. Langfrist-
  prognose, Streckenwind und Korridorwetter bleiben dabei unangetastet.
- Der Alternates-Dialog zeigt zuerst den aktuellen Zielairport. Dahinter sucht
  er aufsteigend nach Entfernung so lange weiter, bis vier Airports die
  Wetter- und Runway-Filter erfüllen. Angezeigt werden geografische Runway,
  Windpfeil, Entfernung, Peilung und die windstille Flugzeit mit der
  65-%-Leistung des aktiven Flugzeugs bei 1.500 ft. Aus demselben Profilpunkt
  wird der direkte Streckenverbrauch in der eingestellten Kraftstoffeinheit
  berechnet und auf die nächste gerade Einheit aufgerundet. Wetter-Minimums
  lassen sich auf **MVFR** (Standard), **VFR** oder
  **OFF** stellen; die Mindestbahnlänge ist von 300 bis 1000+ m wählbar.
  Der standardmäßig aktive Öffnungszeitenfilter vergleicht die Prognosezeit
  mit hinterlegten publizierten Betriebszeiten. Sicher geschlossene Plätze
  werden ersetzt; fehlende oder PPR-abhängige Angaben bleiben mit dem Hinweis
  **Öffnungszeit unklar** sichtbar.
  Runway- und Windwarnungen verwenden dieselben Hinterlegungen wie Hin- und
  Rückflug. **Update** aktualisiert gezielt nur die fünf angezeigten Plätze
  ohne Cache.
- **Stand EDFZ** setzt EDFZ als Referenz und priorisiert EDFE, EDFM, EDRK und
  EDRY. Erfüllt davon ein Airport die Filter nicht, rückt der nächste passende
  Kandidat nach; ein erneuter Klick kehrt zum aktuellen Hauptziel zurück.
- Gleichzeitige identische Abrufe werden zusammengeführt; global laufen maximal
  vier Fachanfragen und pro Host höchstens drei Verbindungen.
- Der Destination Finder lädt Wetter erst nach den statischen Filtern, in
  kleinen Zehnergruppen und nur für das gewählte Zeitfenster.
- Das Best Level wird für jede 500-ft-Stufe von 2.000 bis 10.000 ft berechnet.
  ICON-D2/ICON-EU-Wind wird auf allen gelieferten Druckflächen verwendet;
  fehlende Zwischenhöhen werden vektoriell zwischen benachbarten
  Modellflächen interpoliert.
- Langfristprognose, Streckenrisiko und Föhnprüfung sind nachrangig und zeitlich
  gestaffelt, damit schwache Mobilverbindungen nicht mit Anfragepaketen
  überlastet werden.

## Rechenmodell

Die zentrale Berechnung berücksichtigt Strecke, Zwischenstopps, Steigleistung,
höhenabhängige Cruise-Performance, Wind, Bodenzeiten, Reserve,
Charter-Rundung, Rabatte und Kraftstoffzuzahlung gegen den Referenzkraftstoff
der Heimatbasis. Die sichtbare Charter- und Reservierungsrechnung benutzen
denselben kommerziellen Rundungspfad.

## Start und Prüfung

`Flybook Europe starten.command` doppelklicken oder `Package.swift` in Xcode
öffnen und das Produkt **Flybook Europe** ausführen.

Release-Prüfungen:

```sh
swift build
python3 Scripts/release_data_audit.py
python3 Scripts/release_source_audit.py
python3 Scripts/release_transfer_audit.py
python3 Scripts/release_persistence_audit.py
Scripts/run_release_math_audit.sh
```

Der geprüfte Stand ist in `INTEGRITAET_v1.46.0.md` dokumentiert.

## iPad-Migration

Die neue SwiftUI-iPad-App liegt unter `Flybook-iPad/` und ist für eine feste
Hochformat-Vollbildansicht ausgelegt. Die Flugplanung stellt Abflug und Ankunft
spiegelbildlich dar; Wind, Zielwechsel und Blockzeit liegen auf der Mittelachse.
Die Zielauswahl akzeptiert eine direkte ICAO-Eingabe und zeigt ab drei Zeichen
Vorschläge. Der dauerhaft sichtbare Zwischenstoppblock hält Auswahlfelder und
0/1/2-Schalter in einem festen, einzeiligen Layout.
