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

    func testCloudLayerDoesNotInventUnknownHeight() {
        XCTAssertEqual(
            AviationWeatherText.cloudAndVisibility(
                lowCloudCoverPercent: 70,
                lowestCloudBaseFeet: nil,
                visibilityMeters: 10_000,
                unitSystem: .eu
            ),
            "BKN Basis n/v / 10km+"
        )
    }

    func testCloudBaseAboveTenThousandFeetIsHidden() {
        XCTAssertEqual(
            AviationWeatherText.cloudAndVisibility(
                lowCloudCoverPercent: 25,
                lowestCloudBaseFeet: 53_200,
                visibilityMeters: 10_000,
                unitSystem: .eu
            ),
            "FEW / 10km+"
        )
    }
}
