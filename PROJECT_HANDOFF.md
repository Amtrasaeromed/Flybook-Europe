# Flybook Europe – Übergabe v1.46.0

## Produktstand

- Native SwiftUI-/SwiftPM-App für macOS 13 oder neuer
- Bundle-ID `de.flybook.europe`
- 125 Flugplätze, 94 Ziele, 31 TechStops
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
