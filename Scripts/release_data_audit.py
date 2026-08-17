#!/usr/bin/env python3
"""Deterministic release audit for Flybook's bundled master data."""

from __future__ import annotations

import csv
import json
import math
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Sources" / "FlybookEurope" / "Resources"
ERRORS: list[str] = []
WARNINGS: list[str] = []
OPTIONAL_TRAILING_FIELDS = {
    "airports": {
        "fee_note",
        "fee_url",
        "aip_aero_url",
        "aip_aero_checked_at",
        "aip_aero_opening_hours",
        "aip_aero_frequencies",
    },
    "services": {
        "half_day_price", "full_day_price", "deposit_price", "price_currency"
    },
}


def error(message: str) -> None:
    ERRORS.append(message)


def warning(message: str) -> None:
    WARNINGS.append(message)


def table(name: str) -> tuple[list[str], list[dict[str, str]]]:
    path = RESOURCES / f"{name}.csv"
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)
        if reader.fieldnames is None:
            error(f"{name}.csv: Kopfzeile fehlt")
            return [], []
        for number, row in enumerate(rows, start=2):
            extras = row.get(None)
            if extras:
                error(f"{name}.csv:{number}: zusätzliche Spalten {extras!r}")
            optional = OPTIONAL_TRAILING_FIELDS.get(name, set())
            missing_required = [
                key for key, value in row.items()
                if key is not None and value is None and key not in optional
            ]
            for key in optional:
                if row.get(key) is None:
                    row[key] = ""
            if missing_required:
                error(f"{name}.csv:{number}: fehlende Spalten")
        return reader.fieldnames, rows


def unique(rows: list[dict[str, str]], field: str, name: str) -> None:
    counts = Counter(row[field].strip() for row in rows)
    duplicates = sorted(key for key, count in counts.items() if not key or count > 1)
    if duplicates:
        error(f"{name}: ungültige/doppelte Schlüssel in {field}: {duplicates}")


def number(row: dict[str, str], field: str, context: str) -> float | None:
    text = row[field].strip().replace(",", ".")
    try:
        value = float(text)
    except ValueError:
        error(f"{context}: {field} ist keine Zahl: {text!r}")
        return None
    if not math.isfinite(value):
        error(f"{context}: {field} ist nicht endlich")
        return None
    return value


