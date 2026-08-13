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

Aktive Merkmale: TechStop 33, Frühstück 9, Stadt 9, Strand/Meer 54,
See/Natur 30, Berge/Wandern 28 und Wellness 33.

## UK-Merge

Alle neun ICAOs EGHN, EGHJ, EGHF, EGKA, EGMD, EGHQ, EGHR, EGKH und EGHA
werden vom produktiven `DestinationStore` geladen und zeigen POE „Ja“.
Bembridge und Headcorn behaupten keine unbestätigte Kraftstoffsorte.

Operative Flugplanung muss weiterhin aktuelle AIP, NOTAM, GAR-/POE-Verfahren,
Betriebszeiten, PPR und Kraftstoffverfügbarkeit unmittelbar vor dem Flug
bestätigen.
