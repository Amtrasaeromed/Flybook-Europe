# Karten und Flughafen-Luftbilder

Die Zielseite erzeugt beide Darstellungen nativ mit MapKit:

- links eine Europakarte mit markiertem Ziel
- rechts ein eng gezoomtes Satellitenbild des jeweiligen Flugplatzes

Die Luftbilder werden nicht im Projekt gespeichert. Die rechte Karte lädt
öffentliche Kacheln aus Esri World Imagery; deshalb ist für die
Satellitenansicht eine Internetverbindung erforderlich. Ein API-Schlüssel ist
nicht notwendig. Die erforderliche Quellenangabe wird direkt im Luftbild
angezeigt.

Die Koordinaten aller 35 ICAO-Ziele stehen in `destination_data.json`. Die
ergänzten Flughafenkoordinaten stammen aus dem Public-Domain-Datensatz von
OurAirports:

`https://ourairports.com/data/`

Der bisherige Ordner `Resources/regions/` bleibt aus Gründen der
Rückwärtskompatibilität bestehen, wird in der aktuellen Zielansicht aber nicht
mehr für das rechte Bildfeld verwendet.
