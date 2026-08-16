#!/usr/bin/env python3
"""Audit AeroPS calculator pages and merge confirmed fuel data.

The concrete calculator URL is authoritative only for fuels and prices that
are visibly listed.  A missing page or missing fuel never changes an existing
availability value to ``Nein``.
"""

from __future__ import annotations

import argparse
import csv
import html
import re
import shutil
import ssl
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Sources" / "FlybookEurope" / "Resources"
IPAD_RESOURCES = ROOT / "Flybook-iPad" / "Flybook-iPad" / "Resources"
AUDIT_PATH = ROOT / "AEROPS_AUDIT_2026-08-16.csv"
CHECKED_AT = "2026-08-16"
BASE_URL = "https://gat.aerops.com/prices/calculator"
USER_AGENT = "FlybookEurope/1.47 AeroPS-audit"
CONTEXT = ssl.create_default_context()
PRICE_PATTERN = re.compile(
    r'<span\s+class="fw-bold">\s*([^<:]+):\s*</span>\s*'
    r'<span\s+class="font-monospace">\s*([0-9]+(?:[.,][0-9]+)?)\s*'
    r'([A-Z]{3})\s*</span>',
    re.IGNORECASE | re.DOTALL,
)


@dataclass(frozen=True)
class VisibleFuel:
    label: str
    fuel_type: str
    price: str
    currency: str


