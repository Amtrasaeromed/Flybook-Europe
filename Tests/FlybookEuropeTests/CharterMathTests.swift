import XCTest
@testable import FlybookEurope

final class CharterMathTests: XCTestCase {
    func testCommercialBlockTimeRoundsUpBySixMinuteSteps() {
        XCTAssertEqual(CharterMath.commercialDecimalHours(minutes: 65), 1.1)
        XCTAssertEqual(CharterMath.commercialDecimalHours(minutes: 66), 1.1)
        XCTAssertEqual(CharterMath.commercialDecimalHours(minutes: 67), 1.2)
    }

    func testCommercialCostUsesDisplayedRoundedBlockTime() {
        XCTAssertEqual(
            CharterMath.commercialCost(minutes: 67, hourlyRateEUR: 100),
            120,
            accuracy: 0.0001
        )
    }

    func testDomesticEDKALossForTenLiters() {
        let loss = CharterMath.refuelLoss(
            grossPricePerLiter: 2.69,
            homeReferencePerLiter: 2.59,
            liters: 10,
            destinationVATPercent: 19,
            isForeign: false
        )
        XCTAssertEqual(loss ?? -1, 1.00, accuracy: 0.0001)
    }

    func testForeignEHMZLossIncludesNonReimbursedVAT() {
        let loss = CharterMath.refuelLoss(
            grossPricePerLiter: 1.83,
            homeReferencePerLiter: 2.59,
            liters: 10,
            destinationVATPercent: 21,
            isForeign: true
        )
        XCTAssertEqual(loss ?? -1, 3.176_033_057_9, accuracy: 0.0001)
    }

    func testUnknownPriceProducesUnknownLoss() {
        XCTAssertNil(CharterMath.refuelLoss(
            grossPricePerLiter: nil,
            homeReferencePerLiter: 2.59,
            liters: 70,
            destinationVATPercent: 21,
            isForeign: true
        ))
    }

    func testUnknownForeignVATProducesUnknownLoss() {
        XCTAssertNil(CharterMath.refuelLoss(
            grossPricePerLiter: 2.80,
            homeReferencePerLiter: 2.59,
            liters: 70,
            destinationVATPercent: nil,
            isForeign: true
        ))
    }
}
