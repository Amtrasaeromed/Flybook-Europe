#!/usr/bin/env python3
"""Audit AIP:Aero airport pages and merge corroborated public data.

AIP:Aero exposes each aerodrome as schema.org ``Airport`` JSON-LD.  This
script deliberately treats the site as a secondary index: source links,
published opening hours, frequencies, fuel availability and explicit pump
prices are imported, while coordinate/runway/elevation differences are only
reported for review and never overwrite the curated airport master.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import html
import json
import math
import re
import ssl
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Sources" / "FlybookEurope" / "Resources"
CHECKED_AT = dt.date.today().isoformat()
AUDIT_PATH = ROOT / f"AIP_AERO_AUDIT_{CHECKED_AT}.csv"
VERSION = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
USER_AGENT = f"FlybookEurope/{VERSION} AIP-Aero-audit"
CONTEXT = ssl.create_default_context()

# AIP:Aero documents these public page patterns in /llms.txt.  The database
# contains VFR-oriented destinations; France uses its national "aeroports"
# collection, while Guernsey and Jersey are published in the UK collection.
COUNTRY_PATHS = {
    "AT": "at/en/vfr",
    "BE": "be/vfr",
    "CH": "ch/en/vfr",
    "CZ": "cz/en/vfr",
    "DE": "de/en/vfr",
    "DK": "dk/en/vfr",
    "FR": "fr/en/aeroports",
    "GB": "uk/vfr",
    "GG": "uk/vfr",
    "HR": "hr/en/vfr",
    "IT": "it/en/vfr",
    "JE": "uk/vfr",
    "NL": "nl/en/vfr",
    "PL": "pl/en/vfr",
    "SE": "se/en/vfr",
    "SI": "si/en/vfr",
}

PATH_OVERRIDES = {
    # Hyères is listed in AIP:Aero's French military collection rather than
    # the civil airports collection.
    "LFTH": "fr/en/military",
}

LD_JSON_PATTERN = re.compile(
    r'<script[^>]*type=["\']application/ld\+json["\'][^>]*>(.*?)</script>',
    re.IGNORECASE | re.DOTALL,
)
TAG_PATTERN = re.compile(r"<[^>]+>")
RUNWAY_METRIC_PATTERN = re.compile(r"\((\d+)\s*[×x]\s*(\d+)\s*m\)")
PRICE_PATTERN = re.compile(
    r"(?P<currency>€|EUR|CHF|£|GBP)\s*(?P<price>[0-9]+(?:[.,][0-9]+)?)\s*/l",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class AIPAirport:
    icao: str
    url: str
    status: str
    name: str = ""
    latitude: float | None = None
    longitude: float | None = None
    elevation_ft: int | None = None
    longest_runway_m: int | None = None
    ppr: str = ""
    fuel_summary: str = ""
    prices: tuple[tuple[str, str, str, str], ...] = ()
    price_checked_at: str = ""
    opening_hours: str = ""
    frequencies: str = ""
    restaurant: str = ""
    error: str = ""


def read_table(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise RuntimeError(f"CSV header missing: {path}")
        return list(reader.fieldnames), list(reader)


def write_table(
    path: Path,
    fieldnames: list[str],
    rows: list[dict[str, str]],
) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def page_url(icao: str, country: str) -> str | None:
    path = PATH_OVERRIDES.get(icao.upper(), COUNTRY_PATHS.get(country.upper()))
    if path is None:
        return None
    return f"https://aip.aero/{path}/?{icao.upper()}"


def normalized_text(raw_html: str) -> str:
    return " ".join(
        html.unescape(TAG_PATTERN.sub(" ", raw_html)).replace("\xa0", " ").split()
    )


def airport_json(raw_html: str, icao: str) -> dict[str, object] | None:
    for raw in LD_JSON_PATTERN.findall(raw_html):
        try:
            candidate = json.loads(html.unescape(raw))
        except (json.JSONDecodeError, TypeError):
            continue
        if not isinstance(candidate, dict):
            continue
        airport_type = candidate.get("@type")
        is_airport = airport_type == "Airport" or (
            isinstance(airport_type, list) and "Airport" in airport_type
        )
        if is_airport and str(candidate.get("icaoCode", "")).upper() == icao:
            return candidate
    return None


def properties(airport: dict[str, object]) -> dict[str, str]:
    result: dict[str, str] = {}
    raw_properties = airport.get("additionalProperty", [])
    if not isinstance(raw_properties, list):
        return result
    for item in raw_properties:
        if not isinstance(item, dict):
            continue
        name = str(item.get("name", "")).strip()
        value = str(item.get("value", "")).strip()
        if name and value:
            result[name] = value
    return result


def parse_elevation_ft(value: str) -> int | None:
    match = re.search(r"(-?[0-9][0-9,]*)\s*ft\b", value, re.IGNORECASE)
    if match is None:
        return None
    return int(match.group(1).replace(",", ""))


def fuel_type_for_price(label: str) -> str | None:
    compact = re.sub(r"[^a-z0-9]+", "", label.casefold())
    if "ul91" in compact:
        return "UL91"
    if "avgas" in compact and ("ul94" in compact or "94ul" in compact):
        return "AVGAS_UL94"
    if "avgas" in compact:
        return "AVGAS"
    if "mogas" in compact or "carpetrol" in compact or "superplus" in compact:
        return "MOGAS_SUPER"
    if "jeta1" in compact or "jetfuel" in compact:
        return "JET_A1"
    return None


def currency_code(symbol: str) -> str:
    return {
        "€": "EUR",
        "EUR": "EUR",
        "CHF": "CHF",
        "£": "GBP",
        "GBP": "GBP",
    }.get(symbol.upper(), symbol.upper())


def extract_prices(props: dict[str, str]) -> tuple[tuple[str, str, str, str], ...]:
    result: list[tuple[str, str, str, str]] = []
    for name, value in props.items():
        if not name.casefold().startswith("fuel price"):
            continue
        fuel_type = fuel_type_for_price(name)
        match = PRICE_PATTERN.search(value)
        if fuel_type is None or match is None:
            continue
        result.append(
            (
                fuel_type,
                name.removeprefix("Fuel price ").strip(),
                match.group("price").replace(",", "."),
                currency_code(match.group("currency")),
            )
        )
    return tuple(sorted(result))


def parse_price_checked_at(page_text: str) -> str:
    match = re.search(
        r"Fuel prices\s+Last updated\s+([A-Z][a-z]+\s+[0-9]{1,2},\s+[0-9]{4})",
        page_text,
    )
    if match is None:
        return CHECKED_AT
    try:
        return dt.datetime.strptime(match.group(1), "%B %d, %Y").date().isoformat()
    except ValueError:
        return CHECKED_AT


def day_name(value: str) -> str:
    return value.rsplit("/", 1)[-1][:3]


def extract_opening_hours(airport: dict[str, object]) -> str:
    raw = airport.get("openingHoursSpecification", [])
    if not isinstance(raw, list):
        return ""
    by_hours: list[tuple[list[str], str]] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        days = item.get("dayOfWeek", [])
        if isinstance(days, str):
            days = [days]
        if not isinstance(days, list):
            continue
        opens = str(item.get("opens", "")).strip()
        closes = str(item.get("closes", "")).strip()
        if not opens or not closes:
            continue
        hours = "H24" if opens == "00:00" and closes == "23:59" else f"{opens}–{closes} UTC"
        by_hours.append(([day_name(str(day)) for day in days], hours))
    return "; ".join(f"{'/'.join(days)} {hours}" for days, hours in by_hours)


def extract_frequencies(props: dict[str, str]) -> str:
    ignored = {
        "Aerodrome type",
        "Elevation",
        "Runway surface",
        "Fuel",
        "PPR",
        "Restaurant",
    }
    values = []
    for name, value in props.items():
        if name in ignored or name.startswith("Runway ") or name.startswith("Fuel price"):
            continue
        if re.fullmatch(r"[0-9]{3}(?:\.[0-9]{1,3})?", value):
            values.append(f"{name} {value}")
    return " · ".join(values)


def parse_page(raw_html: str, icao: str, url: str) -> AIPAirport:
    airport = airport_json(raw_html, icao)
    if airport is None:
        return AIPAirport(icao, url, "not_listed", error="Airport JSON-LD missing")
    props = properties(airport)
    geo = airport.get("geo", {})
    if not isinstance(geo, dict):
        geo = {}
    runway_lengths = []
    for name, value in props.items():
        if not name.startswith("Runway "):
            continue
        match = RUNWAY_METRIC_PATTERN.search(value)
        if match:
            runway_lengths.append(int(match.group(1)))
    try:
        latitude = float(geo["latitude"])
        longitude = float(geo["longitude"])
    except (KeyError, TypeError, ValueError):
        latitude = longitude = None
    return AIPAirport(
        icao=icao,
        url=str(airport.get("url", url)),
        status="ok",
        name=str(airport.get("name", "")),
        latitude=latitude,
        longitude=longitude,
        elevation_ft=parse_elevation_ft(props.get("Elevation", "")),
        longest_runway_m=max(runway_lengths) if runway_lengths else None,
        ppr=props.get("PPR", ""),
        fuel_summary=props.get("Fuel", ""),
        prices=extract_prices(props),
        price_checked_at=parse_price_checked_at(normalized_text(raw_html)),
        opening_hours=extract_opening_hours(airport),
        frequencies=extract_frequencies(props),
        restaurant=props.get("Restaurant", ""),
    )


def fetch(icao: str, country: str) -> AIPAirport:
    url = page_url(icao, country)
    if url is None:
        return AIPAirport(icao, "", "unsupported_country", error=country)
    request = urllib.request.Request(
        url,
        headers={"User-Agent": USER_AGENT, "Accept": "text/html"},
    )
    last_error = ""
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=40, context=CONTEXT) as response:
                raw_html = response.read().decode("utf-8", errors="replace")
                return parse_page(raw_html, icao, url)
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                return AIPAirport(icao, url, "not_listed", error="HTTP 404")
            last_error = f"HTTP {exc.code}"
        except Exception as exc:  # noqa: BLE001 - transient network retry
            last_error = f"{type(exc).__name__}: {exc}"
        if attempt < 2:
            time.sleep(0.8 * (attempt + 1))
    return AIPAirport(icao, url, "request_failed", error=last_error)


def audit_airports(
    airports: list[dict[str, str]], workers: int
) -> list[AIPAirport]:
    results: list[AIPAirport] = []
    with ThreadPoolExecutor(max_workers=workers) as executor:
        futures = {
            executor.submit(fetch, row["icao"].upper(), row["country_code"].upper()): row
            for row in airports
        }
        for future in as_completed(futures):
            result = future.result()
            results.append(result)
            print(
                f"{result.icao}: {result.status}"
                + (f" ({len(result.prices)} prices)" if result.prices else ""),
                flush=True,
            )
    return sorted(results, key=lambda item: item.icao)


def distance_nm(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    radius_nm = 3440.065
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    value = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return radius_nm * 2 * math.atan2(math.sqrt(value), math.sqrt(1 - value))


def write_audit(
    results: list[AIPAirport], airports: list[dict[str, str]]
) -> None:
    airports_by_icao = {row["icao"].upper(): row for row in airports}
    fields = [
        "checked_at",
        "icao",
        "url",
        "status",
        "name",
        "database_latitude",
        "database_longitude",
        "aip_latitude",
        "aip_longitude",
        "coordinate_delta_nm",
        "database_elevation_ft",
        "aip_elevation_ft",
        "elevation_delta_ft",
        "database_runway_m",
        "aip_longest_runway_m",
        "runway_delta_m",
        "ppr",
        "fuel",
        "prices",
        "opening_hours",
        "frequencies",
        "restaurant",
        "error",
    ]
    rows = []
    for result in results:
        airport = airports_by_icao[result.icao]
        coordinate_delta = ""
        if result.latitude is not None and result.longitude is not None:
            coordinate_delta = f"{distance_nm(float(airport['latitude_wgs84']), float(airport['longitude_wgs84']), result.latitude, result.longitude):.3f}"
        elevation_delta = (
            str(result.elevation_ft - int(float(airport["elevation_ft"])))
            if result.elevation_ft is not None else ""
        )
        runway_delta = (
            str(result.longest_runway_m - int(float(airport["runway_length_m"])))
            if result.longest_runway_m is not None else ""
        )
        rows.append(
            {
                "checked_at": CHECKED_AT,
                "icao": result.icao,
                "url": result.url,
                "status": result.status,
                "name": result.name,
                "database_latitude": airport["latitude_wgs84"],
                "database_longitude": airport["longitude_wgs84"],
                "aip_latitude": result.latitude if result.latitude is not None else "",
                "aip_longitude": result.longitude if result.longitude is not None else "",
                "coordinate_delta_nm": coordinate_delta,
                "database_elevation_ft": airport["elevation_ft"],
                "aip_elevation_ft": result.elevation_ft if result.elevation_ft is not None else "",
                "elevation_delta_ft": elevation_delta,
                "database_runway_m": airport["runway_length_m"],
                "aip_longest_runway_m": result.longest_runway_m if result.longest_runway_m is not None else "",
                "runway_delta_m": runway_delta,
                "ppr": result.ppr,
                "fuel": result.fuel_summary,
                "prices": "; ".join(
                    f"{label}: {price} {currency}/l"
                    for _, label, price, currency in result.prices
                ),
                "opening_hours": result.opening_hours,
                "frequencies": result.frequencies,
                "restaurant": result.restaurant,
                "error": result.error,
            }
        )
    write_table(AUDIT_PATH, fields, rows)


def availability_types(summary: str) -> set[str]:
    compact = re.sub(r"[^a-z0-9]+", "", summary.casefold())
    result: set[str] = set()
    if "avgas" in compact:
        result.add("AVGAS")
    if "ul91" in compact:
        result.add("UL91")
    if "mogas" in compact or "superplus" in compact or "carpetrol" in compact:
        result.add("MOGAS_SUPER")
    if "jeta1" in compact or "jetfuel" in compact:
        result.add("JET_A1")
    return result


def is_affirmative(value: str) -> bool:
    normalized = value.strip().casefold()
    return normalized == "ja" or normalized.startswith(("ja ", "ja–", "ja-")) \
        or normalized in {"yes", "true", "available", "verfügbar"}


def is_secondary_source(source: str) -> bool:
    """Return whether a source is an index/community source, not an operator."""
    normalized = source.casefold()
    return not normalized or any(
        marker in normalized
        for marker in (
            "aip.aero",
            "gat.aerops.com",
            "spritpreisliste.de",
            "aviation-fuel-prices.com",
        )
    )


def parsed_date(value: str) -> dt.date | None:
    try:
        return dt.date.fromisoformat(value)
    except ValueError:
        return None


def has_fresh_authoritative_price(
    rows: list[dict[str, str]], reference_date: str
) -> bool:
    reference = parsed_date(reference_date)
    if reference is None:
        return False
    cutoff = reference - dt.timedelta(days=7)
    return any(
        not is_secondary_source(row.get("source", ""))
        and (parsed_date(row.get("price_checked_at", "")) or dt.date.min) >= cutoff
        for row in rows
    )


def merge_confirmed(results: list[AIPAirport]) -> tuple[int, int, int]:
    airport_path = RESOURCES / "airports.csv"
    fuel_path = RESOURCES / "fuels.csv"
    price_path = RESOURCES / "fuel_prices.csv"
    airport_fields, airport_rows = read_table(airport_path)
    fuel_fields, fuel_rows = read_table(fuel_path)
    price_fields, price_rows = read_table(price_path)

    for field in (
        "aip_aero_url",
        "aip_aero_checked_at",
        "aip_aero_opening_hours",
        "aip_aero_frequencies",
    ):
        if field not in airport_fields:
            airport_fields.append(field)
            for row in airport_rows:
                row[field] = ""

    airports_by_icao = {row["icao"].upper(): row for row in airport_rows}
    fuels_by_key = {
        (row["airport_id"].upper(), row["fuel_type"]): row for row in fuel_rows
    }
    prices_by_key: dict[tuple[str, str], list[dict[str, str]]] = {}
    for row in price_rows:
        key = (row["airport_id"].upper(), row["fuel_type"])
        prices_by_key.setdefault(key, []).append(row)
    airport_changes = fuel_changes = price_changes = 0

    for result in results:
        if result.status != "ok":
            continue
        airport = airports_by_icao[result.icao]
        before_airport = dict(airport)
        airport["aip_aero_url"] = result.url
        airport["aip_aero_checked_at"] = CHECKED_AT
        airport["aip_aero_opening_hours"] = result.opening_hours
        airport["aip_aero_frequencies"] = result.frequencies
        if airport != before_airport:
            airport_changes += 1

        labels_by_type = {
            fuel_type: label for fuel_type, label, _, _ in result.prices
        }
        for fuel_type in availability_types(result.fuel_summary) | set(labels_by_type):
            key = (result.icao, fuel_type)
            fuel = fuels_by_key.get(key)
            if fuel is None:
                fuel = {field: "" for field in fuel_fields}
                fuel.update(
                    {
                        "schema_version": "1.2",
                        "fuel_id": f"{result.icao}:{fuel_type}:AIPAERO",
                        "airport_id": result.icao,
                        "fuel_type": fuel_type,
                    }
                )
                fuel_rows.append(fuel)
                fuels_by_key[key] = fuel
            elif not is_secondary_source(fuel.get("source", "")):
                # Operator-published availability and restrictions (for
                # example "Ja – nur PPR") outrank an aggregator summary.
                continue
            before_fuel = dict(fuel)
            if not is_affirmative(fuel.get("availability_raw", "")):
                fuel["availability_raw"] = "Ja"
            if labels_by_type.get(fuel_type):
                fuel["grade_or_detail"] = labels_by_type[fuel_type]
            elif not fuel.get("grade_or_detail"):
                fuel["grade_or_detail"] = result.fuel_summary
            fuel["source"] = result.url
            fuel["source_checked_at"] = CHECKED_AT
            fuel["data_checked_at"] = CHECKED_AT
            if fuel != before_fuel:
                fuel_changes += 1

        for fuel_type, label, price_value, currency in result.prices:
            if currency != "EUR" or float(price_value) <= 0:
                continue
            key = (result.icao, fuel_type)
            existing_prices = prices_by_key.get(key, [])
            # A direct airport/operator publication is authoritative even if
            # AIP:Aero exposes a newer indicative AeroPS value. This avoids
            # replacing e.g. a current gross pump price with an index value.
            if has_fresh_authoritative_price(
                existing_prices,
                result.price_checked_at or CHECKED_AT,
            ):
                continue
            price = max(
                existing_prices,
                key=lambda row: row.get("price_checked_at", ""),
                default=None,
            )
            if price is None:
                price = {field: "" for field in price_fields}
                price.update(
                    {
                        "schema_version": "1.2",
                        "price_id": f"{result.icao}:{fuel_type}:AIPAERO",
                        "airport_id": result.icao,
                        "fuel_type": fuel_type,
                    }
                )
                price_rows.append(price)
                prices_by_key.setdefault(key, []).append(price)
            before_price = dict(price)
            price["fuel_label_raw"] = label
            price["price_eur_per_litre"] = price_value
            price["price_raw_text"] = (
                f"{label} {price_value} EUR/l laut AIP:Aero "
                "(dort als indikative AeroPS-Angabe ausgewiesen)"
            )
            price["price_checked_at"] = result.price_checked_at or CHECKED_AT
            price["source"] = result.url
            if price != before_price:
                price_changes += 1

    write_table(airport_path, airport_fields, airport_rows)
    write_table(fuel_path, fuel_fields, fuel_rows)
    write_table(price_path, price_fields, price_rows)
    return airport_changes, fuel_changes, price_changes


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--workers", type=int, default=6)
    options = parser.parse_args()

    _, airports = read_table(RESOURCES / "airports.csv")
    results = audit_airports(airports, max(1, min(options.workers, 8)))
    write_audit(results, airports)
    if options.apply:
        changes = merge_confirmed(results)
        print(
            "Merged airport rows: %d; fuel rows: %d; price rows: %d"
            % changes
        )
    failures = [
        result
        for result in results
        if result.status in {"request_failed", "unsupported_country"}
    ]
    not_listed = [result for result in results if result.status == "not_listed"]
    print(
        f"Audited {len(results)} airports; not listed {len(not_listed)}; "
        f"request failures {len(failures)}; "
        f"report {AUDIT_PATH.name}"
    )
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
