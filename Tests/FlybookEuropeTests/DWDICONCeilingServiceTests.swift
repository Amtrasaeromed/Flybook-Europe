import Foundation
import XCTest
@testable import FlybookEurope

final class DWDICONCeilingServiceTests: XCTestCase {
    func testMainzTargetPrefersDirectICOND2Ceiling() throws {
        let now = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-16T18:00:00Z")
        )
        let target = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-18T07:00:00Z")
        )
        let candidates = DWDICONCeilingService.candidates(
            validTime: target,
            now: now
        )
        let first = try XCTUnwrap(candidates.first)

        XCTAssertEqual(first.model, .iconD2)
        XCTAssertEqual(first.cycle, 15)
        XCTAssertEqual(first.forecastHour, 40)
        XCTAssertEqual(
            first.url?.absoluteString,
            "https://opendata.dwd.de/weather/nwp/icon-d2/grib/15/ceiling/"
                + "icon-d2_germany_regular-lat-lon_single-level_"
                + "2026081615_040_2d_ceiling.grib2.bz2"
        )
    }

    func testICONEUIsUsedBeyondD2Range() throws {
        let now = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-16T18:00:00Z")
        )
        let target = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-20T07:00:00Z")
        )
        let candidates = DWDICONCeilingService.candidates(
            validTime: target,
            now: now
        )

        XCTAssertFalse(candidates.contains { $0.model == .iconD2 })
        let first = try XCTUnwrap(candidates.first)
        XCTAssertEqual(first.model, .iconEU)
        XCTAssertEqual(first.forecastHour, 87)
        XCTAssertTrue(
            first.url?.absoluteString.hasSuffix("_087_CEILING.grib2.bz2")
                == true
        )
    }

    func testNoDirectCeilingBeyondICONEURange() throws {
        let now = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-16T18:00:00Z")
        )
        let target = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-24T07:00:00Z")
        )

        XCTAssertTrue(
            DWDICONCeilingService.candidates(validTime: target, now: now)
                .isEmpty
        )
    }

    func testLiveDirectCeilingWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment[
            "FLYBOOK_LIVE_DWD_CEILING_TEST"
        ] == "1" else {
            throw XCTSkip("Nur für den expliziten DWD-Ceiling-Quellencheck")
        }
        let target = Date().addingTimeInterval(24 * 60 * 60)
        let value = await DWDICONCeilingService.shared.ceiling(
            latitude: 49.9689,
            longitude: 8.1472,
            validTime: target
        )

        XCTAssertNotNil(value)
        XCTAssertEqual(value?.source, .dwdICOND2)
        XCTAssertGreaterThanOrEqual(value?.feetAGL ?? -1, 0)
    }
}
