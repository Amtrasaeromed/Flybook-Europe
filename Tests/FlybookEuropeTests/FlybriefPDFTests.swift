import PDFKit
import XCTest
@testable import FlybookEurope

@MainActor
final class FlybriefPDFTests: XCTestCase {
    func testFlybriefRendersOneSearchablePDFPagePerMainFlight() throws {
        let snapshot = sampleSnapshot()
        let data = FlybriefPDFExporter.pdfData(for: snapshot)
        let document = try XCTUnwrap(PDFDocument(data: data))

        XCTAssertEqual(
            snapshot.suggestedFilename,
            "Flybrief 13AUG26 EDFZ-EDXE-EDLM-EHAM-EDFZ.pdf"
        )
        XCTAssertEqual(document.pageCount, 3)
        let outboundPage = try XCTUnwrap(document.page(at: 0))
        let returnPage = try XCTUnwrap(document.page(at: 1))
        let fuelPage = try XCTUnwrap(document.page(at: 2))
        for page in [outboundPage, returnPage, fuelPage] {
            XCTAssertEqual(page.bounds(for: .mediaBox).width, 595.28, accuracy: 0.1)
            XCTAssertEqual(page.bounds(for: .mediaBox).height, 841.89, accuracy: 0.1)
        }
        XCTAssertGreaterThan(data.count, 10_000)
        let text = document.string ?? ""
        XCTAssertTrue(text.contains("FLYBRIEF"))
        XCTAssertTrue(text.contains("EDFZ-EDXE-EDLM-EHAM-EDFZ"))
        XCTAssertTrue(text.contains("ETOPS-PIPI MAX"))
        XCTAssertTrue(text.contains("08:00-18:00 LCL"))
        XCTAssertFalse(text.contains("Regulär"))
        XCTAssertFalse(outboundPage.string?.contains("KRAFTSTOFF") == true)
        XCTAssertFalse(returnPage.string?.contains("KRAFTSTOFF") == true)
        XCTAssertTrue(fuelPage.string?.contains("FUELPLAN") == true)
        XCTAssertTrue(fuelPage.string?.contains("MINIMUM T/O") == true)
        XCTAssertTrue(fuelPage.string?.contains("LEG / GESAMT") == true)
        XCTAssertTrue(fuelPage.string?.contains("EHAM - Amsterdam Schiphol") == true)
        XCTAssertTrue(text.contains("Seitenwind rechts 8 G12 kt"))
        XCTAssertTrue(text.contains("ALTERNATES FÜR EHAM"))
        XCTAssertTrue(text.contains("EHRD"))
        XCTAssertTrue(text.contains("2.200 m"))
        XCTAssertTrue(text.contains("Asphalt"))
        XCTAssertTrue(text.contains("RWY"))
        XCTAssertTrue(text.contains("06"))
        XCTAssertTrue(text.contains("24"))
        XCTAssertTrue(text.contains("VFR"))
        XCTAssertTrue(text.contains("Heiter"))
        XCTAssertTrue(text.contains("FLUGZEIT"))
        XCTAssertTrue(text.contains("0:17"))
        XCTAssertTrue(text.contains("8 L"))
        XCTAssertTrue(text.contains("FL30 240/09"))
        XCTAssertTrue(text.contains("FL60 250/12"))
        XCTAssertTrue(text.contains("FL90 260/18"))
        XCTAssertTrue(text.contains("T/O Roll"))
        XCTAssertTrue(text.contains("250m (22%)"))
        XCTAssertTrue(text.contains("430m (38%)"))
        XCTAssertTrue(text.contains("750kg"))
        XCTAssertTrue(text.contains("LDG Roll"))
        XCTAssertTrue(text.contains("210m (23%)"))
        XCTAssertTrue(text.contains("500m (53%)"))
        XCTAssertTrue(text.contains("733kg"))
        XCTAssertTrue(text.contains("Erstellt:"))
        XCTAssertTrue(text.contains("TEILSTRECKE 1/3"))
        XCTAssertTrue(text.contains("EDXE"))
        XCTAssertTrue(outboundPage.string?.contains("HINFLUG") == true)
        XCTAssertFalse(outboundPage.string?.contains("RÜCKFLUG") == true)
        XCTAssertTrue(returnPage.string?.contains("RÜCKFLUG") == true)
        XCTAssertFalse(returnPage.string?.contains("HINFLUG") == true)
        XCTAssertFalse(fuelPage.string?.contains("HINFLUG") == true)

        if let output = ProcessInfo.processInfo.environment["FLYBRIEF_PREVIEW_PATH"] {
            try data.write(to: URL(fileURLWithPath: output), options: .atomic)
        }
    }

