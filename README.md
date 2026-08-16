# Flybook Europe Native v1.47.0

Native macOS-App zur Zielauswahl, Flugzeit-, Kraftstoff- und Charterkalkulation
für VFR-Reisen. Die App bleibt ein Planungswerkzeug und ersetzt weder AIP,
NOTAM, PPR, Flugwetterbriefing noch die operative Flugleistungsrechnung.

## Aktueller Umfang

- 144 Flugplätze in `airports.csv`
- 106 touristische Zielprofile und 37 TechStop-Profile
- 1.008 Merkmalszeilen: exakt sieben je Flugplatz
- 794 Service-, 475 Kraftstoff- und 102 Preisdatensätze
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
- Das Planungsfeld liest die Flugwetter-Ceiling für den konkreten An-/Abflug
  direkt aus dem DWD-GRIB-Feld `CEILING`: bevorzugt ICON-D2 (bis 48 Stunden),
  danach ICON-EU (bis fünf Tage). Der Wert ist bereits eine Modellhöhe über
  Grund und wird nicht aus Temperatur, Taupunkt oder Wolkenanteilen geschätzt.
  Fehlt das direkte Feld, bleibt die Ceiling leer und die Kategorie wird nur
  aus der externen Sichtweite bestimmt.
- Das separat validierte Nebel-/Tiefwolken-Risikomodell der 5-Tages-Anzeige
  verwendet weiterhin mehrere Wetterfaktoren und seine Farbcodierung; es wird
  nicht als punktgenaue Planungs-Ceiling ausgegeben.
- Die direkte GRIB-Punktabfrage auf macOS nutzt `grib_get` aus ecCodes
  (`/opt/homebrew/bin` oder `/usr/local/bin`). Fehlt der Decoder, zeigt das
  Planungsfeld bewusst keine geschätzte Ceiling. iPadOS verwendet ebenfalls
  keine Ersatzschätzung; das 5-Tages-Risikomodell bleibt dort separat aktiv.
- Langfristprognose, Streckenrisiko und Föhnprüfung sind nachrangig und zeitlich
  gestaffelt, damit schwache Mobilverbindungen nicht mit Anfragepaketen
  überlastet werden.

## Rechenmodell

Die zentrale Berechnung berücksichtigt Strecke, Zwischenstopps, Steigleistung,
höhenabhängige Cruise-Performance, Wind, Bodenzeiten, Reserve,
Charter-Rundung, Rabatte und Kraftstoffzuzahlung gegen den Referenzkraftstoff
der Heimatbasis. Die sichtbare Charter- und Reservierungsrechnung benutzen
denselben kommerziellen Rundungspfad.

Die Charterkalkulation führt Landegebühr, Übernachtungsgebühr, Zoll Einreise,
Zoll Ausreise und Handling als fünf unabhängige Schalter. Landegebühren sind
standardmäßig aktiv; Übernachtung und Zoll werden aus dem Flugplan vorbelegt.
Tanken, Parken, Zoll und Handling erscheinen als vier einheitliche eigene
Tabellenzeilen. Die Kraftstoffwerte der einzelnen Flüge und der Gesamtzeile
zeigen ausschließlich den tatsächlich verflogenen Blockkraftstoff; Reserven
werden dort nicht als Verbrauch mitgerechnet.
Zollkosten werden dem tatsächlichen Ausreise- und Einreiseflugplatz am
Grenzsegment zugeordnet; unbekannte Tarife bleiben sichtbar als `?` und werden
nicht in die Gesamtsumme erfunden.

Der Tanksäulen-Schalter zwischen Lokal/UTC und Drucken öffnet den
Tankkalkulator für alle aktuell geplanten Legs. Er berechnet die erforderlichen
Bestände vom Reservekraftstoff am letzten Ziel rückwärts, zeigt je Abschnitt
Leg-Verbrauch, die seit dem letzten Tankstopp laufende Verbrauchssumme,
Mindest- und Planbestand und erlaubt einen frei wählbaren Tankpunkt. Am
Tankstopp beginnt die laufende Verbrauchssumme wieder bei null.
Am Tankpunkt wird vorhandener Restkraftstoff auf die Mindest-Auffüllmenge
angerechnet. Zu kleiner Startbestand, zu geringe Auffüllmenge, negative
Bestände sowie Überschreitungen der nutzbaren Tankkapazität werden rot
gekennzeichnet. Die Tabelle ordnet Minimum, den blau hervorgehobenen Plan,
Verbrauch und Zeit in getrennten Spalten. Der gewählte Tankstopp erscheint als
eigene Zeile zwischen den Legs; alle berechneten Literwerte werden auf den
nächsten vollen Liter aufgerundet. Die Refuel-Menge wird direkt in dieser
Planzeile manuell, als Minimum oder bis Voll festgelegt. **Tankberechnung
übernehmen** überträgt Menge und Refueling-Stop in die weiterhin manuell
editierbare Tanken-Zeile der Charterkalkulation, sodass der passende bekannte
Platzpreis für die Zusatzkosten verwendet wird.

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

Der vollständige AeroPS-Abgleich verwendet konkrete Rechner-URLs ohne
abschließenden Slash. Ein erneuter Nur-Lese-Audit und die kontrollierte
Übernahme erfolgen mit:

```sh
python3 Scripts/aerops_fuel_sync.py
python3 Scripts/aerops_fuel_sync.py --apply
```

Der geprüfte Stand ist in `INTEGRITAET_v1.47.0.md` dokumentiert.

## iPad-Migration

Die neue SwiftUI-iPad-App liegt unter `Flybook-iPad/` und ist für eine feste
Hochformat-Vollbildansicht ausgelegt. Die Flugplanung stellt Abflug und Ankunft
spiegelbildlich dar; Wind, Zielwechsel und Blockzeit liegen auf der Mittelachse.
Die Zielauswahl akzeptiert eine direkte ICAO-Eingabe und zeigt ab drei Zeichen
Vorschläge. Der dauerhaft sichtbare Zwischenstoppblock hält Auswahlfelder und
0/1/2-Schalter in einem festen, einzeiligen Layout.
Das Flugwetter übernimmt die Risikologik des Hauptprojekts und bewertet den
Streckenkorridor in zehn farbcodierten Abschnitten. Sicht, Niederschlag,
Gewitter/CAPE, Taupunktspreizung, tiefe Bewölkung und die Wolkenschicht an der
gewählten Flughöhe fließen in die Einstufung ein.
Die iPad-Flugplanung trennt Reisezeit und Charter-Blockzeit: Reisezeit enthält
zusätzlich die Pausen geplanter Tankstopps, während Charter, Kraftstoff und die
Blockzeitspalte nur die Zeit von Losrollen bis Anhalten summieren. Manuell
wählbare Höhen und Best Level folgen der kursabhängigen VFR-Halbkreisflugregel.
Das verdichtete Hochformatlayout integriert die beiden Wetterdatengruppen und
die zehn Korridorpunkte direkt in die Flugplanung. VFR/MVFR stehen
spiegelbildlich an den ICAO-Feldern; die Zwischenstoppsteuerung bleibt ohne
zusätzliche Überschrift als feste, einzeilige Bedienleiste sichtbar.
Unter Datum und Abflugzeit stehen die aus dem Hauptprojekt übernommenen
Schnellwahlen **Jetzt**, **Heute** und **Morgen**. Die zehn Korridorbalken
besitzen innerhalb der vergrößerten Flugplanung eine eigene Zeile.
