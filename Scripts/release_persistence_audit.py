#!/usr/bin/env python3
"""Static release checks for version-stable Flybook profile persistence."""

from __future__ import annotations

import plistlib
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "Sources" / "FlybookEurope"


def read(name: str) -> str:
    return (SOURCES / name).read_text(encoding="utf-8")


def main() -> int:
    version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    with (SOURCES / "Info.plist").open("rb") as handle:
        info = plistlib.load(handle)

    app = read("FlybookEuropeApp.swift")
    users = read("ETOPSSettings.swift")
    aircraft = read("AircraftSettings.swift")
    airports = read("AirportSettings.swift")

    checks = {
        "stabile Bundle-ID": info.get("CFBundleIdentifier") == "de.flybook.europe",
        "Marketingversion entspricht VERSION": info.get("CFBundleShortVersionString") == version,
        "monotone numerische Buildnummer": str(info.get("CFBundleVersion", "")).isdigit(),
        "Benutzer Stephan und Maria vorhanden": (
            'case stephan = "Stephan"' in users and 'case maria = "Maria"' in users
        ),
        "stabile Benutzerprofil-Suite": (
            'UserDefaults(suiteName: "de.flybook.europe.user-profiles")' in users
        ),
        "Benutzerprofile werden beim Start restauriert": (
            "ETOPSProfileStore.restorePersistentProfiles()" in app
        ),
        "Legacy-Benutzerprofile werden migriert": "migrateLegacyValue" in users,
        "aktive Benutzerwahl wird persistent gespiegelt": (
            "persistentDefaults.set(user.rawValue" in users
            and "UserDefaults.standard" in users
        ),
        "benutzerdefinierte Flugzeuge persistent": (
            'namesKey = "aircraftRegistry.customNames"' in aircraft
            and "UserDefaults.standard.set(newValue, forKey: namesKey)" in aircraft
        ),
        "Flugzeugprofile mit stabilen Schluesseln": (
            'return "aircraft.a211"' in aircraft
            and 'return "aircraft.pa28160"' in aircraft
            and 'return "aircraft.custom.\\(rawValue)"' in aircraft
        ),
        "Airport-Oeffnungszeiten JSON-persistent": (
            'key = "airportOpeningHoursProfiles.v1"' in airports
            and "JSONEncoder().encode(profiles)" in airports
        ),
        "Airport-Landegebuehren JSON-persistent": (
            'key = "airportLandingFeeProfiles.v1"' in airports
            and airports.count("JSONEncoder().encode(profiles)") >= 2
        ),
    }

    failed = []
    for label, passed in checks.items():
        print(f"{'PASS' if passed else 'FAIL'} {label}")
        if not passed:
            failed.append(label)
    print(f"Persistenzpruefungen: {len(checks)}")
    print("ERGEBNIS:", "PASS" if not failed else f"FAIL ({len(failed)} Fehler)")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
