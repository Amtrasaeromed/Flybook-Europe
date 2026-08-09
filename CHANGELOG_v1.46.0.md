# Flybook Europe 1.46.0

- Datenbestand auf 125 Flugplätze, 94 Ziele und 31 TechStops erweitert und
  erneut referenziell geprüft.
- Charter-, Reservierungs-, Reserve- und Tankzuzahlungsrechnung konsolidiert;
  37 reproduzierbare Rechenproben ergänzt.
- Wetterverkehr für schwache Mobilverbindungen priorisiert: kein Vollabruf beim
  Start, 30-Minuten-Caches, Zusammenführung identischer Abrufe, kleine
  Finder-Batches, priorisierte wartende Queue und globale Anfragegrenze.
- NOW!-Aktualisierung auf die aktuell ausgewählten Flugplätze beschränkt.
- Best Level rechnet jede 500-ft-Stufe von 2.000 bis 10.000 ft.
- ICON-Vertikalwind um 1000/975/950/925/900/850/800/700 hPa erweitert;
  Zwischenhöhen und Zwischenzeiten werden als Windvektor interpoliert.
- Drei Streckenwindpunkte werden in einer einzigen Modellanfrage gebündelt;
  alle 17 Best-Level-Höhen werden danach ohne weitere Downloads ausgewertet.
- Langfristwetter und Streckenrisiko fragen nur den benötigten Datumsbereich ab.
- Versions- und Persistenzprüfung sowie Live-Quellen- und Datenflussaudit
  ergänzt.
- Drei fehlerhaft mehrzeilig gespeicherte Quellen-URLs normalisiert.
