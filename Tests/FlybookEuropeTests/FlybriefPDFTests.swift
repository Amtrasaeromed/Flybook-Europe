import PDFKit
import XCTest
@testable import FlybookEurope

@MainActor
final class FlybriefPDFTests: XCTestCase {
    func testFlybriefRendersAsOneSearchablePDFPage() throws {
        let snapshot = sampleSnapshot()
        let data = FlybriefPDFExporter.pdfData(for: snapshot)
        let document = try XCTUnwrap(PDFDocument(data: data))

        XCTAssertEqual(
            snapshot.suggestedFilename,
            "Flybrief 13AUG26 EDFZ-EHAM-EDFZ.pdf"
        )
        XCTAssertEqual(document.pageCount, 1)
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(page.bounds(for: .mediaBox).width, 841.89, accuracy: 0.1)
        XCTAssertEqual(page.bounds(for: .mediaBox).height, 595.28, accuracy: 0.1)
        XCTAssertGreaterThan(data.count, 10_000)
        let text = document.string ?? ""
        XCTAssertTrue(text.contains("FLYBRIEF"))
        XCTAssertTrue(text.contains("EDFZ-EHAM-EDFZ"))
        XCTAssertTrue(text.contains("Seitenwind rechts 8 G12 kt"))
        XCTAssertTrue(text.contains("Erstellt:"))

        if let output = ProcessInfo.processInfo.environment["FLYBRIEF_PREVIEW_PATH"] {
            try data.write(to: URL(fileURLWithPath: output), options: .atomic)
        }
    }

    private func sampleSnapshot() -> FlybriefSnapshot {
        let created = Date(timeIntervalSince1970: 1_786_609_800)
        return FlybriefSnapshot(
            title: "Flybrief",
            route: "EDFZ-EHAM-EDFZ",
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
                    )
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
        arrival: FlybriefEndpointSnapshot
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
            etopsText: "126 min",
            etopsLevel: .warning,
            routeWeather: (0..<6).map {
                FlybriefRouteWeatherPoint(
                    id: $0,
                    level: $0 == 4 ? .info : .good
                )
            },
            routeWeatherSummary: "Routenwetter marginal",
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
