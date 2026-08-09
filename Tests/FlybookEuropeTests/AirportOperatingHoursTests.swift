import XCTest
@testable import FlybookEurope

final class AirportOperatingHoursTests: XCTestCase {
    func testEDFERegularHoursAndPPRBoundary() throws {
        let airport = reference(
            "EDFE", latitude: 49.9608, longitude: 8.6436
        )
        XCTAssertEqual(
            assessment(airport, "2026-08-10T05:30:00Z", .edfe),
            .confirmedClosed
        )
        XCTAssertEqual(
            assessment(airport, "2026-08-10T06:30:00Z", .edfe),
            .confirmedOpen
        )
        XCTAssertEqual(
            assessment(airport, "2026-01-12T06:30:00Z", .edfe),
            .confirmedClosed
        )
        XCTAssertEqual(
            assessment(airport, "2026-01-12T07:30:00Z", .edfe),
            .confirmedOpen
        )
    }

    func testEDFMWeekdayAndWeekendHours() throws {
        let airport = reference(
            "EDFM", latitude: 49.4727, longitude: 8.5143
        )
        XCTAssertEqual(
            assessment(airport, "2026-08-10T04:30:00Z", .edfm),
            .confirmedOpen
        )
        XCTAssertEqual(
            assessment(airport, "2026-08-15T05:30:00Z", .edfm),
            .confirmedClosed
        )
        XCTAssertEqual(
            assessment(airport, "2026-08-15T06:30:00Z", .edfm),
            .confirmedOpen
        )
        XCTAssertEqual(
            assessment(airport, "2026-01-10T06:30:00Z", .edfm),
            .confirmedClosed
        )
        XCTAssertEqual(
            assessment(airport, "2026-01-10T07:30:00Z", .edfm),
            .confirmedOpen
        )
    }

