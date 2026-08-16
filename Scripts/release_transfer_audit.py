#!/usr/bin/env python3
"""Static release checks for Flybook's low-data network policy."""

from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "Sources" / "FlybookEurope"
IPAD_ROOT = ROOT / "Flybook-iPad" / "Flybook-iPad"
IPAD_PROJECT = (
    ROOT / "Flybook-iPad" / "Flybook-iPad.xcodeproj" / "project.pbxproj"
)


def text(name: str) -> str:
    return (SOURCES / name).read_text(encoding="utf-8")


def main() -> int:
    app = text("FlybookEuropeApp.swift")
    store = text("DestinationStore.swift")
    finder = text("DestinationFinder.swift")
    page = text("DestinationPage.swift")
    wind = text("RouteWindViewModel.swift")
    wind_service = text("RouteWindService.swift")
    risk = text("RouteWeatherRisk.swift")
    network = text("FlightNetwork.swift")
    planning_weather = text("EDFZWeatherService.swift")
    direct_ceiling = text("DWDICONCeilingService.swift")
    five_day_weather = text("WeatherService.swift")
    optimized_refresh = page[
        page.index("private func refreshDataOptimizedWeather"):
        page.index("private func refreshPlanningAirportWeather")
    ]
    now_refresh = page[
        page.index("private func refreshLiveWeather"):
        page.index("private func resetFlightPlanningSchedule")
    ]
    all_swift = "\n".join(
        path.read_text(encoding="utf-8") for path in SOURCES.glob("*.swift")
    )
    ipad_swift = "\n".join(
        path.read_text(encoding="utf-8") for path in IPAD_ROOT.rglob("*.swift")
    )
    ipad_project = IPAD_PROJECT.read_text(encoding="utf-8")

    checks = {
        "kein Vollwetterabruf beim Start": ".prefetch(destinations: store.destinations)" not in app,
        "kein pauschaler Preis-Scrape aller Flugplaetze": (
            "refreshMonthlyFuelPrices" not in store
            and "withTaskGroup" not in text("FuelPriceService.swift")
            and "refreshFuelPriceIfNeeded" in app
        ),
        "Finder ohne pauschale 16-Tage-Abfrage": 'forecast_days", value: "16"' not in finder,
        "Finder nutzt Zeitfenster": 'name: "start_date"' in finder and 'name: "end_date"' in finder,
        "Finder nutzt kleine Batches": "by: 10" in finder,
        "Finder zeigt Treffer bei fehlendem Wetter weiter": (
            "incompleteRouteWeatherICAOs.insert(destination.icao)" in finder
            and "routeMatches.append(candidate)" in finder
            and "weatherWasChecked:" in finder
            and "!incompleteRouteWeatherICAOs.contains(destination.icao)" in finder
        ),
        "Best-Level im geforderten 500-ft-Raster": (
            "stride(from: 2_000, through: 10_000, by: 500)" in wind
            and "by: 250" not in wind
        ),
        "Vertikalwind nutzt alle gelieferten D2-Druckflaechen": all(
            token in wind_service
            for level in (1000, 975, 950, 925, 900, 850, 800, 700)
            for token in (
                f'"wind_speed_{level}hPa"',
                f'"wind_direction_{level}hPa"',
                f'"geopotential_height_{level}hPa"',
            )
        ),
        "Vertikalinterpolation bleibt auf Modellnachbarflaechen begrenzt": (
            "private func interpolateAltitude(" in wind_service
            and ".sorted { $0.height < $1.height }" in wind_service
            and "let lower = levels.last(where:" in wind_service
            and "let upper = levels.first(where:" in wind_service
        ),
        "drei Streckenwindpunkte werden in einem Modellabruf gebuendelt": (
            'name: "latitude"' in wind_service
            and 'joined(separator: ",")' in wind_service
            and "[RouteWindAPIResponse].self" in wind_service
            and "withThrowingTaskGroup" not in wind_service
        ),
        "Korridorwetter ohne 16-Tage-Payload": 'forecast_days", value: "16"' not in risk,
        "Planungs-Ceiling kommt direkt aus DWD ICON-D2 oder ICON-EU": (
            "icon-d2/grib" not in direct_ceiling
            and 'modelDirectory = "icon-d2"' in direct_ceiling
            and 'modelDirectory = "icon-eu"' in direct_ceiling
            and "_2d_ceiling.grib2.bz2" in direct_ceiling
            and "_CEILING.grib2.bz2" in direct_ceiling
            and "DWDICONCeilingService.shared.ceiling" in planning_weather
        ),
        "Planungsfeld erfindet keine lokale Ceiling": (
            "ICONCloudProfile" not in planning_weather
            and "estimatedCloudBaseFeet" not in planning_weather
            and "ceilingFeet: nil" in planning_weather
        ),
        "validiertes 5-Tages-Nebelrisiko bleibt getrennt": (
            "FogRiskModel.calculate" in five_day_weather
            and "estimatedCloudBaseFeet" in five_day_weather
            and "estimateCeiling" in five_day_weather
        ),
        "Update bleibt datenoptimiert": (
            "refreshPlanningAirportWeather(forceRefresh: true)" in optimized_refresh
            and "AlternateWeatherUpdater.refresh(" in optimized_refresh
            and "airports: nearestAlternateAirports" in optimized_refresh
            and "weatherModel.load" not in optimized_refresh
            and "refreshRouteWinds" not in optimized_refresh
            and "refreshRouteRisks" not in optimized_refresh
        ),
        "NOW umgeht alle Wettercaches": (
            "RouteWindService.shared.invalidateCaches()" in now_refresh
            and "weatherModel.load" in now_refresh
            and "refreshRouteWinds()" in now_refresh
            and "refreshRouteRisks()" in now_refresh
            and "refreshPlanningAirportWeather(forceRefresh: true)" in now_refresh
            and "AlternateWeatherUpdater.refresh(" in now_refresh
            and "airports: nearestAlternateAirports" in now_refresh
            and "forceRefresh: true" in now_refresh
        ),
        "globale Request-Grenze aktiv": "maximumConcurrentRequests: 4" in network,
        "wichtige Flugwetterabrufe haben hohe Prioritaet": (
            "FlightNetworkPriority" in network
            and "priority: .high" in text("EDFZWeatherService.swift")
            and "priority: .high" in text("RouteWindService.swift")
        ),
        "nachrangige Daten haben niedrige Prioritaet": (
            "priority: .low" in finder
            and "priority: .low" in risk
            and "priority: .low" in text("WeatherService.swift")
        ),
        "Request-Gate wartet ohne Polling": (
            "CheckedContinuation<Void, Never>" in network
            and "Task.sleep" not in network
        ),
        "kein URLSession.shared in Fachservices": (
            "URLSession.shared" not in all_swift
            and "URLSession.shared" not in ipad_swift
        ),
        "iPad-Korridorwetter nutzt gemeinsamen Open-Meteo-Schutz": (
            "FlightNetwork.openMeteoData(" in ipad_swift
            and "priority: .low" in ipad_swift
        ),
        "Mac und iPad verwenden dieselben Airport-Masterdaten": (
            all(
                f"../Sources/FlybookEurope/Resources/{name}" in ipad_project
                for name in (
                    "airports.csv",
                    "features.csv",
                    "fuels.csv",
                    "fuel_prices.csv",
                )
            )
            and not any((IPAD_ROOT / "Resources").glob("*.csv"))
        ),
        "30-Minuten-Fachcaches vorhanden": all_swift.count("30 * 60") >= 4,
    }

    failures = []
    for label, passed in checks.items():
        print(f"{'PASS' if passed else 'FAIL'} {label}")
        if not passed:
            failures.append(label)
    print(f"Datenflusspruefungen: {len(checks)}")
    print("ERGEBNIS:", "PASS" if not failures else f"FAIL ({len(failures)} Fehler)")
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
