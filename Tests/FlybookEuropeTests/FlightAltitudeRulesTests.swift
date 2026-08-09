import XCTest
@testable import FlybookEurope

final class FlightAltitudeRulesTests: XCTestCase {
    func testDefaultAltitudeIsSelectableForBothCourseGroups() {
        let eastbound = FlightAltitudeRules.options(forCourseDegrees: 90)
        let westbound = FlightAltitudeRules.options(forCourseDegrees: 270)

        XCTAssertTrue(eastbound.contains(FlightAltitudeRules.defaultFeet))
        XCTAssertTrue(westbound.contains(FlightAltitudeRules.defaultFeet))
    }

    func testSemicircularAltitudeOptionsAreCourseCorrect() {
        let eastbound = FlightAltitudeRules.options(forCourseDegrees: 90)
        let westbound = FlightAltitudeRules.options(forCourseDegrees: 270)

        XCTAssertEqual(eastbound, [2_500, 3_500, 5_500, 7_500, 9_500])
        XCTAssertEqual(westbound, [2_500, 4_500, 6_500, 8_500])
        XCTAssertFalse(eastbound.contains(4_500))
        XCTAssertFalse(westbound.contains(3_500))
    }

    func testLegacyFiveThousandFeetNormalizesToSelectableAltitude() {
        let eastbound = FlightAltitudeRules.options(forCourseDegrees: 90)
        let westbound = FlightAltitudeRules.options(forCourseDegrees: 270)

        XCTAssertEqual(
            FlightAltitudeRules.nearest(to: 5_000, in: eastbound),
            5_500
        )
        XCTAssertEqual(
            FlightAltitudeRules.nearest(to: 5_000, in: westbound),
            4_500
        )
    }
}
