import XCTest
@testable import FlybookEurope

final class MultiStopTimeTests: XCTestCase {
    func testSecondDepartureUpdatesSecondArrival() throws {
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let date = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-13T00:00:00Z")
        )

        XCTAssertEqual(
            MultiStopTimeLinker.arrivalText(
                departureText: "12:00",
                date: date,
                departureTimeZone: timeZone,
                arrivalTimeZone: timeZone,
                travelMinutes: 150
            ),
            "14:30"
        )
    }

    func testChangedRouteDurationRecalculatesArrivalFromDeparture() throws {
        let berlin = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let date = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-18T00:00:00Z")
        )

        XCTAssertEqual(
            MultiStopTimeLinker.arrivalText(
                departureText: "11:00",
                date: date,
                departureTimeZone: berlin,
                arrivalTimeZone: berlin,
                travelMinutes: 64
            ),
            "12:04"
        )
    }

    func testSecondArrivalUpdatesSecondDeparture() throws {
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let date = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-13T00:00:00Z")
        )

        XCTAssertEqual(
            MultiStopTimeLinker.departureText(
                arrivalText: "15:30",
                date: date,
                departureTimeZone: timeZone,
                arrivalTimeZone: timeZone,
                travelMinutes: 150
            ),
            "13:00"
        )
    }

    func testLinkedTimesRespectAirportTimeZones() throws {
        let berlin = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let london = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let date = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-13T00:00:00Z")
        )

        XCTAssertEqual(
            MultiStopTimeLinker.arrivalText(
                departureText: "12:00",
                date: date,
                departureTimeZone: berlin,
                arrivalTimeZone: london,
                travelMinutes: 120
            ),
            "13:00"
        )
    }

    func testIncompleteManualTimeDoesNotMoveLinkedTime() throws {
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        XCTAssertNil(
            MultiStopTimeLinker.arrivalText(
                departureText: "12:",
                date: Date(),
                departureTimeZone: timeZone,
                arrivalTimeZone: timeZone,
                travelMinutes: 90
            )
        )
    }

    func testManualReturnDepartureMovesReturnArrival() throws {
        let berlin = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let date = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-18T00:00:00Z")
        )

        XCTAssertEqual(
            MultiStopTimeLinker.arrivalText(
                departureText: "14:00",
                date: date,
                departureTimeZone: berlin,
                arrivalTimeZone: berlin,
                travelMinutes: 95
            ),
            "15:35"
        )
    }

    func testManualReturnArrivalMovesReturnDeparture() throws {
        let berlin = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let date = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-18T00:00:00Z")
        )

        XCTAssertEqual(
            MultiStopTimeLinker.departureText(
                arrivalText: "17:00",
                date: date,
                departureTimeZone: berlin,
                arrivalTimeZone: berlin,
                travelMinutes: 95
            ),
            "15:25"
        )
    }
}

final class FlightPlanningDestinationSyncTests: XCTestCase {
    func testManualRoundTripArrivalBecomesHeaderDestination() {
        XCTAssertEqual(
            FlightPlanningDestinationSync.headerICAO(
                forArrivalICAO: "LSGN",
                planningMode: .roundTrip,
                isOneWay: true
            ),
            "LSGN"
        )
    }

    func testManualOneWayArrivalBecomesHeaderDestination() {
        XCTAssertEqual(
            FlightPlanningDestinationSync.headerICAO(
                forArrivalICAO: "LSGN",
                planningMode: .multiStop,
                isOneWay: true
            ),
            "LSGN"
        )
    }

    func testTwoLegMultiStopArrivalDoesNotReplaceHeaderDestination() {
        XCTAssertNil(
            FlightPlanningDestinationSync.headerICAO(
                forArrivalICAO: "LSGN",
                planningMode: .multiStop,
                isOneWay: false
            )
        )
    }

    func testHeaderBrowsingOverridesManualOneWayDestination() {
        XCTAssertEqual(
            FlightPlanningDestinationSync.outboundICAO(
                current: "EDKA",
                headerDestinationICAO: "EDWC",
                planningMode: .multiStop,
                isOneWay: true
            ),
            "EDWC"
        )
    }

    func testHeaderBrowsingPreservesFirstLegOfTwoLegMultiStopPlan() {
        XCTAssertEqual(
            FlightPlanningDestinationSync.outboundICAO(
                current: "EDKA",
                headerDestinationICAO: "EDWC",
                planningMode: .multiStop,
                isOneWay: false
            ),
            "EDKA"
        )
    }

    func testRoundTripUsesHeaderDestinationDirectly() {
        XCTAssertEqual(
            FlightPlanningDestinationSync.outboundICAO(
                current: "EDKA",
                headerDestinationICAO: "EDWC",
                planningMode: .roundTrip,
                isOneWay: true
            ),
            ""
        )
    }
}
