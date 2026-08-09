import XCTest
@testable import FlybookEurope

final class FuelPriceServiceTests: XCTestCase {
    func testCachedPricesOverrideSeedWithoutDroppingOtherFuelTypes() {
        let result = MonthlyFuelPriceService.mergedPrices(
            seed: [
                "EDKA": FuelPriceRecord(
                    avgas: 3.00,
                    ul91: 2.70,
                    mogas: nil,
                    reportedAt: "Stammdaten"
                )
            ],
            cached: [
                "EDKA": FuelPriceRecord(
                    avgas: 3.14,
                    mogas: 2.81,
                    reportedAt: "Stand 01.08.2026"
                )
            ]
        )

        XCTAssertEqual(result["EDKA"]?.avgas, 3.14)
        XCTAssertEqual(result["EDKA"]?.ul91, 2.70)
        XCTAssertEqual(result["EDKA"]?.mogas, 2.81)
        XCTAssertEqual(result["EDKA"]?.reportedAt, "Stand 01.08.2026")
    }

    func testSelectedAirportIsCheckedAtMostDaily() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        XCTAssertFalse(
            MonthlyFuelPriceService.shouldRefresh(
                lastCheckedAt: now.addingTimeInterval(-23 * 60 * 60),
                now: now,
                maximumAge: 24 * 60 * 60
            )
        )
        XCTAssertTrue(
            MonthlyFuelPriceService.shouldRefresh(
                lastCheckedAt: now.addingTimeInterval(-24 * 60 * 60),
                now: now,
                maximumAge: 24 * 60 * 60
            )
        )
        XCTAssertTrue(
            MonthlyFuelPriceService.shouldRefresh(
                lastCheckedAt: nil,
                now: now,
                maximumAge: 24 * 60 * 60
            )
        )
    }
}
