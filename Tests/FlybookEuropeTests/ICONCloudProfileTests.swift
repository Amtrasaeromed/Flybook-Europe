import XCTest
@testable import FlybookEurope

final class ICONCloudProfileTests: XCTestCase {
    func testMainzPressureProfilePlacesCeilingNearWindyAndDWDRange() throws {
        let ceiling = try XCTUnwrap(ICONCloudProfile.ceilingFeetAGL(
            airportElevationFeet: 760,
            levels: [
                .init(cloudCoverPercent: 5, geopotentialHeightMetersMSL: 124),
                .init(cloudCoverPercent: 0, geopotentialHeightMetersMSL: 339),
                .init(cloudCoverPercent: 0, geopotentialHeightMetersMSL: 559),
                .init(cloudCoverPercent: 13, geopotentialHeightMetersMSL: 783.9),
                .init(cloudCoverPercent: 17, geopotentialHeightMetersMSL: 1013.86),
                .init(cloudCoverPercent: 31, geopotentialHeightMetersMSL: 1490),
                .init(cloudCoverPercent: 54, geopotentialHeightMetersMSL: 1991.56),
                .init(cloudCoverPercent: 100, geopotentialHeightMetersMSL: 3078),
            ]
        ))

        XCTAssertEqual(ceiling, 6_430, accuracy: 80)
        XCTAssertGreaterThan(ceiling, 6_000)
    }

    func testInterpolatesBrokenLayerThresholdBetweenPressureLevels() throws {
        let ceiling = try XCTUnwrap(ICONCloudProfile.ceilingFeetAGL(
            airportElevationFeet: 0,
            levels: [
                .init(cloudCoverPercent: 50, geopotentialHeightMetersMSL: 1_000),
                .init(cloudCoverPercent: 75, geopotentialHeightMetersMSL: 2_000),
            ]
        ))

        XCTAssertEqual(ceiling, 4_921, accuracy: 2)
    }

    func testNoBrokenOrOvercastLayerHasNoCeiling() {
        XCTAssertNil(ICONCloudProfile.ceilingFeetAGL(
            airportElevationFeet: 500,
            levels: [
                .init(cloudCoverPercent: 12, geopotentialHeightMetersMSL: 500),
                .init(cloudCoverPercent: 49, geopotentialHeightMetersMSL: 2_000),
            ]
        ))
    }
}