    func testDailyOpeningHoursUseAirportLocalTime() throws {
        let airport = reference(
            "EDFM", latitude: 49.4727, longitude: 8.5143
        )
        let instant = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-10T12:00:00Z")
        )
        guard case .confirmed(let windows) =
            AirportOperatingHoursEvaluator.dailyOpeningHours(
                airport: airport,
                at: instant
            )
        else {
            return XCTFail("Expected confirmed daily opening hours")
        }
        let window = try XCTUnwrap(windows.first)
        let formatter = DateFormatter()
        formatter.timeZone = airport.timeZone
        formatter.dateFormat = "HH:mm"
        XCTAssertEqual(formatter.string(from: window.opening), "06:00")
        XCTAssertEqual(formatter.string(from: window.closing), "21:00")
    }

    func testAlternateOpeningHoursFilterHasStrictConfirmedMode() {
        XCTAssertTrue(
            AlternateOpeningHoursFilter.off.includes(.confirmedClosed)
        )
        XCTAssertTrue(
            AlternateOpeningHoursFilter.consider.includes(.unclear)
        )
        XCTAssertFalse(
            AlternateOpeningHoursFilter.consider.includes(.confirmedClosed)
        )
        XCTAssertTrue(
            AlternateOpeningHoursFilter.confirmed.includes(.confirmedOpen)
        )
        XCTAssertFalse(
            AlternateOpeningHoursFilter.confirmed.includes(.unclear)
        )
        XCTAssertFalse(
            AlternateOpeningHoursFilter.confirmed.includes(.confirmedClosed)
        )
    }

    func testEDRYSeasonalHours() throws {
        let airport = reference(
            "EDRY", latitude: 49.3047, longitude: 8.4514
        )
        XCTAssertEqual(
            assessment(airport, "2026-08-10T05:30:00Z", .edry),
            .confirmedOpen
        )
        XCTAssertEqual(
            assessment(airport, "2026-08-15T06:30:00Z", .edry),
            .confirmedClosed
        )
        XCTAssertEqual(
            assessment(airport, "2026-08-15T07:30:00Z", .edry),
            .confirmedOpen
        )
        XCTAssertEqual(
            assessment(airport, "2026-01-10T07:30:00Z", .edry),
            .confirmedClosed
        )
        XCTAssertEqual(
            assessment(airport, "2026-01-10T08:30:00Z", .edry),
            .confirmedOpen
        )
    }

    func testEDRKDateAndDaylightSavingRules() throws {
        let airport = reference(
            "EDRK", latitude: 50.3256, longitude: 7.5286
        )
        XCTAssertEqual(
            assessment(airport, "2026-03-02T06:30:00Z", .edrk),
            .confirmedClosed
        )
        XCTAssertEqual(
            assessment(airport, "2026-03-02T07:30:00Z", .edrk),
            .confirmedOpen
        )
        XCTAssertEqual(
            assessment(airport, "2026-03-30T06:30:00Z", .edrk),
            .confirmedOpen
        )
        XCTAssertEqual(
            assessment(airport, "2026-11-02T07:30:00Z", .edrk),
            .confirmedClosed
        )
        XCTAssertEqual(
            assessment(airport, "2026-11-02T08:30:00Z", .edrk),
            .confirmedOpen
        )
    }

    func testEDGSMonthAndDaylightSavingRules() throws {
        let airport = reference(
            "EDGS", latitude: 50.7077, longitude: 8.083
        )
        XCTAssertEqual(
            assessment(airport, "2026-03-02T06:30:00Z", .edgs),
            .confirmedClosed
        )
        XCTAssertEqual(
            assessment(airport, "2026-03-02T07:30:00Z", .edgs),
            .confirmedOpen
        )
        XCTAssertEqual(
            assessment(airport, "2026-03-30T06:30:00Z", .edgs),
            .confirmedOpen
        )
        XCTAssertEqual(
            assessment(airport, "2026-08-10T05:30:00Z", .edgs),
            .confirmedClosed
        )
        XCTAssertEqual(
            assessment(airport, "2026-08-10T06:30:00Z", .edgs),
            .confirmedOpen
        )
        XCTAssertEqual(
            assessment(airport, "2026-11-02T07:30:00Z", .edgs),
            .confirmedClosed
        )
        XCTAssertEqual(
            assessment(airport, "2026-11-02T08:30:00Z", .edgs),
            .confirmedOpen
        )
    }

    func testPPRAlwaysCountsAsClosed() throws {
        let airport = reference(
            "TEST", latitude: 50, longitude: 8
        )
        let regular = AirportOpeningPeriod(
            fromUTC: "08:00",
            closingReference: .fixed,
            fixedUntilUTC: "09:00"
        )
        let hours = AirportSeasonHours(
            monday: regular, tuesday: regular, wednesday: regular,
            thursday: regular, friday: regular, saturday: regular,
            sunday: regular, holiday: regular,
            outsideHoursPPR: true
        )
        let profile = AirportOpeningHoursProfile(
            summer: hours,
            winter: hours
        )

        XCTAssertEqual(
            assessment(airport, "2026-08-10T10:00:00Z", profile),
            .confirmedClosed
        )
    }

    func testEDFZFlyingWithoutFlightDirectorOverridesPPRFromSixLocal() {
        let beforeSix = ISO8601DateFormatter().date(
            from: "2026-08-10T03:30:00Z"
        )!
        let afterSix = ISO8601DateFormatter().date(
            from: "2026-08-10T04:30:00Z"
        )!
        let regularReturn = ISO8601DateFormatter().date(
            from: "2026-08-10T15:00:00Z"
        )!

        XCTAssertEqual(
            AirportOperatingHoursEvaluator.status(
                airport: .edfz,
                at: beforeSix,
                operation: .departure,
                flyingWithoutFlightDirector: true,
                homeAirportICAO: "EDFZ",
                initialHomeDeparture: beforeSix,
                plannedHomeReturn: regularReturn,
                legOriginICAO: "EDFZ"
            ),
            .closedOrPPR
        )
        XCTAssertEqual(
            AirportOperatingHoursEvaluator.status(
                airport: .edfz,
                at: afterSix,
                operation: .departure,
                flyingWithoutFlightDirector: false,
                homeAirportICAO: "EDFZ",
                initialHomeDeparture: afterSix,
                plannedHomeReturn: regularReturn,
                legOriginICAO: "EDFZ"
            ),
            .closedOrPPR
        )
        XCTAssertEqual(
            AirportOperatingHoursEvaluator.status(
                airport: .edfz,
                at: afterSix,
                operation: .departure,
                flyingWithoutFlightDirector: true,
                homeAirportICAO: "EDFZ",
                initialHomeDeparture: afterSix,
                plannedHomeReturn: regularReturn,
                legOriginICAO: "EDFZ"
            ),
            .flyingWithoutFlightDirector
        )
        XCTAssertEqual(
            AirportOperatingHoursEvaluator.openingAssessment(
                airport: .edfz,
                at: afterSix,
                flyingWithoutFlightDirector: true,
                homeAirportICAO: "EDFZ"
            ),
            .confirmedOpen
        )
        let assessedAlternate = AlternateAirport.edfzPrimaryAirport()
            .assessingOpeningHours(
                at: afterSix,
                flyingWithoutFlightDirector: true,
                homeAirportICAO: "EDFZ"
            )
        XCTAssertEqual(
            assessedAlternate.operatingStatus,
            .flyingWithoutFlightDirector
        )
        XCTAssertEqual(
            assessedAlternate.openingAssessment,
            .confirmedOpen
        )
    }

    func testMainzFOFRuleDoesNotApplyToAnotherHomeAirport() {
        let airport = reference(
            "EDKA", latitude: 50.8231, longitude: 6.1864
        )
        let early = ISO8601DateFormatter().date(
            from: "2026-08-10T04:30:00Z"
        )!

        XCTAssertNotEqual(
            AirportOperatingHoursEvaluator.status(
                airport: airport,
                at: early,
                operation: .departure,
                flyingWithoutFlightDirector: true,
                homeAirportICAO: "EDKA",
                initialHomeDeparture: early,
                plannedHomeReturn: early.addingTimeInterval(10 * 3600),
                legOriginICAO: "EDKA"
            ),
            .flyingWithoutFlightDirector
        )
    }

    private func assessment(
        _ airport: AirportReference,
        _ iso8601: String,
        _ profile: AirportOpeningHoursProfile
    ) -> AirportOpeningAssessment {
        AirportOperatingHoursEvaluator.openingAssessment(
            airport: airport,
            at: ISO8601DateFormatter().date(from: iso8601)!,
            profile: profile
        )
    }

    private func reference(
        _ icao: String,
        latitude: Double,
        longitude: Double
    ) -> AirportReference {
        AirportReference(
            icao: icao,
            name: icao,
            latitude: latitude,
            longitude: longitude,
            elevationFeet: 0,
            timeZone: TimeZone(identifier: "Europe/Berlin")!
        )
    }
}
