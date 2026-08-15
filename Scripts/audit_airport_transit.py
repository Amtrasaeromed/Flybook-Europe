#!/usr/bin/env python3
"""Audit scheduled public transport within 500 m of Flybook destinations.

The script is deliberately read-only: it prints compact CSV-compatible audit
records and never modifies the bundled Flybook data.
"""

from __future__ import annotations

import csv
import io
import json
import math
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESOURCE_DIR = ROOT / "Sources" / "FlybookEurope" / "Resources"
API_URL = "https://api.transitous.org/api/v6/stoptimes"
USER_AGENT = (
    "Flybook-Europe-data-audit/1.0 "
    "(https://github.com/Amtrasaeromed/Flybook-Europe)"
)
AUDIT_START = "2026-08-22T04:00:00Z"
AUDIT_END = "2026-08-23T04:00:00Z"
RAIL_MODES = "HIGHSPEED_RAIL,LONG_DISTANCE,REGIONAL_RAIL,SUBURBAN,SUBWAY,TRAM"
CHECKED_AT = "2026-08-15"


def read_rows(name: str) -> list[dict[str, str]]:
    with (RESOURCE_DIR / name).open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def distance_m(lat1: float, lon1: float, lat2: float, lon2: float) -> int:
    radius = 6_371_000.0
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)
    value = (
        math.sin(delta_phi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2) ** 2
    )
    return round(radius * 2 * math.atan2(math.sqrt(value), math.sqrt(1 - value)))


def fetch_departures(lat: float, lon: float, modes: str) -> list[dict]:
    query = urllib.parse.urlencode(
        {
            "center": f"{lat},{lon}",
            "radius": "500",
            "exactRadius": "true",
            "time": AUDIT_START,
            "direction": "LATER",
            "mode": modes,
            "n": "3",
            "fetchStops": "false",
            "withAlerts": "false",
        }
    )
    request = urllib.request.Request(
        f"{API_URL}?{query}",
        headers={"User-Agent": USER_AGENT},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response).get("stopTimes", [])


def audit_mode(
    airport: dict[str, str], modes: str
) -> tuple[str, str, int | None, int, str]:
    lat = float(airport["latitude_wgs84"])
    lon = float(airport["longitude_wgs84"])
    try:
        departures = fetch_departures(lat, lon, modes)
    except Exception as error:  # A failed source check is unknown, never "No".
        return "?", "", None, 0, f"API-Fehler: {type(error).__name__}"

    same_day = []
    for departure in departures:
        place = departure.get("place", {})
        instant = place.get("scheduledDeparture") or place.get("departure") or ""
        if AUDIT_START <= instant < AUDIT_END:
            same_day.append(departure)

    if not same_day:
        return "?", "", None, 0, "Keine ausreichend belastbare Fahrplanauskunft"

    nearest = min(
        same_day,
        key=lambda item: distance_m(
            lat,
            lon,
            float(item.get("place", {}).get("lat", lat)),
            float(item.get("place", {}).get("lon", lon)),
        ),
    )
    place = nearest.get("place", {})
    distance = distance_m(
        lat,
        lon,
        float(place.get("lat", lat)),
        float(place.get("lon", lon)),
    )
    stop_name = str(place.get("name", "")).strip()
    feed = str(nearest.get("source", "")).split("/", 1)[0]
    status = "Ja" if len(same_day) >= 3 and distance <= 500 else "?"
    return status, stop_name, distance, len(same_day), feed


def main() -> int:
    if len(sys.argv) == 3 and sys.argv[1] == "--render-services-patch":
        return render_services_patch(Path(sys.argv[2]))

    destination_ids = {row["airport_id"] for row in read_rows("destinations.csv")}
    airports = [
        row for row in read_rows("airports.csv") if row["airport_id"] in destination_ids
    ]
    airports.sort(key=lambda row: row["airport_id"])

    writer = csv.writer(sys.stdout, lineterminator="\n")
    writer.writerow(
        [
            "airport_id",
            "mode",
            "status",
            "stop_name",
            "distance_m",
            "departures",
            "feed_or_note",
        ]
    )
    for index, airport in enumerate(airports, start=1):
        for label, modes in (("rail", RAIL_MODES), ("bus", "BUS")):
            status, stop, distance, departures, feed = audit_mode(airport, modes)
            writer.writerow(
                [
                    airport["airport_id"],
                    label,
                    status,
                    stop,
                    "" if distance is None else distance,
                    departures,
                    feed,
                ]
            )
            sys.stdout.flush()
            time.sleep(0.12)
        print(f"# {index}/{len(airports)}", file=sys.stderr, flush=True)
    return 0


def render_services_patch(audit_path: Path) -> int:
    """Render an apply_patch payload; never edit the resource directly."""
    with audit_path.open(encoding="utf-8", newline="") as handle:
        audit_rows = list(csv.DictReader(handle))

    output = io.StringIO()
    writer = csv.writer(output, lineterminator="\n")
    for audit in audit_rows:
        airport = audit["airport_id"]
        mode = audit["mode"]
        status = audit["status"]
        stop = audit["stop_name"]
        distance = audit["distance_m"]
        departures = int(audit["departures"] or 0)
        service_type = "rail_transit" if mode == "rail" else "bus_transit"
        service_class = "Bahnanschluss" if mode == "rail" else "Busanschluss"

        if status == "Ja":
            availability = (
                f"Ja – {stop}, {distance} m, mindestens 3 Abfahrten täglich"
            )
            description = (
                "Haltestelle höchstens 500 m vom Flugplatzbezugspunkt; "
                "mehrere tägliche Verbindungen im Fahrplan belegt"
            )
            opening_hours = "Mehrmals täglich am Prüftag bestätigt"
            confidence = "hoch"
        elif stop:
            availability = (
                f"? – {stop} in {distance} m, aber weniger als 3 Fahrten belegt"
            )
            description = "Haltestelle räumlich gefunden; Bedienung nicht ausreichend belegt"
            opening_hours = ""
            confidence = "mittel"
        else:
            availability = "? – keine belastbare Fahrplanbestätigung im 500-m-Radius"
            description = "Fehlende Fahrplandaten sind kein Beleg für ein Nein"
            opening_hours = ""
            confidence = "mittel"

        writer.writerow(
            [
                "1.2",
                f"{airport}:{service_type}",
                airport,
                service_type,
                availability,
                stop,
                service_class,
                description,
                f"{distance} m vom Flugplatzbezugspunkt" if distance else "",
                opening_hours,
                "",
                "",
                confidence,
                (
                    f"Prüffenster 22.08.2026; {departures} Abfahrten im "
                    "24-Stunden-Fenster. Fahrplan vor dem Flug erneut prüfen."
                ),
                "https://api.transitous.org/api/",
                "https://transitous.org/sources/",
                CHECKED_AT,
            ]
        )

    services_path = RESOURCE_DIR / "services.csv"
    last_line = services_path.read_text(encoding="utf-8").splitlines()[-1]
    print("*** Begin Patch")
    print("*** Update File: Sources/FlybookEurope/Resources/services.csv")
    print("@@")
    print(f" {last_line}")
    for line in output.getvalue().splitlines():
        print(f"+{line}")
    print("*** End Patch")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
