# BUILD FIX v1.43.1

## Wettermodell-Hierarchie der 5-Tages-Übersicht

Die Farbcodierungen und Windschwellen bleiben unverändert.

Behoben wurde die bisherige kalenderbasierte Modellwahl:

- ICON-D2 wurde zuvor nur für die ersten zwei angezeigten Kalendertage verwendet.
- Dadurch konnte derselbe Zeitpunkt in der Flugplanung mit ICON-D2, in der 5-Tages-Übersicht aber bereits mit ICON-EU erscheinen.

Ab v1.43.1 gilt für jeden einzelnen Stundenwert:

1. ICON-D2, solange für die konkrete Stunde tatsächlich Daten vorhanden sind.
2. ICON-EU für Stunden ohne verfügbare ICON-D2-Daten.
3. ICON Seamless, falls auch ICON-EU für die Stunde keinen Wert liefert.
4. Best Match als letzte Rückfallebene.

Ein teilweise von ICON-D2 abgedeckter Tag wird stundenweise zusammengesetzt. Die App schaltet daher nicht mehr einen kompletten Kalendertag vorzeitig auf ICON-EU um.

Auch die punktgenauen Werte für Landung und Rückflug verwenden ICON-D2 nur dann, wenn der Zielzeitpunkt innerhalb der tatsächlich gelieferten Daten liegt. Ein außerhalb des Modellhorizonts liegender Zeitpunkt wird nicht mehr fälschlich auf die letzte verfügbare D2-Stunde gezogen.
