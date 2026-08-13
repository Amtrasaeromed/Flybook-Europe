import XCTest
@testable import FlybookEurope

final class MultiStopTimeTests: XCTestCase {
    func testEditingSecondArrivalDoesNotChangeOtherMultiStopTimes() throws {
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let date = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-13T00:00:00Z")
        )
        let automatic = ["09:00", "11:00", "12:00", "14:00"].map {
            FlightDateTime.instant(
                date: date,
                timeText: $0,
                timeZone: timeZone
            )
        }

        let unchangedFirstDeparture = automatic[0]
        let unchangedFirstArrival = MultiStopTimeResolver.instant(
            manualText: "11:00",
            date: date,
            timeZone: timeZone,
            automatic: automatic[1]
        )
        let unchangedSecondDeparture = MultiStopTimeResolver.instant(
            manualText: "12:00",
            date: date,
            timeZone: timeZone,
            automatic: automatic[2]
        )
        let editedSecondArrival = MultiStopTimeResolver.instant(
            manualText: "15:30",
            date: date,
            timeZone: timeZone,
            automatic: automatic[3]
        )

        XCTAssertEqual(unchangedFirstDeparture, automatic[0])
        XCTAssertEqual(unchangedFirstArrival, automatic[1])
        XCTAssertEqual(unchangedSecondDeparture, automatic[2])
        XCTAssertEqual(
            editedSecondArrival,
            FlightDateTime.instant(
                date: date,
                timeText: "15:30",
                timeZone: timeZone
            )
        )
    }
}
