import AppKit
import SwiftUI
import XCTest
@testable import FlybookEurope

@MainActor
final class LayoutSmokeTests: XCTestCase {
    func testFuelPlanCalculatorRendersAtSheetSize() throws {
        let view = FuelPlanCalculatorView(
            legs: [
                FuelPlanLeg(
                    id: "outbound",
                    originICAO: "EDFZ",
                    destinationICAO: "EDTG",
                    flightMinutes: 88,
                    consumptionLitersPerHour: 25
                ),
                FuelPlanLeg(
                    id: "return-one",
                    originICAO: "EDTG",
                    destinationICAO: "EDFM",
                    flightMinutes: 52,
                    consumptionLitersPerHour: 23
                ),
                FuelPlanLeg(
                    id: "return-two",
                    originICAO: "EDFM",
                    destinationICAO: "EDFZ",
                    flightMinutes: 24,
                    consumptionLitersPerHour: 23
                )
            ],
            reserveMinutes: 45,
            usableFuelLiters: 98,
            aircraftName: "D-EZHS · Aquila A211",
            startingFuelLiters: .constant(70)
        )

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            return XCTFail("Tankkalkulator konnte nicht gerendert werden")
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flybook-fuel-plan-calculator-audit.png")
        try png.write(to: url, options: .atomic)
        XCTAssertEqual(Int(image.size.width), 980)
        XCTAssertEqual(Int(image.size.height), 640)
    }

    func testDestinationFinderRendersWithVoucherButton() throws {
        let store = DestinationStore()
        let origins = [AirportReference.edfz] + store.destinations.compactMap {
            airport in
            guard airport.icao != "EDFZ",
                  let latitude = airport.latitude,
                  let longitude = airport.longitude
            else { return nil }
            return AirportReference(
                icao: airport.icao,
                name: airport.name,
                latitude: latitude,
                longitude: longitude,
                elevationFeet: airport.elevationFeet,
                timeZone: DestinationTimeZone.value(
                    for: airport,
                    weatherTimeZone: nil
                )
            )
        }
        let view = DestinationFinderView(
            destinations: store.destinations,
            origins: origins,
            onApply: { _ in },
            onClear: {}
        )
        .frame(width: 800, height: 900)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            return XCTFail("Destination Finder konnte nicht gerendert werden")
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flybook-destination-finder-voucher-audit.png")
        try png.write(to: url, options: .atomic)
        XCTAssertEqual(Int(image.size.width), 800)
        XCTAssertEqual(Int(image.size.height), 900)
    }

    func testVoucherHeaderRendersForArnsberg() throws {
        let store = DestinationStore()
        let destination = try XCTUnwrap(
            store.destinations.first(where: { $0.icao == "EDLA" })
        )
        let origins = [AirportReference.edfz] + store.destinations.compactMap { airport in
            guard airport.icao != "EDFZ",
                  let latitude = airport.latitude,
                  let longitude = airport.longitude else { return nil }
            return AirportReference(
                icao: airport.icao,
                name: airport.name,
                latitude: latitude,
                longitude: longitude,
                elevationFeet: airport.elevationFeet,
                timeZone: DestinationTimeZone.value(
                    for: airport,
                    weatherTimeZone: nil
                )
            )
        }
        let view = DestinationPage(
            destination: destination,
            availableDestinations: store.destinations,
            destinationPickerDestinations: store.destinations,
            destinationFilterIsActive: .constant(false),
            destinationFilterIsAvailable: false,
            availableOrigins: origins,
            selectedDestinationIndex: .constant(0),
            plannedMainDestinationArrival: .constant(nil)
        )
        .frame(width: 1800, height: 1200)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            return XCTFail("Arnsberg-Kopfbereich konnte nicht gerendert werden")
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flybook-voucher-header-audit.png")
        try png.write(to: url, options: .atomic)
        XCTAssertEqual(Int(image.size.width), 1800)
        XCTAssertEqual(Int(image.size.height), 1200)
    }

