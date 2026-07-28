# Flybook Image Studio

## Start

Doppelklick auf **Flybook Image Studio.command**. Beim ersten Start kann macOS wegen eines aus dem Internet geladenen Skripts nachfragen. In diesem Fall Rechtsklick → Öffnen.

## Bedienung

1. Einen OpenAI-API-Schlüssel in das obere Feld kopieren.
2. **Schlüssel speichern** anklicken. Er wird ausschließlich im persönlichen macOS-Schlüsselbund unter `de.flybook-europe.image-studio` gespeichert.
3. **Alle Bilder erzeugen** startet den bestehenden Python-Batchgenerator für 35 Ziele und je drei Kandidaten.
4. Pro Ziel einen Kandidaten anklicken. Die Auswahl wird in `ImageProduction/selections.csv` gespeichert.
5. Sobald alle 35 Ziele freigegeben sind, kopiert **35 Favoriten übernehmen** die gewählten Dateien nach `Sources/FlybookEurope/Resources/regions/`.

Die Bilderzeugung kann gestoppt und später fortgesetzt werden. Bereits vorhandene Kandidaten werden nicht erneut berechnet.

## Voraussetzungen

- macOS 13 oder neuer
- Xcode Command Line Tools (`xcode-select --install`), falls Swift noch nicht verfügbar ist
- Python 3
- OpenAI-API-Konto mit aktivierter Abrechnung bzw. verfügbarem Guthaben
