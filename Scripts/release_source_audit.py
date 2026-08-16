#!/usr/bin/env python3
"""Network/source health audit for Flybook's runtime and master-data URLs."""

from __future__ import annotations

import argparse
import csv
import json
import re
import ssl
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Sources" / "FlybookEurope" / "Resources"
VERSION = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
USER_AGENT = f"FlybookEurope/{VERSION} release-audit contact: local-app"
CONTEXT = ssl.create_default_context()


def fetch(url: str, timeout: float = 25, limit: int | None = None):
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "*/*",
            **({"Range": f"bytes=0-{limit - 1}"} if limit else {}),
        },
    )
    started = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=timeout, context=CONTEXT) as response:
            body = response.read(limit) if limit else response.read()
            return response.status, response.headers.get("Content-Type", ""), body, time.monotonic() - started
    except urllib.error.HTTPError as exc:
        return exc.code, exc.headers.get("Content-Type", ""), exc.read(2048), time.monotonic() - started


def runtime_checks() -> list[str]:
    failures: list[str] = []
    route_wind_variables = [
        "wind_speed_10m",
        "wind_direction_10m",
        *[
            variable
            for level in (1000, 975, 950, 925, 900, 850, 800, 700)
            for variable in (
                f"wind_speed_{level}hPa",
                f"wind_direction_{level}hPa",
                f"geopotential_height_{level}hPa",
            )
        ],
    ]
    icon_weather_variables = [
        "temperature_2m",
        "dew_point_2m",
        "visibility",
        "cloud_cover_low",
        "wind_speed_10m",
        "wind_direction_10m",
        "wind_gusts_10m",
    ]

    def validates_route_wind_profile(content_type: str, body: bytes) -> bool:
        if "json" not in content_type:
            return False
        hourly = json.loads(body).get("hourly", {})
        return all(
            key in hourly and any(value is not None for value in hourly[key])
            for key in route_wind_variables
        )

    def validates_icon_weather(content_type: str, body: bytes) -> bool:
        if "json" not in content_type:
            return False
        hourly = json.loads(body).get("hourly", {})
        return len(hourly.get("time", [])) >= 120 and all(
            key in hourly and any(value is not None for value in hourly[key])
            for key in icon_weather_variables
        )

    checks = [
        (
            "DWD ICON-D2 direkte Ceiling",
            "https://opendata.dwd.de/weather/nwp/icon-d2/grib/12/ceiling/",
            lambda content_type, body: b"regular-lat-lon" in body.lower()
            and b"_2d_ceiling.grib2.bz2" in body.lower(),
        ),
        (
            "DWD ICON-EU direkte Ceiling",
            "https://opendata.dwd.de/weather/nwp/icon-eu/grib/12/ceiling/",
            lambda content_type, body: b"regular-lat-lon" in body.lower()
            and b"_ceiling.grib2.bz2" in body.lower(),
        ),
        (
            "Open-Meteo ICON-D2 Vertikalwind",
            "https://api.open-meteo.com/v1/dwd-icon?latitude=49.9675&longitude=8.1472"
            f"&hourly={','.join(route_wind_variables)}&forecast_days=2&timezone=UTC"
            "&wind_speed_unit=kn&models=icon_d2",
            validates_route_wind_profile,
        ),
        (
            "Open-Meteo ICON Seamless Hauptzugang",
            "https://api.open-meteo.com/v1/dwd-icon?latitude=49.9675&longitude=8.1472"
            f"&hourly={','.join(icon_weather_variables)}&forecast_days=5&timezone=UTC"
            "&wind_speed_unit=kn&models=icon_seamless",
            validates_icon_weather,
        ),
        (
            "Open-Meteo ICON Seamless Alternativzugang",
            "https://api.open-meteo.com/v1/forecast?latitude=49.9675&longitude=8.1472"
            f"&hourly={','.join(icon_weather_variables)}&forecast_days=5&timezone=UTC"
            "&wind_speed_unit=kn&models=icon_seamless",
            validates_icon_weather,
        ),
        (
            "Open-Meteo ICON-EU Vertikalwind",
            "https://api.open-meteo.com/v1/dwd-icon?latitude=49.9675&longitude=8.1472"
            f"&hourly={','.join(route_wind_variables)}&forecast_days=2&timezone=UTC"
            "&wind_speed_unit=kn&models=icon_eu",
            validates_route_wind_profile,
        ),
        (
            "Open-Meteo Best Match",
            "https://api.open-meteo.com/v1/forecast?latitude=49.9675&longitude=8.1472&hourly=temperature_2m,wind_speed_10m&forecast_days=2&timezone=UTC",
            lambda content_type, body: "json" in content_type and "hourly" in json.loads(body),
        ),
        (
            "MET Norway",
            "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=49.9675&lon=8.1472",
            lambda content_type, body: len(json.loads(body)["properties"]["timeseries"]) > 10,
        ),
        (
            "Esri Luftbild",
            "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/3/2/4",
            lambda content_type, body: body.startswith(b"\xff\xd8") or body.startswith(b"\x89PNG"),
        ),
        (
            "EDFZ Kraftstoff",
            "https://edfz.de/flugplatz/pilot-briefing/treibstoffpreise/",
            lambda content_type, body: b"AVGAS" in body.upper() and (b"MOGAS" in body.upper() or b"SUPER PLUS" in body.upper()),
        ),
        (
            "Spritpreisliste",
            "https://spritpreisliste.de/airports/EDKA",
            lambda content_type, body: b"EDKA" in body.upper(),
        ),
        (
            "Aviation Fuel Prices",
            "https://aviation-fuel-prices.com/airport-info/EDKA",
            lambda content_type, body: b"EDKA" in body.upper() or b"AACHEN" in body.upper(),
        ),
        (
            "Landegut",
            "https://landegut.de/",
            lambda content_type, body: len(set(re.findall(rb"\b(?:ED|ET|LO|EH|EK)[A-Z]{2}\b", body))) >= 40,
        ),
        (
            "DWD Open Data",
            "https://opendata.dwd.de/weather/nwp/icon-eu/grib/",
            lambda content_type, body: b"icon-eu" in body.lower() or b"href" in body.lower(),
        ),
        (
            "NOAA NOMADS",
            "https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_0p25.pl",
            lambda content_type, body: len(body) > 500,
        ),
    ]
    for name, url, validator in checks:
        last_error: Exception | None = None
        for attempt in range(3):
            try:
                status, content_type, body, elapsed = fetch(url)
                valid = 200 <= status < 300 and validator(content_type, body)
                print(f"{'PASS' if valid else 'FAIL'} {name}: HTTP {status}, {elapsed:.2f}s, {len(body)} Bytes")
                if not valid:
                    failures.append(f"{name}: HTTP {status} oder unerwarteter Inhalt")
                last_error = None
                break
            except Exception as exc:  # noqa: BLE001 - retry transient network errors
                last_error = exc
                if attempt < 2:
                    time.sleep(0.5 * (attempt + 1))
        if last_error is not None:
            print(f"FAIL {name}: {type(last_error).__name__}: {last_error}")
            failures.append(f"{name}: {last_error}")
    return failures