    func testDestinationPageRendersAtReferenceSize() throws {
        let store = DestinationStore()
        guard let destination = store.destinations.first(where: { $0.icao == "EDKA" }) else {
            return XCTFail("EDKA fehlt in den Masterdaten")
        }
        let origins = [AirportReference.edfz] + store.destinations.compactMap { airport in
            guard airport.icao != "EDFZ",
                  let latitude = airport.latitude,
                  let longitude = airport.longitude else { return nil }
            return AirportReference(
                icao: airport.icao,
                name: airport.name,
                latitude: latitude,
                longitude: longitude,
                elevationFeet: airport.elevationFeet,
                timeZone: DestinationTimeZone.value(for: airport, weatherTimeZone: nil)
            )
        }
        let view = DestinationPage(
            destination: destination,
            availableDestinations: store.destinations,
            destinationPickerDestinations: store.destinations,
            destinationFilterIsActive: .constant(false),
            destinationFilterIsAvailable: false,
            availableOrigins: origins,
            selectedDestinationIndex: .constant(0),
            plannedMainDestinationArrival: .constant(nil)
        )
        .frame(width: 1800, height: 1200)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return XCTFail("SwiftUI-Seite konnte nicht gerendert werden")
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flybook-layout-audit.png")
        try png.write(to: url, options: .atomic)
        XCTAssertEqual(Int(image.size.width), 1800)
        XCTAssertEqual(Int(image.size.height), 1200)
    }

