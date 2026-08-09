# Flybook Europe für iPad

Dies ist das neue, native iPadOS-Projekt. Die bestehende macOS-Anwendung im
übergeordneten Projekt bleibt während der Migration als Referenz und
funktionsfähige Version erhalten.

## Erster Migrationsstand

- natives SwiftUI-App-Target für iPadOS 17 oder neuer
- festes SwiftUI-Vollbilddashboard als iPad-Grundlayout
- aktueller lokaler Flybook-Flugplatzbestand aus `airports.csv`
- Flugplatzsuche und erste responsive Detailansicht
- vorhandenes Flybook-App-Symbol und Farbwelt
- Hochformat als feste Vollbildansicht ohne vertikales Seitenscrolling
- erstes Hauptdashboard mit Oneway-Flugplanung und Wetterbereichen
- Hauptseite mit Zielnavigation, Airport-/Kraftstoffdaten, Oneway-Planung,
  Charterkalkulation und fester Symbol-Menüleiste
- Kraftstoffpreise mit EDFZ-Referenzdifferenz und lokalem Datenstand
- Flugplanung mit ICAO-Direkteingabe, Vorschlägen, Zieltausch und Levelwahl

## Öffnen und starten

1. `Flybook-iPad.xcodeproj` in Xcode öffnen.
2. Das Scheme `Flybook-iPad` auswählen.
3. Einen iPad-Simulator oder ein angeschlossenes iPad als Ziel wählen.
4. Mit `⌘R` starten.

Für den Simulator ist keine Signierung erforderlich. Für ein echtes iPad muss
in Xcode unter **Signing & Capabilities** das eigene Apple-Developer-Team
ausgewählt werden.

## Vorgesehene Migration

1. gemeinsame plattformneutrale Modelle und Berechnungen
2. Wetterabruf und Cache ohne macOS-Prozessabhängigkeiten
3. Flugplanung, Runway/Wind und Alternates
4. Charterkalkulation und Setup
5. iPhone-Layout, Gerätesignierung und TestFlight