def master_urls() -> set[str]:
    values: set[str] = set()
    for path in RESOURCES.glob("*.csv"):
        with path.open(newline="", encoding="utf-8-sig") as handle:
            for row in csv.DictReader(handle):
                for value in row.values():
                    if isinstance(value, str) and value.startswith(("http://", "https://")):
                        values.add(value.strip())
    return values


def check_master_url(url: str):
    try:
        status, _, _, elapsed = fetch(url, timeout=15, limit=4096)
        return url, status, elapsed, ""
    except Exception as exc:  # noqa: BLE001
        return url, 0, 0.0, f"{type(exc).__name__}: {exc}"


def audit_master_sources() -> list[str]:
    urls = sorted(master_urls())
    broken: list[str] = []
    restricted = 0
    healthy = 0
    with ThreadPoolExecutor(max_workers=12) as executor:
        futures = [executor.submit(check_master_url, url) for url in urls]
        for future in as_completed(futures):
            url, status, _, error = future.result()
            if 200 <= status < 400:
                healthy += 1
            elif status in {401, 403, 405, 429}:
                # Reachable but automated validation is disallowed or throttled.
                restricted += 1
            else:
                broken.append(f"HTTP {status or '-'} {url} {error}".strip())
    print(f"Masterquellen: {len(urls)}; erreichbar {healthy}; geschützt/gedrosselt {restricted}; fehlerhaft {len(broken)}")
    for item in broken:
        print("QUELLENFEHLER:", item)
    return broken


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--all-master-sources", action="store_true")
    options = parser.parse_args()
    failures = runtime_checks()
    if options.all_master_sources:
        failures.extend(audit_master_sources())
    print("ERGEBNIS:", "PASS" if not failures else f"FAIL ({len(failures)} Fehler)")
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