def distance_nm(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    radius_nm = 3440.065
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return radius_nm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def main() -> int:
    _, airports = table("airports")
    _, destinations = table("destinations")
    _, features = table("features")
    _, fuels = table("fuels")
    _, prices = table("fuel_prices")
    _, services = table("services")
    _, techstops = table("techstops")

    unique(airports, "airport_id", "airports.csv")
    unique(airports, "icao", "airports.csv")
    unique(destinations, "destination_id", "destinations.csv")
    unique(features, "feature_id", "features.csv")
    unique(fuels, "fuel_id", "fuels.csv")
    unique(prices, "price_id", "fuel_prices.csv")
    unique(services, "service_id", "services.csv")
    unique(techstops, "techstop_id", "techstops.csv")

    airport_ids = {row["airport_id"] for row in airports}
    # EDFZ is the application's built-in homebase fallback and therefore may
    # have current service rows without a duplicated airports.csv master row.
    referenced_airport_ids = airport_ids | {"EDFZ"}
    for name, rows in (
        ("destinations", destinations),
        ("features", features),
        ("fuels", fuels),
        ("fuel_prices", prices),
        ("services", services),
        ("techstops", techstops),
    ):
        orphaned = sorted({row["airport_id"] for row in rows} - referenced_airport_ids)
        if orphaned:
            error(f"{name}.csv: verwaiste airport_id: {orphaned}")

    edfz_lat, edfz_lon = 49.9675, 8.1472
    maximum_distance_delta = 0.0
    for row in airports:
        context = f"Airport {row['icao']}"
        if not re.fullmatch(r"[A-Z0-9]{4}", row["icao"]):
            error(f"{context}: ungültiger ICAO-Code")
        lat = number(row, "latitude_wgs84", context)
        lon = number(row, "longitude_wgs84", context)
        elevation = number(row, "elevation_ft", context)
        stored_distance = number(row, "distance_edfz_nm", context)
        runway = number(row, "runway_length_m", context)
        width = number(row, "runway_width_m", context)
        lda = number(row, "runway_lda_m", context)
        if lat is not None and not -90 <= lat <= 90:
            error(f"{context}: Breitengrad außerhalb des Wertebereichs")
        if lon is not None and not -180 <= lon <= 180:
            error(f"{context}: Längengrad außerhalb des Wertebereichs")
        if elevation is not None and not -1500 <= elevation <= 20_000:
            error(f"{context}: unplausible Höhe {elevation}")
        if runway is not None and not 250 <= runway <= 6_000:
            error(f"{context}: unplausible Pistenlänge {runway}")
        if width is not None and not 5 <= width <= 100:
            error(f"{context}: unplausible Pistenbreite {width}")
        if lda is not None and runway is not None and (lda <= 0 or lda > runway):
            error(f"{context}: LDA {lda} liegt nicht in 1…{runway}")
        try:
            ZoneInfo(row["timezone_identifier"])
        except ZoneInfoNotFoundError:
            error(f"{context}: ungültige Zeitzone {row['timezone_identifier']!r}")
        if None not in (lat, lon, stored_distance):
            delta = abs(distance_nm(edfz_lat, edfz_lon, lat, lon) - stored_distance)
            maximum_distance_delta = max(maximum_distance_delta, delta)
            if delta > 3:
                error(f"{context}: EDFZ-Distanz weicht um {delta:.1f} NM ab")

    expected_features = {
        "techstop", "breakfast", "city", "beach", "lake", "mountain", "wellness"
    }
    by_airport: dict[str, set[str]] = defaultdict(set)
    for row in features:
        by_airport[row["airport_id"]].add(row["feature_type"])
        status = row["status_raw"].strip().casefold()
        if status not in {"ja", "nein", "grenzfall"}:
            error(f"Feature {row['feature_id']}: ungültiger Status {row['status_raw']!r}")
        if row["feature_type"] == "beach" and status == "ja":
            context = f"Strandmerkmal {row['feature_id']}"
            mode = row["recommended_mode"].strip().casefold().replace("ß", "ss")
            if mode not in {"fahrrad", "zu fuss", "e-roller"}:
                error(
                    f"{context}: Zugang muss Fahrrad, zu Fuß oder E-Roller sein, "
                    f"nicht {row['recommended_mode']!r}"
                )
            minutes = number(row, "recommended_minutes", context)
            if minutes is not None and not 0 < minutes <= 45:
                error(f"{context}: Zugang dauert {minutes:g} Minuten statt maximal 45")
    for airport_id in sorted(airport_ids):
        missing = expected_features - by_airport[airport_id]
        extra = by_airport[airport_id] - expected_features
        if missing or extra:
            error(f"Features {airport_id}: fehlen={sorted(missing)}, extra={sorted(extra)}")

    destination_by_airport = {row["airport_id"]: row for row in destinations}
    status_fields = {
        "city": "city_status",
        "beach": "beach_status",
        "lake": "lake_status",
        "mountain": "mountain_status",
        "wellness": "wellness_status",
    }
    feature_lookup = {(row["airport_id"], row["feature_type"]): row for row in features}
    for airport_id, destination in destination_by_airport.items():
        for feature_type, field in status_fields.items():
            expected = destination[field].strip().casefold() == "ja"
            actual = feature_lookup.get((airport_id, feature_type), {}).get("status_raw", "").strip().casefold() == "ja"
            if expected != actual:
                error(f"{airport_id}: destinations.{field} und Feature {feature_type} widersprechen sich")

    price_keys = {(row["airport_id"], row["fuel_type"]): row for row in prices}
    for row in prices:
        value = number(row, "price_eur_per_litre", f"Preis {row['price_id']}")
        if value is not None and not 0.5 <= value <= 10:
            error(f"Preis {row['price_id']}: unplausibel {value}")
    for row in fuels:
        availability = row["availability_raw"].strip().casefold()
        if availability == "ja" and (row["airport_id"], row["fuel_type"]) not in price_keys:
            # Raw availability is retained as a source hint. DestinationStore
            # deliberately normalizes it to "?" unless a verified price exists.
            warning(f"Fuel {row['fuel_id']}: Rohhinweis 'Ja' wird ohne Preis als '?' angezeigt")

    data = json.loads((RESOURCES / "destination_data.json").read_text(encoding="utf-8"))
    unknown_json = sorted(set(data) - {row["icao"] for row in airports})
    if unknown_json:
        warning(f"destination_data.json: inaktive Reserve-ICAOs {unknown_json}")

    print(f"Airports: {len(airports)}")
    print(f"Destinations: {len(destinations)}")
    print(f"Features: {len(features)}")
    print(f"Fuels: {len(fuels)}")
    print(f"Fuel prices: {len(prices)}")
    print(f"Services: {len(services)}")
    print(f"Techstops: {len(techstops)}")
    print(f"Max. Distanzabweichung: {maximum_distance_delta:.2f} NM")
    for message in WARNINGS:
        print(f"WARNUNG: {message}")
    for message in ERRORS:
        print(f"FEHLER: {message}")
    print("ERGEBNIS:", "PASS" if not ERRORS else f"FAIL ({len(ERRORS)} Fehler)")
    return 0 if not ERRORS else 1


if __name__ == "__main__":
    sys.exit(main())
