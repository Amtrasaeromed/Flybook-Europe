# Flybook Europe – Übergabe v1.47.0

## Sofortübergabe (16. August 2026)

- Arbeitsverzeichnis: `/Users/stephan/Documents/ChatGPT/Flybook`
- Branch: `codex/ipad-migration`
- Git-Stand: alle Änderungen auf `codex/ipad-migration` versioniert und für
  die Übergabe an einen weiteren Account vorbereitet
- Version: `1.47.0`
- Die macOS-App wurde erfolgreich mit
  `./Flybook\ Europe\ starten.command` gebaut, lokal signiert, unter
  `~/Applications/Flybook Europe.app` aktualisiert und geöffnet.
- Der letzte Build und die vollständige Swift-Test-Suite waren erfolgreich:
  201 Tests, 0 Fehler, 3 bewusst deaktivierte Live-Quellentests.
- Hin- und Rückflug besitzen ein editierbares TOW-Feld mit MTOW als
  Ausgangswert. Für A211/DEUKS/DEZHS werden Start- und Landestrecken aus den
  offiziellen POH-Ausgangswerten mit Dichtehöhe, Gewicht und Pistenwind
  berechnet; der Flybrief enthält Roll- und 50-ft-Strecke.
- Flughafenwahl, Runwayempfehlung, Rollstrecke, Uhrzeit und Wind stehen im
  Planungsfeld für Abflug und Ankunft auf exakt denselben vertikalen
  Mittelachsen. Roll- und 50-ft-Strecke zeigen jeweils ihre Auslastung. Die
  Performancezeile verwendet eine gut lesbare größere Schrift und schreibt
  die Hindernishöhe als `50 ft`. Die Rollstrecke ist von 50 bis 74 Prozent
  orange und ab 75 Prozent rot; die
  50-ft-Strecke wird ausschließlich ab 100 Prozent rot. Beim Start gilt die
  physische Pistenlänge, bei der Landung die LDA.
- Der Flybrief schreibt die Performance kompakt als `T/O Roll`, `50ft` und
  Gewicht; bei Landungen steht die `50ft`-Strecke vor dem `LDG Roll`. Das
  Landing Weight zieht den
  tatsächlich
  verflogenen Blockkraftstoff ohne Reserve mit der Dichte der im Flugzeugprofil
  bevorzugten Sorte vom TOW ab. Auch dort stehen die getrennten Roll-/50-ft-
  Prozentwerte mit derselben getrennten Roll-/50-ft-Warnlogik.
- Im aktiven Nutzerprofil ist unter Flugkalkulation eine Sicherheitsmarge von
  0 bis 50 Prozent in 5-Prozent-Schritten hinterlegt. Sie erhöht Roll- und
  50-ft-Strecke für Start und Landung und damit auch die Pistenprozentwerte.
- Daten-, Quellen-, Datenfluss-, Persistenz- und Rechenaudit sind grün.
- Der Destination Finder behält Ziele bei unvollständigem Streckenwetter als
  Treffer und kennzeichnet sie als nicht vollständig geprüft. Alpenföhn wird
  entlang der relevanten West-, Zentral- und Ostachsen bewertet.
- Mobilitätsdaten unterscheiden Fahrrad, Mietwagen, app2drive, Bahn und Bus.
  Bahn-/Busnähe bedeutet höchstens 500 m und mehrfach täglichen Verkehr; nicht
  eindeutig belegte Angebote bleiben als `?` gekennzeichnet.
- Tourismusmerkmale sowie die POE-/Zolltauglichkeit der Schweizer und
  britischen Ziele wurden redaktionell nachgeschärft.
- EDTM, EDQH, EDTG und EDTS sind als süddeutsche TechStops ergänzt. EDTS-Fuel
  ist als ausschließlich PPR verfügbar gekennzeichnet.
- Neuchâtel, Buochs, Reichenbach und Bremgarten besitzen die neu erfassten
  Lande-, Park- und Zollgebühren. Schweizer Beträge werden mit Tageskurs in
  EUR umgerechnet und auf volle Euro aufgerundet.
- Flugzeugprofile enthalten nun einen verpflichtenden Lärmwert in dB(A).
  Fehlt er, zeigt eine dB-abhängige Gebührenberechnung konsequent `?`.
  Für die AQUILA A211 ist der publizierte Wert 65,1 dB(A) vorbelegt.
- Die konkreten AeroPS-Platzrechner funktionieren ohne Login. Für EDTG sind
  AVGAS 100LL 2,99 EUR/l, SuperPlus 2,36 EUR/l und Jet A-1 2,49 EUR/l mit
  Stand 16.08.2026 hinterlegt.