    func testAlternatesViewRendersWithUpdateButton() throws {
        let store = DestinationStore()
        let destination = try XCTUnwrap(
            store.destinations.first(where: { $0.icao == "EDKA" })
        )
        let cruiseSpeed = try XCTUnwrap(
            AircraftType.a211.defaultCruisePerformance(powerPercent: 65)
                .tasKnots(atPressureAltitudeFeet: 1500)
        )
        let airports = AlternateAirport.nearestAirports(
            for: destination,
            availableDestinations: store.destinations,
            cruiseSpeedKnots: cruiseSpeed,
            fuelConsumptionLitersPerHour: 25
        )
        XCTAssertEqual(airports.count, 5)
        XCTAssertEqual(airports.first?.reference.icao, "EDKA")
        XCTAssertEqual(Set(airports.map(\.reference.icao)).count, 5)
        XCTAssertTrue(
            airports.dropFirst().allSatisfy {
                ($0.distanceFromDestinationNM ?? 0) > 0
                    && $0.bearingFromDestinationDegrees != nil
                    && ($0.flightTimeMinutes ?? 0) > 0
                    && ($0.estimatedFuelLiters ?? 0) > 0
                    && $0.relativePositionDescription != nil
            }
        )
        let distances = airports.dropFirst().compactMap(
            \.distanceFromDestinationNM
        )
        XCTAssertEqual(distances, distances.sorted())
        let firstAlternate = try XCTUnwrap(airports.dropFirst().first)
        let firstDistance = try XCTUnwrap(
            firstAlternate.distanceFromDestinationNM
        )
        XCTAssertEqual(
            try XCTUnwrap(firstAlternate.estimatedFuelLiters),
            firstDistance / cruiseSpeed * 25,
            accuracy: 0.001
        )

        let edfzPrimary = try XCTUnwrap(
            AlternateAirport.homebasePrimaryAirport(
                icao: "EDFZ",
                availableDestinations: store.destinations
            )
        )
        let edfzStandard = [edfzPrimary] + Array(
            AlternateAirport.candidates(
                from: edfzPrimary,
                availableDestinations: store.destinations,
                cruiseSpeedKnots: cruiseSpeed,
                fuelConsumptionLitersPerHour: 25,
                preferredICAOs: AlternateAirport.edfzStandardICAOs
            ).prefix(4)
        )
        XCTAssertEqual(
            edfzStandard.map(\.reference.icao),
            ["EDFZ", "EDFE", "EDFM", "EDRK", "EDRY"]
        )
        XCTAssertEqual(edfzStandard.first?.primaryBadgeText, "HOMEBASE")
        XCTAssertTrue(
            edfzStandard.dropFirst().allSatisfy {
                ($0.distanceFromDestinationNM ?? 0) > 0
                    && $0.bearingFromDestinationDegrees != nil
            }
        )

        XCTAssertTrue(AlternateWeatherMinimum.mvfr.includes(.vfr))
        XCTAssertTrue(AlternateWeatherMinimum.mvfr.includes(.mvfr))
        XCTAssertFalse(AlternateWeatherMinimum.mvfr.includes(.ifr))
        XCTAssertFalse(AlternateWeatherMinimum.mvfr.includes(nil))
        XCTAssertFalse(AlternateWeatherMinimum.vfr.includes(.mvfr))
        XCTAssertTrue(AlternateWeatherMinimum.off.includes(.lifr))
        XCTAssertTrue(AlternateWeatherMinimum.off.includes(nil))
        XCTAssertEqual(
            AlternateFuelDisplay.roundedUpEvenQuantity(
                liters: 4,
                unit: .liters
            ),
            4
        )
        XCTAssertEqual(
            AlternateFuelDisplay.roundedUpEvenQuantity(
                liters: 4.01,
                unit: .liters
            ),
            6
        )
        let formatter = ISO8601DateFormatter()
        let midday = try XCTUnwrap(
            formatter.date(from: "2026-08-10T12:00:00Z")
        )
        let lateEvening = try XCTUnwrap(
            formatter.date(from: "2026-08-10T22:00:00Z")
        )
        let ehmz = AirportReference(
            icao: "EHMZ",
            name: "Midden-Zeeland",
            latitude: 51.5122,
            longitude: 3.7311,
            elevationFeet: 6,
            timeZone: TimeZone(identifier: "Europe/Amsterdam")!,
            referenceRunway: "09/27"
        )
        XCTAssertEqual(
            AirportOperatingHoursEvaluator.openingAssessment(
                airport: ehmz,
                at: midday
            ),
            .confirmedOpen
        )
        XCTAssertEqual(
            AirportOperatingHoursEvaluator.openingAssessment(
                airport: ehmz,
                at: lateEvening
            ),
            .confirmedClosed
        )
        XCTAssertEqual(
            AirportOperatingHoursEvaluator.openingAssessment(
                airport: .edfz,
                at: lateEvening
            ),
            .confirmedClosed
        )
        XCTAssertEqual(
            AirportOperatingHoursEvaluator.openingAssessment(
                airport: AirportReference(
                    icao: "ZZZZ",
                    name: "Unbekannt",
                    latitude: 50,
                    longitude: 8,
                    elevationFeet: 0,
                    timeZone: .gmt
                ),
                at: midday
            ),
            .unclear
        )
        XCTAssertEqual(
            FlightPlanningWeatherStyle.windLevel(steadyWindKnots: 14.9),
            .normal
        )
        XCTAssertEqual(
            FlightPlanningWeatherStyle.windLevel(steadyWindKnots: 15),
            .yellow
        )
        XCTAssertEqual(
            FlightPlanningWeatherStyle.windLevel(steadyWindKnots: 20),
            .red
        )
        XCTAssertEqual(
            EDFZRunway.crosswindWarning(
                for: "EDFM",
                runway: "09",
                referenceRunway: "09/27",
                windFromDegrees: 180,
                steadyWindKnots: 10,
                gustKnots: nil
            ),
            .yellow
        )
        XCTAssertEqual(
            EDFZRunway.crosswindWarning(
                for: "EDFM",
                runway: "09",
                referenceRunway: "09/27",
                windFromDegrees: 180,
                steadyWindKnots: 16,
                gustKnots: nil
            ),
            .red
        )
        XCTAssertEqual(
            EDFZRunway.crosswindWarning(for: RunwayWindComponents(
                headwindKnots: 0,
                crosswindKnots: 1,
                gustCrosswindKnots: nil,
                crosswindComesFromRight: true
            )),
            .none
        )

        let view = AlternatesView(
            destination: destination,
            availableDestinations: store.destinations,
            plannedMainDestinationArrival:
                Date().addingTimeInterval(75 * 60)
        )
            .frame(width: 1180, height: 740)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return XCTFail("Alternates-Seite konnte nicht gerendert werden")
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flybook-alternates-layout-audit.png")
        try png.write(to: url, options: .atomic)
        XCTAssertEqual(Int(image.size.width), 1180)
        XCTAssertEqual(Int(image.size.height), 740)
    }

}