@dataclass(frozen=True)
class AuditResult:
    icao: str
    url: str
    http_status: int
    result: str
    fuels: tuple[VisibleFuel, ...]
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
        writer = csv.DictWriter(
            handle,
            fieldnames=fieldnames,
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(rows)


def normalize_label(value: str) -> str:
    return " ".join(html.unescape(value).strip().split())


def fuel_type_for(label: str) -> str | None:
    folded = label.casefold().replace("-", " ")
    compact = re.sub(r"[^a-z0-9]+", "", folded)
    if "ul91" in compact:
        return "UL91"
    if "avgas" in compact and ("ul94" in compact or "94ul" in compact):
        return "AVGAS_UL94"
    if "avgas" in compact:
        return "AVGAS"
    if any(token in compact for token in ("superplus", "super98", "mogas")):
        return "MOGAS_SUPER"
    if "jeta1" in compact or compact == "jetfuel":
        return "JET_A1"
    return None


def fetch(icao: str) -> AuditResult:
    url = f"{BASE_URL}/{icao}"
    request = urllib.request.Request(
        url,
        headers={"User-Agent": USER_AGENT, "Accept": "text/html"},
    )
    last_error = ""
    for attempt in range(3):
        try:
            with urllib.request.urlopen(
                request,
                timeout=35,
                context=CONTEXT,
            ) as response:
                body = response.read().decode("utf-8", errors="replace")
                # Only the dark fuel-price band at the top is public airport
                # fuel information.  The later service form can contain
                # hidden/net/tax variants with the same labels and must not be
                # imported as additional pump prices.
                band_start = body.find("fa-solid fa-gas-pump")
                band_end = body.find(
                    '<div class="col-lg-10 text-sm-start mt-3">',
                    band_start,
                )
                price_band = (
                    body[band_start:band_end]
                    if band_start >= 0 and band_end > band_start
                    else ""
                )
                matches: list[VisibleFuel] = []
                seen: set[tuple[str, str, str]] = set()
                for raw_label, raw_price, raw_currency in PRICE_PATTERN.findall(
                    price_band
                ):
                    label = normalize_label(raw_label)
                    fuel_type = fuel_type_for(label)
                    if fuel_type is None:
                        continue
                    price = raw_price.replace(",", ".")
                    currency = raw_currency.upper()
                    key = (fuel_type, price, currency)
                    if key in seen:
                        continue
                    seen.add(key)
                    matches.append(VisibleFuel(label, fuel_type, price, currency))
                has_calculator = (
                    f'value="{icao}" id="icao"' in body
                    or f">{icao}</span>" in body
                    or f">{icao}</span>".replace('"', '') in body
                )
                result = (
                    "fuel_prices_visible"
                    if matches
                    else "calculator_without_visible_fuel"
                    if has_calculator
                    else "unexpected_page"
                )
                return AuditResult(
                    icao=icao,
                    url=url,
                    http_status=getattr(response, "status", 200),
                    result=result,
                    fuels=tuple(matches),
                )
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                return AuditResult(icao, url, 404, "no_calculator", ())
            last_error = f"HTTP {exc.code}"
        except Exception as exc:  # noqa: BLE001 - transient network retry
            last_error = f"{type(exc).__name__}: {exc}"
        if attempt < 2:
            time.sleep(0.6 * (attempt + 1))
    return AuditResult(icao, url, 0, "request_failed", (), last_error)


def audit_airports(icaos: list[str], workers: int) -> list[AuditResult]:
    results: list[AuditResult] = []
    with ThreadPoolExecutor(max_workers=workers) as executor:
        futures = {executor.submit(fetch, icao): icao for icao in icaos}
        for future in as_completed(futures):
            result = future.result()
            results.append(result)
            print(
                f"{result.icao}: {result.result}"
                + (f" ({len(result.fuels)} fuels)" if result.fuels else ""),
                flush=True,
            )
    return sorted(results, key=lambda item: item.icao)


def write_audit(results: list[AuditResult]) -> None:
    fields = [
        "checked_at",
        "icao",
        "url",
        "http_status",
        "result",
        "visible_fuels",
        "error",
    ]
    rows = []
    for result in results:
        visible = "; ".join(
            f"{fuel.label}: {fuel.price} {fuel.currency} [{fuel.fuel_type}]"
            for fuel in result.fuels
        )
        rows.append(
            {
                "checked_at": CHECKED_AT,
                "icao": result.icao,
                "url": result.url,
                "http_status": str(result.http_status),
                "result": result.result,
                "visible_fuels": visible,
                "error": result.error,
            }
        )
    write_table(AUDIT_PATH, fields, rows)


def merge_confirmed(results: list[AuditResult]) -> tuple[int, int]:
    fuel_path = RESOURCES / "fuels.csv"
    price_path = RESOURCES / "fuel_prices.csv"
    fuel_fields, fuel_rows = read_table(fuel_path)
    price_fields, price_rows = read_table(price_path)
    fuels_by_key = {
        (row["airport_id"], row["fuel_type"]): row for row in fuel_rows
    }
    prices_by_key = {
        (row["airport_id"], row["fuel_type"]): row for row in price_rows
    }
    fuel_changes = 0
    price_changes = 0

    for result in results:
        grouped: dict[str, list[VisibleFuel]] = {}
        for visible in result.fuels:
            grouped.setdefault(visible.fuel_type, []).append(visible)

        for fuel_type, visible_group in grouped.items():
            key = (result.icao, fuel_type)
            labels = list(dict.fromkeys(item.label for item in visible_group))
            raw_values = "; ".join(
                f"{item.label} {item.price} {item.currency}/l"
                for item in visible_group
            )
            fuel = fuels_by_key.get(key)
            if fuel is None:
                fuel = {field: "" for field in fuel_fields}
                fuel.update(
                    {
                        "schema_version": "1.2",
                        "fuel_id": f"{result.icao}:{fuel_type}",
                        "airport_id": result.icao,
                        "fuel_type": fuel_type,
                    }
                )
                fuel_rows.append(fuel)
                fuels_by_key[key] = fuel
            before = dict(fuel)
            if not fuel["availability_raw"].casefold().startswith("ja"):
                fuel["availability_raw"] = "Ja"
            fuel["grade_or_detail"] = " / ".join(labels)
            fuel["price_raw_text"] = f"{raw_values} laut AeroPS"
            if not before.get("source") or not before.get(
                "availability_raw", ""
            ).casefold().startswith("ja"):
                fuel["source"] = result.url
            fuel["source_checked_at"] = CHECKED_AT
            fuel["data_checked_at"] = CHECKED_AT
            if fuel != before:
                fuel_changes += 1

            # The price master is explicitly EUR/l.  Other currencies remain
            # visible in the audit and fuel raw text without an invented FX
            # conversion. Multiple different values for one type are equally
            # ambiguous and therefore never collapsed to an arbitrary price.
            eur_candidates = {
                item.price
                for item in visible_group
                if item.currency == "EUR" and float(item.price) > 0
            }
            if len(eur_candidates) != 1:
                continue
            price_value = next(iter(eur_candidates))
            price = prices_by_key.get(key)
            if price is None:
                price = {field: "" for field in price_fields}
                price.update(
                    {
                        "schema_version": "1.2",
                        "price_id": (
                            f"{result.icao}:{fuel_type}:"
                            f"{CHECKED_AT.replace('-', '')}"
                        ),
                        "airport_id": result.icao,
                        "fuel_type": fuel_type,
                    }
                )
                price_rows.append(price)
                prices_by_key[key] = price
            before = dict(price)
            price["fuel_label_raw"] = " / ".join(labels)
            price["price_eur_per_litre"] = price_value
            price["price_raw_text"] = (
                f"{' / '.join(labels)} {price_value} EUR/l laut AeroPS-Platzrechner"
            )
            price["price_checked_at"] = CHECKED_AT
            price["source"] = result.url
            if price != before:
                price_changes += 1

    price_rows = [
        row
        for row in price_rows
        if not (
            row.get("source", "").startswith(BASE_URL)
            and float(row.get("price_eur_per_litre") or 0) <= 0
        )
    ]
    write_table(fuel_path, fuel_fields, fuel_rows)
    write_table(price_path, price_fields, price_rows)
    for name in ("airports.csv", "features.csv", "fuels.csv", "fuel_prices.csv"):
        shutil.copyfile(RESOURCES / name, IPAD_RESOURCES / name)
    return fuel_changes, price_changes


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--workers", type=int, default=6)
    options = parser.parse_args()
    _, airports = read_table(RESOURCES / "airports.csv")
    icaos = sorted({row["icao"].strip().upper() for row in airports})
    results = audit_airports(icaos, max(1, min(options.workers, 8)))
    write_audit(results)
    if options.apply:
        fuel_changes, price_changes = merge_confirmed(results)
        print(f"Merged fuel rows: {fuel_changes}; price rows: {price_changes}")
    failures = [result for result in results if result.result == "request_failed"]
    print(
        f"Audited {len(results)} airports; request failures {len(failures)}; "
        f"report {AUDIT_PATH.name}"
    )
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
