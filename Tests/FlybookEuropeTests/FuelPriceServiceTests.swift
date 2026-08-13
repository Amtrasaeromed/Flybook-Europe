import XCTest
@testable import FlybookEurope

final class FuelPriceServiceTests: XCTestCase {
    func testOfficialMarlPageParserUsesGrossPricesAndDate() {
        let html = """
        <h3>Kraftstoff AVGAS 100LL</h3>
        <div>EUR 3,06 pro Liter (Brutto)</div>
        <div>EUR 2,57 pro Liter (Netto)</div>
        <h3>Kraftstoff JET A-1</h3>
        <div>EUR 3,08 pro Liter (Brutto)</div>
        <h3>Kraftstoff SUPER PLUS</h3>
        <div>EUR 2,49 pro Liter (Brutto)</div>
        <div>EUR 2,09 pro Liter (Netto)</div>
        <p>Datenstand: 01.07.2026</p>
        """

        let record = MonthlyFuelPriceService.parseOfficialMarlPage(html)

        XCTAssertEqual(record.avgas, 3.06)
        XCTAssertEqual(record.mogas, 2.49)
        XCTAssertEqual(record.reportedAt, "Stand 01.07.2026")
    }

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
