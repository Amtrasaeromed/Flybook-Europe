import XCTest
@testable import FlybookEurope

final class AlpineRouteWeatherTests: XCTestCase {
    func testRainAtOneThousandFeetTerrainClearanceIsVeryCritical() {
        let assessment = AlpineRouteWeatherEvaluator.assess(
            baseRisk: .blue,
            isAlpine: true,
            controllingTerrainFeetMSL: 6_000,
            ceilingClearanceFeet: 1_000,
            visibilityMeters: 10_000,
            precipitationMillimeters: 0.2
        )

        XCTAssertEqual(assessment.risk, .purple)
        XCTAssertTrue(assessment.explanation.contains("Niederschlag"))
    }

    func testSameWeatherOutsideAlpsKeepsBaseRisk() {
        let assessment = AlpineRouteWeatherEvaluator.assess(
            baseRisk: .blue,
            isAlpine: false,
            controllingTerrainFeetMSL: 1_000,
            ceilingClearanceFeet: 1_000,
            visibilityMeters: 10_000,
            precipitationMillimeters: 0.2
        )

        XCTAssertEqual(assessment.risk, .blue)
    }

    func testVeryLowAlpineVisibilityIsVeryCritical() {
        let assessment = AlpineRouteWeatherEvaluator.assess(
            baseRisk: .green,
            isAlpine: true,
            controllingTerrainFeetMSL: 5_000,
            ceilingClearanceFeet: 6_000,
            visibilityMeters: 4_000,
            precipitationMillimeters: 0
        )

        XCTAssertEqual(assessment.risk, .purple)
    }

    func testAlpineRegionRecognizesLocarnoButNotMainz() {
        XCTAssertTrue(AlpineRegion.contains(latitude: 46.00, longitude: 8.91))
        XCTAssertFalse(AlpineRegion.contains(latitude: 49.97, longitude: 8.15))
    }

    func testThreeFoehnAxesCoverWesternCentralAndEasternAlps() {
        XCTAssertEqual(
            AlpineFoehnAxis.nearest(toLatitude: 45.90, longitude: 6.13),
            .west
        )
        XCTAssertEqual(
            AlpineFoehnAxis.nearest(toLatitude: 47.46, longitude: 8.56),
            .central
        )
        XCTAssertEqual(
            AlpineFoehnAxis.nearest(toLatitude: 47.27, longitude: 11.40),
            .east
        )
    }

    func testAirportFoehnUsesOnlyItsRegionalAxisAndAffectedSide() {
        let instant = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            AlpineFoehnPressureSample(
                axis: .west,
                instant: instant,
                pressureDifferenceHPA: 10
            ),
            AlpineFoehnPressureSample(
                axis: .central,
                instant: instant,
                pressureDifferenceHPA: 5
            ),
            AlpineFoehnPressureSample(
                axis: .east,
                instant: instant,
                pressureDifferenceHPA: 8
            )
        ]
        let zurich = airport("LSZH", latitude: 47.4581, longitude: 8.5555)
        let lugano = airport("LSZA", latitude: 46.0043, longitude: 8.9106)

        XCTAssertEqual(
            AlpineFoehnEvaluator.maximumRelevantMagnitude(
                in: samples,
                for: zurich,
                from: instant.addingTimeInterval(-60),
                until: instant.addingTimeInterval(60)
            ),
            5
        )
        XCTAssertEqual(
            AlpineFoehnEvaluator.maximumRelevantMagnitude(
                in: samples,
                for: lugano,
                from: instant.addingTimeInterval(-60),
                until: instant.addingTimeInterval(60)
            ),
            0,
            "Positive Süd−Nord-Differenz betrifft nur die Nordseite"
        )
    }

    func testHighestFoehnWarningMapsToPurpleRouteWeather() {
        XCTAssertNil(AlpineFoehnEvaluator.routeRisk(forMagnitude: 1.9))
        XCTAssertEqual(AlpineFoehnEvaluator.routeRisk(forMagnitude: 2), .blue)
        XCTAssertEqual(AlpineFoehnEvaluator.routeRisk(forMagnitude: 4), .red)
        XCTAssertEqual(AlpineFoehnEvaluator.routeRisk(forMagnitude: 6), .purple)
    }

    func testAirportFoehnLimitIsStrictlyLessThanSelectedValue() {
        let instant = Date(timeIntervalSince1970: 1_700_000_000)
        let zurich = airport("LSZH", latitude: 47.4581, longitude: 8.5555)
        let samples = [AlpineFoehnPressureSample(
            axis: .central,
            instant: instant,
            pressureDifferenceHPA: 2
        )]

        XCTAssertEqual(
            AlpineFoehnEvaluator.airportMatches(
                samples: samples,
                airport: zurich,
                from: instant,
                until: instant,
                maximumExclusive: 2
            ),
            false
        )
        XCTAssertEqual(
            AlpineFoehnEvaluator.airportMatches(
                samples: samples,
                airport: zurich,
                from: instant,
                until: instant,
                maximumExclusive: 2.1
            ),
            true
        )
    }

    func testRouteCrossingAlpsIsDetectedWithRemoteEndpoints() {
        let mainz = airport("EDFZ", latitude: 49.97, longitude: 8.15)
        let milan = airport("LIML", latitude: 45.45, longitude: 9.28)

        XCTAssertTrue(AlpineRegion.routeCrosses([mainz, milan]))
        XCTAssertTrue(AlpineRegion.foehnAxes(along: [mainz, milan]).contains(.central))
    }

    private func airport(
        _ icao: String,
        latitude: Double,
        longitude: Double
    ) -> AirportReference {
        AirportReference(
            icao: icao,
            name: icao,
            latitude: latitude,
            longitude: longitude,
            elevationFeet: 0,
            timeZone: .gmt
        )
    }
}
