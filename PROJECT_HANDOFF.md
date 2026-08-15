# Flybook Europe – Übergabe v1.47.0

## Sofortübergabe (15. August 2026)

- Arbeitsverzeichnis: `/Users/stephan/Documents/ChatGPT/Flybook`
- Branch: `codex/ipad-migration`
- Git-Stand: alle Änderungen auf `codex/ipad-migration` versioniert und für
  die Übergabe an einen weiteren Account vorbereitet
- Version: `1.47.0`
- Die macOS-App wurde erfolgreich mit
  `./Flybook\ Europe\ starten.command` gebaut, lokal signiert, unter
  `~/Applications/Flybook Europe.app` aktualisiert und geöffnet.
- Der letzte Build und die vollständige Swift-Test-Suite waren erfolgreich.
- Der Destination Finder behält Ziele bei unvollständigem Streckenwetter als
  Treffer und kennzeichnet sie als nicht vollständig geprüft. Alpenföhn wird
  entlang der relevanten West-, Zentral- und Ostachsen bewertet.
- Mobilitätsdaten unterscheiden Fahrrad, Mietwagen, app2drive, Bahn und Bus.
  Bahn-/Busnähe bedeutet höchstens 500 m und mehrfach täglichen Verkehr; nicht
  eindeutig belegte Angebote bleiben als `?` gekennzeichnet.
- Tourismusmerkmale sowie die POE-/Zolltauglichkeit der Schweizer und
  britischen Ziele wurden redaktionell nachgeschärft.

## Einstieg für den nächsten Account

Diesen Text als erste Aufgabe verwenden:

> Arbeite im bestehenden Projekt `/Users/stephan/Documents/ChatGPT/Flybook`
> weiter. Lies zuerst `PROJECT_HANDOFF.md` und `README.md`, prüfe danach
> `git status` und den aktuellen Branch. Bewahre alle vorhandenen Änderungen.
> Flybook v1.47.0 wurde zuletzt erfolgreich gebaut und gestartet. Setze meine
> nächste konkrete Anforderung direkt um und verifiziere sie mit den passenden
> Swift-Tests beziehungsweise den Release-Audits aus dem README.

## Produktstand

- Native SwiftUI-/SwiftPM-App für macOS 13 oder neuer
- Bundle-ID `de.flybook.europe`
- 140 Flugplätze, 106 Ziele, 33 TechStops
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
