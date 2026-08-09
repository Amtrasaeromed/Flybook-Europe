# Übergabe an einen anderen Account

Dieses Archiv enthält den vollständigen, geprüften Flybook-Europe-Stand
v1.46.0: Swift-Quellcode, Package-Manifest, Tests, Prüfskripte, sämtliche
CSV-/JSON-Daten, Assets sowie Projekt- und Release-Dokumentation.

## Projekt öffnen

1. ZIP vollständig entpacken.
2. Den Ordner `Flybook-Europe-v1.46.0` lokal ablegen.
3. `Package.swift` in Xcode öffnen.
4. Zunächst auf macOS `swift build` beziehungsweise das Produkt
   **Flybook Europe** ausführen.
5. Für iPad/iPhone ein iOS-/iPadOS-App-Target mit derselben fachlichen
   Quellbasis anlegen. Die aktuelle Oberfläche ist noch das geprüfte
   macOS-SwiftUI-Target; das Archiv ist die Ausgangsbasis für die Portierung,
   keine bereits signierte iOS-App.

## Lokale Flybook-Profile

`Transfer/UserDefaults` enthält zusätzlich die auf diesem Mac gespeicherten
Flybook-Einstellungen und Benutzerprofile. Sie gehören nicht zu den
CSV-Masterdaten und würden bei einem reinen Quellcode-Transfer fehlen.

Auf einem anderen Mac bei geschlossener Flybook-App importieren:

```sh
defaults import de.flybook.europe \
  Transfer/UserDefaults/de.flybook.europe.plist
defaults import de.flybook.europe.user-profiles \
  Transfer/UserDefaults/de.flybook.europe.user-profiles.plist
```

Für iOS/iPadOS dienen diese Property Lists als Migrationsquelle. Wegen der
App-Sandbox werden sie dort nicht per `defaults` importiert; die Portierung
soll die relevanten Profilwerte beim ersten Start in den neuen App-Container
übernehmen.

## Lokale Daten und Offline-Caches

`Transfer/Application Support` enthält außerdem die aktuellen lokalen
Flybook-Daten: Wetter- und Kraftstoff-Caches sowie bereits geladene
Luftbild-Kacheln. Auf einem anderen Mac können sie bei geschlossener App
übernommen werden:

```sh
mkdir -p "$HOME/Library/Application Support"
ditto "Transfer/Application Support/Flybook Europe" \
  "$HOME/Library/Application Support/Flybook Europe"
ditto "Transfer/Application Support/FlybookEurope" \
  "$HOME/Library/Application Support/FlybookEurope"
```

Diese Caches sichern den vorhandenen Offline-Stand. Zeitabhängige Wetter- und
Kraftstoffdaten werden von Flybook nach Ablauf ihrer Gültigkeit wieder aus den
Live-Quellen aktualisiert.

## Prüfung

Die Prüfsummen aller übergebenen Dateien stehen in
`ARCHIVE_MANIFEST.sha256`. Die Release-Prüfbefehle sind in `README.md`
dokumentiert. Build-, Daten-, Quellen-, Rechen-, Datenfluss- und
Persistenzaudits waren bei Erstellung des Archivs erfolgreich.
