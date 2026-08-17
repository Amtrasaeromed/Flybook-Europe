# Flybook Europe 1.5.0

- Flugplanung, Charter-, Kraftstoff-, Zoll-, Gewichts-, Start-/Landestrecken-
  und Zeitberechnungen mit 206 Swift-Tests und 37 unabhängigen
  Release-Rechenprüfungen verifiziert.
- Direkte Planungs-Ceiling aus DWD ICON-D2/ICON-EU, gekennzeichneter
  DWD-MOSMIX-Fallback für BKN/OVC und getrenntes validiertes
  Nebel-/Tiefwolkenmodell für die 5-Tages-Anzeige.
- Flybrief mit Teilstreckenwetter, Höhenwinden, Alternates, Runwayperformance
  und bestätigtem Fuelplan als ruhige, vollständig auf A4 passende Tabellen.
- Tankkalkulator mit rückwärts gerechneten Mindestbeständen, bis zu zwei
  Refueling-Stops, konservativer Rundung und Übergabe an die Charterrechnung.
- Gemeinsamer Netzwerkpfad für macOS und iPad: globale Parallelitätsgrenze,
  Prioritäten, Caches und zentraler Open-Meteo-Rate-Limit-Schutz.
- iPad bindet die vier Airport-/Feature-/Fuel-Masterdateien direkt aus der
  einzigen macOS-Datenquelle ein; unbenutzte Schattenkopien wurden entfernt.
- AIP:Aero ist als zusätzliche Flughafenquelle für 139 von 144 Plätzen mit
  Detailseite, UTC-Betriebszeiten, Frequenzen und veröffentlichten
  Kraftstoffangaben integriert. Der vollständige Abgleich ist reproduzierbar
  und als CSV-Audit dokumentiert.
- EDTG verwendet 2,99 EUR/l AVGAS, 2,36 EUR/l MOGAS und 2,49 EUR/l Jet A-1.
  Eine Quelle mit 2026er Bestätigungsdatum, aber tatsächlichem Datenstand 2020,
  wurde aus dem Laufzeitabruf entfernt. Betreiberpreise haben bei vergleichbar
  aktuellem Stand Vorrang vor AIP:Aero-/AeroPS-Indexwerten.
- Vollständiger Release-Audit für Daten, Quellen, Datenfluss, Persistenz,
  macOS und den signierten iPad-Gerätebuild.
