import XCTest
@testable import FlybookEurope

final class AviationWeatherTextTests: XCTestCase {
    func testOvercastAlwaysShowsKnownCloudHeight() {
        XCTAssertEqual(
            AviationWeatherText.cloudAndVisibility(
                lowCloudCoverPercent: 95,
                lowestCloudBaseFeet: 5_960,
                visibilityMeters: 12_000,
                unitSystem: .eu
            ),
            "OVC 6000 / 10km+"
        )
    }

    func testCloudLayerNeverSilentlyOmitsUnknownHeight() {
        XCTAssertEqual(
            AviationWeatherText.cloudAndVisibility(
                lowCloudCoverPercent: 70,
                lowestCloudBaseFeet: nil,
                visibilityMeters: 10_000,
                unitSystem: .eu
            ),
            "BKN Höhe ? / 10km+"
        )
    }
}