- Der AeroPS-Abgleich ist für alle 144 Airports abgeschlossen und in
  `AEROPS_AUDIT_2026-08-16.csv` protokolliert. 40 Rechner zeigen Preise,
  95 Kraftstoffarten sind damit bestätigt und 72 eindeutige positive
  EUR-Preise übernommen. Mehrdeutige Doppelpreise und 0-EUR-Platzhalter
  bleiben ausschließlich im Audit. Das reproduzierbare Werkzeug liegt unter
  `Scripts/aerops_fuel_sync.py`.
- Die vier gemeinsam geführten Airport-/Feature-/Fuel-Ressourcen sind zwischen
  macOS und iPad bytegenau synchronisiert.
- Die Flugplanfelder sind verbreitert; der Betriebszeitstatus sitzt außen links
  am Abflug- und außen rechts am Ankunftsfeld. Best Level, gewählte Höhe und
  Streckenwind beginnen als entzerrte Fußzeile am linken Rand.
- Das Planungsfeld verwendet für den konkreten An-/Abflugzeitpunkt das direkte
  DWD-GRIB-Feld `CEILING`: ICON-D2 bis 48 Stunden, danach ICON-EU bis fünf
  Tage. Es findet dort keine Temperatur-/Taupunkt- oder Wolkenprofil-Schätzung
  mehr statt; ohne direkten Wert bleibt die Ceiling leer.
- Das validierte eigene Nebel-/Tiefwolken-Risikomodell bleibt ausschließlich
  in der farbcodierten 5-Tages-Wetteranzeige aktiv.
- Die gewählte Flughöhe wird im Flugplan-Picker wieder als konkreter Wert
  angezeigt. Die Charterkalkulation besitzt fünf unabhängige Gebührenhaken
  für Landung, Übernachtung, Zoll Einreise, Zoll Ausreise und Handling.
  Tanken, Parken, Zoll und Handling stehen als vier eigene Kostenzeilen; Zoll wird
  am tatsächlichen Grenzsegment dem Ausreise- beziehungsweise Einreiseplatz
  zugeordnet. Angezeigter Kraftstoff je Flug und in der Gesamtzeile ist nur
  der tatsächlich verflogene Blockkraftstoff ohne Reserve. Die Außenmaße der
  Kalkulations- und Zielblöcke bleiben gleich.
- Zwischen Lokal/UTC und Drucken öffnet ein Tanksäulen-Schalter den neuen
  Tankkalkulator. Er übernimmt alle aktiven Direkt- und Zwischenstopp-Legs,
  rechnet die Mindestbestände von der Reserve am Endziel rückwärts und erlaubt
  einen frei wählbaren Tankpunkt. Vorhandener Restkraftstoff wird beim
  Auffüllen angerechnet; Unterdeckung, negative Bestände und unzureichende
  Tankkapazität erscheinen als rote Warnung. Sechs deterministische Tests
  decken die Beispiele A–C–B–A mit Tankpunkt C beziehungsweise B ab.
  Minimum und tatsächlicher Plan sind tabellarisch getrennt; der Plan ist blau
  hervorgehoben und der Tankstopp steht als eigene Zwischenzeile. Berechnete
  Literwerte werden stets auf den nächsten vollen Liter aufgerundet. Die
  Verbrauchsspalte zeigt Leg- und laufenden Gesamtverbrauch; nach dem
  Refueling-Stop beginnt diese laufende Summe neu.
  Die Refuel-Menge wird in der Planzeile manuell, per Minimum oder per Voll
  gesetzt und mit „Tankberechnung übernehmen“ samt Refueling-Stop an die
  weiterhin editierbare Tanken-Zeile der Charterkalkulation übergeben. Die
  frühere Tanksäulen-/Starttankbedienung und der Hinflugreserve-Schalter der
  Charterkarte entfallen.
- Die Flybrief-Wetterseiten enthalten keine Kraftstoffangaben mehr. Nach
  „Tankberechnung übernehmen“ wird der bestätigte Tankplan als eigene letzte
  PDF-Seite mit Minimum, Plan, Refueling-Stop, Leg-/Etappenverbrauch, Zeit und
  Endreserve angehängt. Ändert sich Route, Flugzeug, Reserve, Startbestand oder
  übernommene Tankmenge, wird die Bestätigung als veraltet behandelt und die
  Fuelplan-Seite bis zur erneuten Bestätigung nicht ausgegeben.
- Unter jedem Flybrief-Zielblock folgt ein kompaktes Memo der drei
  geografisch nächsten Alternates mit Entfernung, Runwaylänge, Belag,
  Ausrichtung und Prognose zur Zielankunft. Wegen dieser zusätzlichen
  sicherheitsrelevanten Angaben werden Multi-Stop-Hauptflüge nicht mehr auf
  eine gemeinsame Wetterseite zusammengepresst.
