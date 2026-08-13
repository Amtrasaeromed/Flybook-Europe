import XCTest
@testable import FlybookEurope

final class FogRiskModelTests: XCTestCase {
    private let base = FogRiskInput(
        temperatureC: 18,
        dewPointC: 8,
        windKt: 7,
        visibilityKm: 20,
        lowCloudPercent: 0,
        ceilingFt: 10_000,
        lowLevelRHPercent: 55,
        totalCloudPercent: 20,
        rainLast6HoursMM: 0,
        isNight: false,
        isValley: false
    )

    func testClearWeatherHasLowRisk() throws {
        let result = try XCTUnwrap(FogRiskModel.calculate(base))
        XCTAssertLessThan(result.score, 25)
        XCTAssertEqual(result.level, .low)
    }

    func testPrecursorsAloneCannotCreateHighRisk() throws {
        let result = try XCTUnwrap(FogRiskModel.calculate(FogRiskInput(
            temperatureC: 8,
            dewPointC: 8,
            windKt: 2,
            visibilityKm: 20,
            lowCloudPercent: 0,
            ceilingFt: 10_000,
            lowLevelRHPercent: 100,
            totalCloudPercent: 20,
            rainLast6HoursMM: 0,
            isNight: true,
            isValley: true
        )))
        XCTAssertLessThanOrEqual(result.score, 49)
    }

    func testLowCeilingCreatesHighRisk() throws {
        let result = try XCTUnwrap(FogRiskModel.calculate(FogRiskInput(
            temperatureC: 10,
            dewPointC: 9,
            windKt: 7,
            visibilityKm: 7,
            lowCloudPercent: 80,
            ceilingFt: 800,
            lowLevelRHPercent: 55,
            totalCloudPercent: 20,
            rainLast6HoursMM: 0,
            isNight: false,
            isValley: false
        )))
        XCTAssertGreaterThanOrEqual(result.score, 50)
        XCTAssertEqual(result.level, .high)
    }

    func testFogCreatesVeryHighRisk() throws {
        let result = try XCTUnwrap(FogRiskModel.calculate(FogRiskInput(
            temperatureC: 9,
            dewPointC: 9,
            windKt: 2,
            visibilityKm: 0.8,
            lowCloudPercent: 0,
            ceilingFt: 10_000,
            lowLevelRHPercent: 100,
            totalCloudPercent: 20,
            rainLast6HoursMM: 0,
            isNight: false,
            isValley: false
        )))
        XCTAssertGreaterThanOrEqual(result.score, 70)
        XCTAssertEqual(result.level, .veryHigh)
    }

    func testVeryLowCeilingCreatesVeryHighRisk() throws {
        let result = try XCTUnwrap(FogRiskModel.calculate(FogRiskInput(
            temperatureC: 18,
            dewPointC: 8,
            windKt: 7,
            visibilityKm: 20,
            lowCloudPercent: 100,
            ceilingFt: 400,
            lowLevelRHPercent: 55,
            totalCloudPercent: 20,
            rainLast6HoursMM: 0,
            isNight: false,
            isValley: false
        )))
        XCTAssertGreaterThanOrEqual(result.score, 70)
        XCTAssertEqual(result.level, .veryHigh)
    }

    func testTimelineUsesSameSeventeenHoursForBothBars() {
        XCTAssertEqual(DailyWeatherTimeline.hours, Array(6...22))
        XCTAssertEqual(DailyWeatherTimeline.hours.count, 17)
    }

    func testSparseSixHourlyForecastFillsIntermediateTimelineHours() {
        let sourceHours = [6, 12, 18]

        XCTAssertEqual(
            SparseForecastTimeline.nearestIndex(in: sourceHours, to: 9),
            0
        )
        XCTAssertEqual(
            SparseForecastTimeline.nearestIndex(in: sourceHours, to: 15),
            1
        )
        XCTAssertEqual(
            SparseForecastTimeline.nearestIndex(in: sourceHours, to: 21),
            2
        )
    }

    func testSparseForecastDoesNotInventDataBeyondThreeHours() {
        XCTAssertNil(
            SparseForecastTimeline.nearestIndex(in: [6, 18], to: 12)
        )
    }
}
