#!/usr/bin/env python3
"""Copy chosen candidates into the Swift Package's regions resources folder."""
from __future__ import annotations

import argparse
import csv
import json
import shutil
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
MASTER = PROJECT_ROOT / "Sources/FlybookEurope/Resources/Flybook_Master.csv"
CONFIG = PROJECT_ROOT / "Tools/image_generation_config.json"
CANDIDATES = PROJECT_ROOT / "ImageProduction/Candidates"
SELECTIONS = PROJECT_ROOT / "ImageProduction/selections.csv"


def create_selection_template(path: Path) -> None:
    with MASTER.open(encoding="utf-8-sig", newline="") as handle:
        destinations = list(csv.DictReader(handle))
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["icao", "destination", "candidate", "approved", "notes"])
        writer.writeheader()
        for row in destinations:
            writer.writerow({"icao": row["ICAO"], "destination": row["Ziel"], "candidate": 1, "approved": "no", "notes": ""})
    print(f"Selection template created: {path}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--selections", type=Path, default=SELECTIONS)
    parser.add_argument("--create-template", action="store_true")
    parser.add_argument("--allow-incomplete", action="store_true")
    args = parser.parse_args()
    if args.create_template or not args.selections.exists():
        create_selection_template(args.selections)
        return 0

    config = json.loads(CONFIG.read_text(encoding="utf-8"))
    extension = config["output_format"].lower()
    resource_dir = PROJECT_ROOT / config["final_resource_directory"]
    resource_dir.mkdir(parents=True, exist_ok=True)
    with args.selections.open(encoding="utf-8-sig", newline="") as handle:
        choices = list(csv.DictReader(handle))
    approved = [row for row in choices if row["approved"].strip().lower() in {"yes", "ja", "true", "1"}]
    if len(approved) != 35 and not args.allow_incomplete:
        raise RuntimeError(f"Exactly 35 approved selections required; found {len(approved)}")

    copied = 0
    for row in approved:
        icao = row["icao"].strip().upper()
        candidate = int(row["candidate"])
        source = CANDIDATES / icao / f"{icao}_{candidate:02d}.{extension}"
        if not source.exists():
            raise FileNotFoundError(source)
        target = resource_dir / f"{icao}.{extension}"
        shutil.copy2(source, target)
        copied += 1
        print(f"✓ {icao}: candidate {candidate} → {target.relative_to(PROJECT_ROOT)}")
    print(f"Copied {copied} approved images into Swift Package resources")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