- Wolkenangaben im Flybrief enthalten bei SCT/BKN/OVC stets die verfügbare
  direkte Ceiling-/Wolkenbasis. Frische Cachetreffer ohne Höhenwert werden mit
  dem direkten DWD-ICON-Ceiling-Feld nachangereichert; ein fehlgeschlagener
  Direktabruf löscht keinen bereits vorhandenen externen Basiswert mehr. Im
  Alternate-Memo stehen Wind und Runway exakt untereinander, die rechnerisch
  bevorzugte Pistenrichtung
  ist blau markiert und der bis zum Alternate benötigte Kraftstoff wird mit
  dem höhenabhängigen Profilverbrauch sicherheitsseitig auf volle Liter
  aufgerundet.
- Direkt unter dem farbcodierten Streckenwetter nennt der Flybrief die drei
  kompakten Entscheidungshilfen `FL30`, `FL60` und `FL90`; Windrichtungen sind
  auf zehn Grad gerundet, Geschwindigkeiten auf volle Knoten und Böen entfallen.
- In der Flugzeugkonfiguration erzeugt `Profil kopieren` ein neues editierbares
  Profil und übernimmt alle Basis-, Kosten-, Gewichts-, Lärm-, Kraftstoff-,
  Climb- und Cruise-Werte des Ausgangsflugzeugs.
- Das Zahnrad für das allgemeine Setup steht als letztes Symbol ganz rechts in
  der Hauptnavigation.
- Der macOS-Punktabruf benötigt ecCodes `grib_get`. iPadOS kann die
  komprimierten GRIB2-Dateien derzeit nicht lokal decodieren und lässt die
  Planungs-Ceiling deshalb leer, statt eine Näherung als Fremdwert auszugeben.
  Der signaturfreie iPad-Gerätebuild wurde erfolgreich geprüft.

## Noch offen / nächste Aufgabe

- AeroPS-Preise vor Releases erneut mit `python3 Scripts/aerops_fuel_sync.py`
  prüfen und nach Sichtkontrolle mit `--apply` übernehmen. Betreiber-/AIP-
  Quellen bleiben führend; fehlende AeroPS-Datensätze bleiben ohne negative
  Aussage.
- Die 33 URLs ohne passenden Rechner und 71 Rechner ohne sichtbare Preise nur
  bei neuen Betreiberhinweisen erneut redaktionell prüfen.

## Einstieg für den nächsten Account

Diesen Text als erste Aufgabe verwenden:

> Arbeite im bestehenden Projekt `/Users/stephan/Documents/ChatGPT/Flybook`
> weiter. Lies zuerst `PROJECT_HANDOFF.md` und `README.md`, prüfe danach
> `git status` und den aktuellen Branch. Bewahre alle vorhandenen Änderungen.
> Flybook v1.47.0 wurde zuletzt erfolgreich gebaut und gestartet. Setze meine
> nächste konkrete Anforderung direkt um. Der AeroPS-Abgleich für alle Airports
> ist abgeschlossen; verwende für Wiederholungen das dokumentierte Skript und
> halte Mac- und iPad-Ressourcen synchron. Verifiziere anschließend Swift-Tests
> und Release-Audits aus dem README.

## Produktstand

- Native SwiftUI-/SwiftPM-App für macOS 13 oder neuer
- Bundle-ID `de.flybook.europe`
- 144 Flugplätze, 106 Ziele, 37 TechStops
- Flugzeugprofile DEUKS, DETIK und benutzerdefinierte Flugzeuge
- dauerhafte Profile für Stephan und Maria

## Freigaberelevante Architektur

- Ein zentraler Charter-/Blockzeitpfad; Reservierung und Charteranzeige nutzen
  dieselbe Rundung je Flug.
- Kraftstoffzuzahlung vergleicht den gewählten Kraftstoff mit dem
  Referenzkraftstoff des aktiven Flugzeugs an der Heimatbasis.
- Best-Level-Suche: 2.000–10.000 ft in 500-ft-Schritten, exakte Modellflächen
  plus ausschließlich lokale Vektorinterpolation für Zwischenhöhen.
- Wetterabrufe sind gecacht, zusammengeführt, priorisiert und global begrenzt.
  Der App-Start löst weder einen Vollwetterabruf noch einen Preis-Scrape aus.

## Persistenz

Die stabile Bundle-ID darf bei Updates nicht geändert werden. Allgemeine,
Flugzeug- und Airportprofile liegen in `UserDefaults.standard`. Benutzerprofile
liegen zusätzlich in `de.flybook.europe.user-profiles` und werden beim Start
migriert bzw. wiederhergestellt.

## Release-Prüfung

Alle automatisierten Befehle stehen in `README.md`. Für einen Store-/Gerätebuild
bleiben ein Xcode-Archive, Signierung, Sandbox-/Entitlement-Prüfung und reale
Offline-/schwaches-Netz-Tests auf den Zielgeräten erforderlich.