    func testMultiStopWithAlternateMemosUsesSeparateA4Pages() throws {
        let base = sampleSnapshot()
        let snapshot = FlybriefSnapshot(
            title: base.title,
            route: base.route,
            flightDate: base.flightDate,
            timeBasis: base.timeBasis,
            planningMode: FlightPlanningMode.multiStop.rawValue,
            aircraft: base.aircraft,
            base: base.base,
            legs: base.legs,
            fuelPlan: nil,
            createdAt: base.createdAt
        )

        let groups = FlybriefPDFExporter.pageLegGroups(for: snapshot)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first?.count, 1)

        let document = try XCTUnwrap(
            PDFDocument(data: FlybriefPDFExporter.pdfData(for: snapshot))
        )
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertTrue(document.string?.contains("1. FLUG") == false)
        XCTAssertTrue(document.string?.contains("HINFLUG") == true)
        XCTAssertTrue(document.string?.contains("RÜCKFLUG") == true)
    }

    private func sampleSnapshot() -> FlybriefSnapshot {
        let created = Date(timeIntervalSince1970: 1_786_609_800)
        return FlybriefSnapshot(
            title: "Flybrief",
            route: "EDFZ-EDXE-EDLM-EHAM-EDFZ",
            flightDate: created,
            timeBasis: "Lokal",
            planningMode: "Hin-/Rückflug",
            aircraft: "Aquila A211",
            base: "LSV Mainz",
            legs: [
                leg(
                    id: "outbound",
                    title: "Hinflug",
                    route: "EDFZ → EHAM",
                    departure: endpoint(
                        role: "Abflug", icao: "EDFZ", name: "Mainz-Finthen",
                        time: "13.08.2026 09:00 LCL", runway: "07"
                    ),
                    arrival: endpoint(
                        role: "Ankunft", icao: "EHAM", name: "Amsterdam Schiphol",
                        time: "13.08.2026 11:06 LCL", runway: "06"
                    ),
                    segments: [
                        segment(
                            id: "outbound-0", title: "Teilstrecke 1/3",
                            route: "EDFZ → EDXE",
                            departure: endpoint(
                                role: "Abflug", icao: "EDFZ", name: "Mainz-Finthen",
                                time: "13.08.2026 09:00 LCL", runway: "07"
                            ),
                            arrival: endpoint(
                                role: "Ankunft", icao: "EDXE", name: "Rheine-Eschendorf",
                                time: "13.08.2026 09:42 LCL", runway: "11"
                            )
                        ),
                        segment(
                            id: "outbound-1", title: "Teilstrecke 2/3",
                            route: "EDXE → EDLM",
                            departure: endpoint(
                                role: "Abflug", icao: "EDXE", name: "Rheine-Eschendorf",
                                time: "13.08.2026 10:02 LCL", runway: "11"
                            ),
                            arrival: endpoint(
                                role: "Ankunft", icao: "EDLM", name: "Marl-Loemühle",
                                time: "13.08.2026 10:28 LCL", runway: "07"
                            )
                        ),
                        segment(
                            id: "outbound-2", title: "Teilstrecke 3/3",
                            route: "EDLM → EHAM",
                            departure: endpoint(
                                role: "Abflug", icao: "EDLM", name: "Marl-Loemühle",
                                time: "13.08.2026 10:48 LCL", runway: "07"
                            ),
                            arrival: endpoint(
                                role: "Ankunft", icao: "EHAM", name: "Amsterdam Schiphol",
                                time: "13.08.2026 11:06 LCL", runway: "06"
                            )
                        )
                    ]
                ),
                leg(
                    id: "return",
                    title: "Rückflug",
                    route: "EHAM → EDFZ",
                    departure: endpoint(
                        role: "Abflug", icao: "EHAM", name: "Amsterdam Schiphol",
                        time: "14.08.2026 15:00 LCL", runway: "06"
                    ),
                    arrival: endpoint(
                        role: "Ankunft", icao: "EDFZ", name: "Mainz-Finthen",
                        time: "14.08.2026 17:04 LCL", runway: "07"
                    )
                )
            ],
            fuelPlan: sampleFuelPlan(confirmedAt: created),
            createdAt: created
        )
    }

    private func leg(
        id: String,
        title: String,
        route: String,
        departure: FlybriefEndpointSnapshot,
        arrival: FlybriefEndpointSnapshot,
        segments: [FlybriefSegmentSnapshot] = []
    ) -> FlybriefLegSnapshot {
        FlybriefLegSnapshot(
            id: id,
            title: title,
            dateText: "13.08.2026",
            routeText: route,
            stopsText: nil,
            travelTimeText: "2:06",
            blockTimeText: "2:06",
            trackText: "210 NM",
            altitudeText: "FL085",
            bestLevelText: "FL080",
            routeWindText: "Gegenwind 5 kt",
            routeWindDetail: "Wind 290°/18 kt · gültig 10:00",
            etopsText: "2:06",
            etopsLevel: .warning,
            routeWeather: (0..<6).map {
                FlybriefRouteWeatherPoint(
                    id: $0,
                    level: $0 == 4 ? .info : .good
                )
            },
            routeWeatherSummary: "Routenwetter marginal",
            altitudeWindsText: "FL30 240/09 · FL60 250/12 · FL90 260/18",
            departure: departure,
            arrival: arrival,
            segments: segments,
            alternates: sampleAlternates()
        )
    }

    private func segment(
        id: String,
        title: String,
        route: String,
        departure: FlybriefEndpointSnapshot,
        arrival: FlybriefEndpointSnapshot
    ) -> FlybriefSegmentSnapshot {
        FlybriefSegmentSnapshot(
            id: id,
            title: title,
            routeText: route,
            blockTimeText: "0:58",
            trackText: "98 NM",
            routeWindText: "Gegenwind 4 kt",
            routeWindDetail: "Kurs 340° · Wind 290°/18 kt · gültig 10:00",
            routeWeather: (0..<3).map {
                FlybriefRouteWeatherPoint(id: $0, level: .good)
            },
            routeWeatherSummary: "Routenwetter unkritisch",
            departure: departure,
            arrival: arrival
        )
    }

    private func endpoint(
        role: String,
        icao: String,
        name: String,
        time: String,
        runway: String
    ) -> FlybriefEndpointSnapshot {
        FlybriefEndpointSnapshot(
            role: role,
            icao: icao,
            name: name,
            openingHoursText: "08:00-18:00 LCL",
            timeText: time,
            operatingStatus: "Geöffnet",
            operatingLevel: .good,
            referenceRunway: runway == "07" ? "07/25" : "06/24",
            activeRunway: runway,
            runwayPerformance: role == "Abflug"
                ? FlybriefRunwayPerformanceSnapshot(
                    label: "T/O",
                    rollMeters: 250,
                    rollPercentage: 22,
                    over50FeetMeters: 430,
                    over50FeetPercentage: 38,
                    weightKilograms: 750
                )
                : FlybriefRunwayPerformanceSnapshot(
                    label: "LDG",
                    rollMeters: 210,
                    rollPercentage: 23,
                    over50FeetMeters: 500,
                    over50FeetPercentage: 53,
                    weightKilograms: 733
                ),
            weather: FlybriefWeatherSnapshot(
                category: "VFR",
                categoryLevel: .good,
                condition: "Heiter",
                temperatureText: "22 °C",
                cloudVisibilityText: "SCT 3500 / 10km+",
                pressureText: "QNH 1018",
                densityAltitudeText: "DA 1800 ft",
                windText: "290°/14 G20 kt",
                validTimeText: "Wetter gültig 13.08.2026 09:00 LCL",
                warningText: nil
            ),
            runwayWind: FlybriefRunwayWindSnapshot(
                windDirectionDegrees: 290,
                headwindKnots: 11,
                crosswindKnots: 8,
                gustCrosswindKnots: 12,
                crosswindComesFromRight: true,
                warningLevel: .good
            ),
            sunText: "Dawn 05:45 · SR 06:20 · SS 20:48 · Dusk 21:24 LCL"
        )
    }

    private func sampleAlternates() -> [FlybriefAlternateSnapshot] {
        [
            FlybriefAlternateSnapshot(
                icao: "EHRD",
                name: "Rotterdam",
                distanceNM: 31,
                flightTimeText: "0:17",
                fuelLiters: 8,
                runwayLengthMeters: 2200,
                surface: "Asphalt",
                runwayDirection: "06/24",
                preferredRunway: "24",
                weatherText: "VFR · Heiter · SCT 3500 / 10km+ · 290°/14 kt",
                weatherCategory: "VFR",
                weatherCondition: "Heiter",
                weatherCloudVisibility: "SCT 3500 / 10km+",
                weatherWind: "290°/14 kt",
                weatherLevel: .good
            ),
            FlybriefAlternateSnapshot(
                icao: "EHLE",
                name: "Lelystad",
                distanceNM: 34,
                flightTimeText: "0:19",
                fuelLiters: 9,
                runwayLengthMeters: 1250,
                surface: "Asphalt",
                runwayDirection: "05/23",
                preferredRunway: "23",
                weatherText: "MVFR · Regen · BKN 1800 / 8km · 280°/18 kt",
                weatherCategory: "MVFR",
                weatherCondition: "Regen",
                weatherCloudVisibility: "BKN 1800 / 8km",
                weatherWind: "280°/18 kt",
                weatherLevel: .info
            ),
            FlybriefAlternateSnapshot(
                icao: "EHHV",
                name: "Hilversum",
                distanceNM: 36,
                flightTimeText: "0:20",
                fuelLiters: 9,
                runwayLengthMeters: 700,
                surface: "Gras",
                runwayDirection: "07/25",
                preferredRunway: "25",
                weatherText: "VFR · Bedeckt · SCT 3000 / 10km+ · 270°/12 kt",
                weatherCategory: "VFR",
                weatherCondition: "Bedeckt",
                weatherCloudVisibility: "SCT 3000 / 10km+",
                weatherWind: "270°/12 kt",
                weatherLevel: .good
            )
        ]
    }

    private func sampleFuelPlan(confirmedAt: Date) -> FuelPlanConfirmation {
        let legs = [
            FuelPlanLeg(
                id: "EDFZ-EDXE",
                originICAO: "EDFZ",
                destinationICAO: "EDXE",
                flightMinutes: 42,
                consumptionLitersPerHour: 25
            ),
            FuelPlanLeg(
                id: "EDXE-EDLM",
                originICAO: "EDXE",
                destinationICAO: "EDLM",
                flightMinutes: 26,
                consumptionLitersPerHour: 25
            ),
            FuelPlanLeg(
                id: "EDLM-EHAM",
                originICAO: "EDLM",
                destinationICAO: "EHAM",
                flightMinutes: 18,
                consumptionLitersPerHour: 25
            ),
            FuelPlanLeg(
                id: "EHAM-EDFZ",
                originICAO: "EHAM",
                destinationICAO: "EDFZ",
                flightMinutes: 124,
                consumptionLitersPerHour: 25
            )
        ]
        let result = FuelPlanCalculator.calculate(
            legs: legs,
            reserveMinutes: 45,
            usableFuelLiters: 98,
            startingFuelLiters: 80,
            refuelAfterLegIndex: 2,
            refuelLiters: 27
        )
        return FuelPlanConfirmation(
            aircraftName: "Aquila A211",
            reserveMinutes: 45,
            usableFuelLiters: 98,
            startingFuelLiters: 80,
            refuelAfterLegIndex: 2,
            refuelLiters: 27,
            airportNames: [
                "EDFZ": "Mainz-Finthen",
                "EDXE": "Rheine-Eschendorf",
                "EDLM": "Marl-Loemühle",
                "EHAM": "Amsterdam Schiphol"
            ],
            result: result,
            confirmedAt: confirmedAt
        )
    }
}
