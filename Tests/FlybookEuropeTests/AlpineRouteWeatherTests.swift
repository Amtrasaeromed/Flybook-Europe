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
}
