import XCTest
@testable import FlybookEurope

final class RepresentativeDailyWeatherSymbolTests: XCTestCase {
    func testThreeClearSamplesShowSun() {
        XCTAssertEqual(symbol(0, 0, 0), "sun.max.fill")
    }

    func testClearCloudAndRainAverageToCloud() {
        XCTAssertEqual(symbol(0, 3, 61), "cloud.fill")
    }

    func testTwoClearPeriodsAndOneRainPeriodShowMixedSky() {
        XCTAssertEqual(symbol(0, 0, 61), "cloud.sun.fill")
    }

    func testRainOnlyShowsRain() {
        XCTAssertEqual(symbol(61, 63, 65), "cloud.rain.fill")
    }

    func testSnowShowerCodesAreRecognizedAsSnow() {
        XCTAssertEqual(symbol(85, 86, 85), "cloud.snow.fill")
    }

    func testDailyWorstCodeIsUsedOnlyWhenAllThreeTimesAreMissing() {
        XCTAssertEqual(
            RepresentativeDailyWeatherSymbol.systemName(
                morningCode: nil,
                middayCode: nil,
                eveningCode: nil,
                fallbackDailyCode: 95
            ),
            "cloud.bolt.rain.fill"
        )
        XCTAssertEqual(
            RepresentativeDailyWeatherSymbol.systemName(
                morningCode: 0,
                middayCode: nil,
                eveningCode: nil,
                fallbackDailyCode: 95
            ),
            "sun.max.fill"
        )
    }

    private func symbol(
        _ morning: Int,
        _ midday: Int,
        _ evening: Int
    ) -> String {
        RepresentativeDailyWeatherSymbol.systemName(
            morningCode: morning,
            middayCode: midday,
            eveningCode: evening,
            fallbackDailyCode: nil
        )
    }
}
