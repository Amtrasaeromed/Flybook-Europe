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
  176 Tests, 0 Fehler, 2 bewusst deaktivierte Live-Quellentests.
- Der deterministische Daten-, Datenfluss- und Persistenzaudit ist grün. Der
  Live-Quellenaudit benötigt freien Netzwerkzugriff und war in der lokalen
  Sandbox nicht ausführbar.
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

## Noch offen / nächste Aufgabe

- Den AeroPS-Abgleich für **alle 144 Airports** fortführen. Die URL ist jeweils
  `https://gat.aerops.com/prices/calculator/ICAO` (ohne abschließenden Slash),
  zum Beispiel `.../EDTG` oder `.../EDTF`.
- AeroPS als zusätzliche Quelle verwenden: bestätigte Kraftstoffarten und
  sichtbare Preise übernehmen; ein fehlender AeroPS-Datensatz ist niemals
  allein ein Beleg für `Nein`. Betreiber-/AIP-Quellen bleiben führend.
- AVGAS, UL91 und MOGAS/Super98 platzweise verifizieren. Nur eindeutig
  bestätigte Werte werden `Ja`, unklare bleiben `?`, eindeutig ausgeschlossene
  werden `Nein`. Mac- und iPad-Ressourcen synchron halten.

## Einstieg für den nächsten Account

Diesen Text als erste Aufgabe verwenden:

> Arbeite im bestehenden Projekt `/Users/stephan/Documents/ChatGPT/Flybook`
> weiter. Lies zuerst `PROJECT_HANDOFF.md` und `README.md`, prüfe danach
> `git status` und den aktuellen Branch. Bewahre alle vorhandenen Änderungen.
> Flybook v1.47.0 wurde zuletzt erfolgreich gebaut und gestartet. Setze meine
> nächste konkrete Anforderung direkt um. Als erste Aufgabe führe den in
> `PROJECT_HANDOFF.md` beschriebenen AeroPS-Abgleich für alle Airports fort.
> Verwende die konkreten URLs ohne abschließenden Slash, halte Mac- und
> iPad-Ressourcen synchron und verifiziere anschließend Swift-Tests und
> Release-Audits aus dem README.

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
