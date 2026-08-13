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
        XCTAssertEqual(document.pageCount, 2)
        let outboundPage = try XCTUnwrap(document.page(at: 0))
        let returnPage = try XCTUnwrap(document.page(at: 1))
        for page in [outboundPage, returnPage] {
            XCTAssertEqual(page.bounds(for: .mediaBox).width, 595.28, accuracy: 0.1)
            XCTAssertEqual(page.bounds(for: .mediaBox).height, 841.89, accuracy: 0.1)
        }
        XCTAssertGreaterThan(data.count, 10_000)
        let text = document.string ?? ""
        XCTAssertTrue(text.contains("FLYBRIEF"))
        XCTAssertTrue(text.contains("EDFZ-EDXE-EDLM-EHAM-EDFZ"))
        XCTAssertTrue(text.contains("ETOPS-PIPI MAX"))
        XCTAssertTrue(text.contains("Regulär 08:00-18:00 LCL"))
        XCTAssertTrue(text.contains("Seitenwind rechts 8 G12 kt"))
        XCTAssertTrue(text.contains("Erstellt:"))
        XCTAssertTrue(text.contains("TEILSTRECKE 1/3"))
        XCTAssertTrue(text.contains("EDXE"))
        XCTAssertTrue(outboundPage.string?.contains("HINFLUG") == true)
        XCTAssertFalse(outboundPage.string?.contains("RÜCKFLUG") == true)
        XCTAssertTrue(returnPage.string?.contains("RÜCKFLUG") == true)
        XCTAssertFalse(returnPage.string?.contains("HINFLUG") == true)

        if let output = ProcessInfo.processInfo.environment["FLYBRIEF_PREVIEW_PATH"] {
            try data.write(to: URL(fileURLWithPath: output), options: .atomic)
        }
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
            departure: departure,
            arrival: arrival,
            segments: segments
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
            openingHoursText: "Regulär 08:00-18:00 LCL",
            timeText: time,
            operatingStatus: "Geöffnet",
            operatingLevel: .good,
            referenceRunway: runway == "07" ? "07/25" : "06/24",
            activeRunway: runway,
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
}
