# Flybook Europe v1.47.0 – Integritätsprüfung

**Prüfdatum:** 13. August 2026
**Ergebnis:** PASS für Datenimport, Referenzen, Swift-Loader und UK-Regression.

## Datenbestand

| Prüfung | Ergebnis |
|---|---:|
| Flugplätze / eindeutige IDs | 133 / 133 |
| Touristische Zielprofile | 100 |
| TechStop-Profile | 31 |
| Merkmalszeilen | 931, exakt 7 je Platz |
| Services | 378 |
| Kraftstoffzeilen | 495 |
| Preiszeilen | 36 |
| Doppelte/verwaiste Schlüssel | 0 |
| Max. EDFZ-Distanzabweichung | 1,92 NM |

Aktive Ja-Merkmale: TechStop 33, Frühstück 9, Stadt 9, Strand/Meer 56,
See/Natur 38, Berge/Wandern 27 und Wellness 42.

## UK-Merge

Alle neun ICAOs EGHN, EGHJ, EGHF, EGKA, EGMD, EGHQ, EGHR, EGKH und EGHA
werden vom produktiven `DestinationStore` geladen und zeigen POE „Ja“.
Bembridge und Headcorn behaupten keine unbestätigte Kraftstoffsorte.

Die touristischen UK-Merkmale wurden gegen offizielle Tourismus-, Naturpark-
und Betreiberseiten geprüft. Alle neun Plätze haben ein konkretes
See-/Naturziel und ein anerkanntes Spa innerhalb von 60 Minuten. Strand/Meer
ist bei acht Plätzen innerhalb von 45 Minuten erreichbar; Compton Abbas bleibt
bewusst „Nein“. Keiner der neun Plätze wird als echtes Bergziel geführt.

Operative Flugplanung muss weiterhin aktuelle AIP, NOTAM, GAR-/POE-Verfahren,
Betriebszeiten, PPR und Kraftstoffverfügbarkeit unmittelbar vor dem Flug
bestätigen.
