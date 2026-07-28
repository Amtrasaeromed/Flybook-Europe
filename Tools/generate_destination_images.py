#!/usr/bin/env python3
"""Batch-generate Flybook destination images from Flybook_Master.csv.

No third-party Python packages are required. The script talks directly to the
OpenAI Images API and writes resumable JSONL manifests.
"""
from __future__ import annotations

import argparse
import base64
import csv
import json
import os
import random
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CSV = PROJECT_ROOT / "Sources/FlybookEurope/Resources/Flybook_Master.csv"
DEFAULT_CONFIG = PROJECT_ROOT / "Tools/image_generation_config.json"
DEFAULT_STYLE = PROJECT_ROOT / "Tools/prompts/flybook_style.txt"
DEFAULT_OUTPUT = PROJECT_ROOT / "ImageProduction/Candidates"
DEFAULT_MANIFEST = PROJECT_ROOT / "ImageProduction/generation_manifest.jsonl"
API_URL = "https://api.openai.com/v1/images/generations"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate all Flybook destination images.")
    parser.add_argument("--csv", type=Path, default=DEFAULT_CSV)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--style", type=Path, default=DEFAULT_STYLE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--icao", action="append", help="Generate only this ICAO; may be repeated.")
    parser.add_argument("--count", type=int, help="Override candidates per destination.")
    parser.add_argument("--force", action="store_true", help="Regenerate existing candidate files.")
    parser.add_argument("--dry-run", action="store_true", help="Build prompts and manifests without API calls.")
    return parser.parse_args()


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def load_destinations(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    required = {"Land", "Wetterregion", "Ziel", "ICAO", "Saison", "Highlights", "Aktivitäten"}
    missing = required.difference(rows[0].keys() if rows else ())
    if missing:
        raise ValueError(f"Master CSV lacks columns: {', '.join(sorted(missing))}")
    if len(rows) != 35:
        raise ValueError(f"Expected exactly 35 destinations, found {len(rows)}")
    icaos = [row["ICAO"].strip().upper() for row in rows]
    if any(not code for code in icaos) or len(set(icaos)) != 35:
        raise ValueError("ICAO values must be present and unique for all 35 destinations")
    return rows


def cleaned(value: str) -> str:
    return " · ".join(part.strip() for part in value.split("·") if part.strip())


def build_prompt(row: dict[str, str], style: str, variant: int) -> str:
    seasons = row["Saison"].strip() or "appropriate travel season"
    variation = [
        "Use an establishing landscape view with a strong sense of place.",
        "Use a more intimate viewpoint that still clearly identifies the destination character.",
        "Use an elevated or waterfront perspective where geographically appropriate, without resembling drone stock imagery.",
    ][(variant - 1) % 3]
    return f"""{style.strip()}

Destination assignment:
- Destination: {row['Ziel'].strip()}
- Airport reference: {row['ICAO'].strip().upper()}
- Country code: {row['Land'].strip()}
- Travel region: {row['Wetterregion'].strip()}
- Best season: {seasons}
- Characteristic motifs: {cleaned(row['Highlights'])}
- Typical activities and atmosphere: {cleaned(row['Aktivitäten'])}

Show a coherent scene that represents the destination area, not the airport infrastructure itself. Select two or three characteristic motifs and combine them naturally; do not attempt to show every listed item. The result must remain geographically plausible and recognizably tied to the named destination.

Candidate direction {variant}: {variation}
"""


def api_generate(prompt: str, config: dict[str, Any], api_key: str) -> bytes:
    payload = {
        "model": config["model"],
        "prompt": prompt,
        "size": config["size"],
        "quality": config["quality"],
        "output_format": config["output_format"],
        "n": 1,
    }
    request = urllib.request.Request(
        API_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        method="POST",
    )
    attempts = int(config.get("maximum_retries", 4))
    timeout = int(config.get("request_timeout_seconds", 300))
    for attempt in range(1, attempts + 1):
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                result = json.loads(response.read().decode("utf-8"))
            encoded = result["data"][0].get("b64_json")
            if not encoded:
                raise RuntimeError("Images API response contained no b64_json image data")
            return base64.b64decode(encoded)
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, RuntimeError) as exc:
            detail = ""
            if isinstance(exc, urllib.error.HTTPError):
                try:
                    detail = exc.read().decode("utf-8", errors="replace")
                except Exception:
                    pass
            if attempt >= attempts:
                raise RuntimeError(f"Image request failed after {attempts} attempts: {exc} {detail}") from exc
            delay = float(config.get("retry_base_seconds", 4)) * (2 ** (attempt - 1)) + random.random()
            print(f"  request failed ({attempt}/{attempts}); retrying after {delay:.1f}s", file=sys.stderr)
            time.sleep(delay)
    raise AssertionError("unreachable")


