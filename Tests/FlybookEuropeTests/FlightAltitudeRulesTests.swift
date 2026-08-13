import XCTest
@testable import FlybookEurope

final class FlightAltitudeRulesTests: XCTestCase {
    func testDefaultAltitudeIsSelectableForBothCourseGroups() {
        let eastbound = FlightAltitudeRules.options(forCourseDegrees: 90)
        let westbound = FlightAltitudeRules.options(forCourseDegrees: 270)

        XCTAssertTrue(eastbound.contains(FlightAltitudeRules.defaultFeet))
        XCTAssertTrue(westbound.contains(FlightAltitudeRules.defaultFeet))
    }

    func testEveryAltitudeIsSelectableAndRecommendationsFollowCourse() {
        let eastbound = FlightAltitudeRules.options(forCourseDegrees: 90)
        let westbound = FlightAltitudeRules.options(forCourseDegrees: 270)

        XCTAssertEqual(eastbound, FlightAltitudeRules.allOptions)
        XCTAssertEqual(westbound, FlightAltitudeRules.allOptions)
        XCTAssertEqual(eastbound.first, 1_500)
        XCTAssertEqual(eastbound.last, 12_000)
        XCTAssertTrue(FlightAltitudeRules.isRecommended(5_500, forCourseDegrees: 90))
        XCTAssertFalse(FlightAltitudeRules.isRecommended(4_500, forCourseDegrees: 90))
        XCTAssertTrue(FlightAltitudeRules.isRecommended(4_500, forCourseDegrees: 270))
        XCTAssertFalse(FlightAltitudeRules.isRecommended(5_500, forCourseDegrees: 270))
    }

    func testFiveThousandFeetRemainsSelectableEvenWhenNotRecommended() {
        let eastbound = FlightAltitudeRules.options(forCourseDegrees: 90)
        let westbound = FlightAltitudeRules.options(forCourseDegrees: 270)

        XCTAssertEqual(FlightAltitudeRules.nearest(to: 5_000, in: eastbound), 5_000)
        XCTAssertEqual(FlightAltitudeRules.nearest(to: 5_000, in: westbound), 5_000)
    }
}
