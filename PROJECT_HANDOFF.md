# Flybook Europe – Übergabe an Codex

Dieses Dokument überträgt den Arbeitskontext zwischen den beiden Macs. Vor der Weiterarbeit immer zuerst `main` von GitHub aktualisieren und anschließend diese Datei lesen.

## Projekt

- Native macOS-App mit SwiftUI und Swift Package Manager
- Hauptbranch: `main`
- Repository: `https://github.com/Amtrasaeromed/Flybook-Europe`
- Build-Prüfung: `swift build`
- Das bestehende Design soll beibehalten und schrittweise erweitert werden.

## Aktueller Funktionsstand

- Flugplanung für Hin-/Rückflug, One-Way und Multi-Stop
- Standardtermine, Reset, Wetteraktualisierung und Umkehren von Start/Ziel
- Multi-Stop mit zwei Legs, gemeinsamer Datumslogik und editierbarer Abflugzeit des zweiten Legs
- Kartenroute mit Haus für Start, Fähnchen für Ziel und Zwischenstopp
- Wetterkarten für Abflug und Ankunft einschließlich Pistenempfehlungen
- Civil Dawn, Sunrise, Sunset und Civil Dusk in den kleinen Wetterkarten
- Reiseflughöhen einschließlich 2.500 ft; Best Level nur FL025 bis FL100
- 5-Tages-Wetter mit Kategorienbalken für 05–11, 11–17 und 17–23 Uhr
- Zwölfteiliger Dauerwindbalken von 08–20 Uhr in 3-kt-Farbstufen
- Windsack im 5-Tages-Wetter bei Dauerwind über 15 kt oder Böen über 20 kt
- Gelbe/rote Querwindwarnung an vorhandenen Pistenempfehlungen
- Charterkalkulation einschließlich One-Way und nicht verbrauchter Hinflugreserve
- Reservierungsmanager und EU-/US-Zeit- und Einheitendarstellung
- Juist/EDWJ und weitere Flugplätze in den Zieldaten

## Pisten-Querwindwarnung

Die Querwindkomponente wird aus Windrichtung und Kurs der empfohlenen Piste getrennt für Dauerwind und Böen berechnet. Die strengere Farbe gewinnt.

- Gelb: Dauerwind-Querkomponente ab 10 kt bis einschließlich 15 kt oder Böen-Querkomponente über 15 kt
- Rot: Dauerwind-Querkomponente über 15 kt oder Böen-Querkomponente über 30 kt

## Arbeitsablauf auf jedem Mac

1. Vor Arbeitsbeginn den aktuellen Stand von `origin/main` holen.
2. Änderungen implementieren und mit `swift build` prüfen.
3. Vor dem Mac-Wechsel alle Projektänderungen committen und zu `origin/main` pushen.
4. Nicht gleichzeitig auf beiden Macs dieselben Dateien bearbeiten.

## Startanweisung für einen neuen Codex-Task

> Öffne das Flybook-Europe-Projekt, hole den aktuellen Stand von `origin/main`, lies `PROJECT_HANDOFF.md` vollständig und arbeite auf dieser Grundlage weiter. Bewahre das bestehende SwiftUI-Design und prüfe Änderungen mit `swift build`.