def append_manifest(path: Path, record: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")


def main() -> int:
    args = parse_args()
    config = read_json(args.config)
    style = args.style.read_text(encoding="utf-8")
    destinations = load_destinations(args.csv)
    selected = {code.upper() for code in args.icao} if args.icao else None
    if selected:
        destinations = [row for row in destinations if row["ICAO"].strip().upper() in selected]
        unknown = selected.difference(row["ICAO"].strip().upper() for row in destinations)
        if unknown:
            raise ValueError(f"Unknown ICAO selection: {', '.join(sorted(unknown))}")

    api_key = os.getenv("OPENAI_API_KEY", "")
    if not args.dry_run and not api_key:
        raise RuntimeError("OPENAI_API_KEY is not set")

    count = args.count or int(config["candidates_per_destination"])
    if count < 1:
        raise ValueError("Candidate count must be at least 1")
    extension = str(config["output_format"]).lower()
    args.output.mkdir(parents=True, exist_ok=True)

    total = len(destinations) * count
    completed = skipped = failed = 0
    print(f"Flybook image generation: {len(destinations)} destinations × {count} candidates = {total}")

    for destination_index, row in enumerate(destinations, 1):
        icao = row["ICAO"].strip().upper()
        target_dir = args.output / icao
        target_dir.mkdir(parents=True, exist_ok=True)
        print(f"[{destination_index:02d}/{len(destinations):02d}] {icao} — {row['Ziel']}")
        for variant in range(1, count + 1):
            target = target_dir / f"{icao}_{variant:02d}.{extension}"
            prompt_path = target_dir / f"{icao}_{variant:02d}.prompt.txt"
            prompt = build_prompt(row, style, variant)
            prompt_path.write_text(prompt, encoding="utf-8")

            if target.exists() and target.stat().st_size > 0 and not args.force:
                print(f"  ✓ candidate {variant}: already exists")
                skipped += 1
                continue

            record = {
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "icao": icao,
                "destination": row["Ziel"].strip(),
                "candidate": variant,
                "model": config["model"],
                "size": config["size"],
                "quality": config["quality"],
                "format": extension,
                "prompt_version": config["prompt_version"],
                "prompt_file": str(prompt_path.relative_to(PROJECT_ROOT)),
                "output_file": str(target.relative_to(PROJECT_ROOT)),
            }
            if args.dry_run:
                record["status"] = "dry-run"
                append_manifest(args.manifest, record)
                print(f"  · candidate {variant}: prompt prepared")
                completed += 1
                continue

            try:
                image_bytes = api_generate(prompt, config, api_key)
                temporary = target.with_suffix(target.suffix + ".part")
                temporary.write_bytes(image_bytes)
                temporary.replace(target)
                record.update(status="generated", bytes=len(image_bytes))
                completed += 1
                print(f"  ✓ candidate {variant}: {len(image_bytes) / 1024:.0f} KB")
            except Exception as exc:
                record.update(status="failed", error=str(exc))
                failed += 1
                print(f"  ✗ candidate {variant}: {exc}", file=sys.stderr)
            append_manifest(args.manifest, record)

    print(f"Done: {completed} prepared/generated, {skipped} skipped, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("Interrupted. Existing images remain and the next run will resume.", file=sys.stderr)
        raise SystemExit(130)
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        raise SystemExit(1)
