#!/usr/bin/env python3
"""Inventory and technically review Flybook destination image candidates."""
from __future__ import annotations

import argparse
import csv
import json
import subprocess
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
CSV_PATH = PROJECT_ROOT / "Sources/FlybookEurope/Resources/Flybook_Master.csv"
CANDIDATES = PROJECT_ROOT / "ImageProduction/Candidates"
REPORT = PROJECT_ROOT / "ImageProduction/Reports/candidate_review.csv"
CONFIG = PROJECT_ROOT / "Tools/image_generation_config.json"


def image_dimensions(path: Path) -> tuple[int | None, int | None]:
    # macOS provides sips by default. The fallback still validates existence/size.
    try:
        output = subprocess.check_output(
            ["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(path)],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        values = {}
        for line in output.splitlines():
            if ":" in line:
                key, value = line.split(":", 1)
                values[key.strip()] = value.strip()
        return int(values["pixelWidth"]), int(values["pixelHeight"])
    except (FileNotFoundError, subprocess.SubprocessError, KeyError, ValueError):
        return None, None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidates", type=Path, default=CANDIDATES)
    parser.add_argument("--report", type=Path, default=REPORT)
    args = parser.parse_args()

    config = json.loads(CONFIG.read_text(encoding="utf-8"))
    expected_count = int(config["candidates_per_destination"])
    extension = config["output_format"].lower()
    expected_width, expected_height = map(int, config["size"].split("x"))
    with CSV_PATH.open(encoding="utf-8-sig", newline="") as handle:
        destinations = list(csv.DictReader(handle))
    if len(destinations) != 35:
        raise RuntimeError(f"Expected 35 CSV destinations, found {len(destinations)}")

    rows = []
    missing = invalid = 0
    for destination in destinations:
        icao = destination["ICAO"].strip().upper()
        for candidate in range(1, expected_count + 1):
            image = args.candidates / icao / f"{icao}_{candidate:02d}.{extension}"
            exists = image.exists()
            byte_size = image.stat().st_size if exists else 0
            width, height = image_dimensions(image) if exists else (None, None)
            dimensions_ok = width is None or (width == expected_width and height == expected_height)
            size_ok = byte_size >= 20_000 if exists else False
            status = "ready" if exists and size_ok and dimensions_ok else "missing" if not exists else "invalid"
            missing += status == "missing"
            invalid += status == "invalid"
            rows.append({
                "icao": icao,
                "destination": destination["Ziel"],
                "candidate": candidate,
                "file": str(image.relative_to(PROJECT_ROOT)),
                "status": status,
                "bytes": byte_size,
                "width": width or "not_checked",
                "height": height or "not_checked",
                "manual_choice": "",
                "manual_notes": "",
            })

    args.report.parent.mkdir(parents=True, exist_ok=True)
    with args.report.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    print(f"Review report: {args.report}")
    print(f"Candidates: {len(rows)}; missing: {missing}; invalid: {invalid}; ready: {len(rows)-missing-invalid}")
    return 1 if invalid else 0


if __name__ == "__main__":
    raise SystemExit(main())
