import XCTest
@testable import FlybookEurope

final class CharterMathTests: XCTestCase {
    func testLandingFeesAreExcludedUnlessEnabled() {
        XCTAssertEqual(
            CharterMath.combinedTotalCost(
                charterCostEUR: 485,
                landingFeesEUR: 40,
                includeLandingFees: false
            ),
            485
        )
    }

    func testLandingFeesAreIncludedWhenEnabled() {
        XCTAssertEqual(
            CharterMath.combinedTotalCost(
                charterCostEUR: 485,
                landingFeesEUR: 40,
                includeLandingFees: true
            ),
            525
        )
    }

    func testDisabledLandingFeeDisplayHidesEveryValue() {
        let freeVoucherQuote = AirportLandingFeeQuote(
            knownTotalEUR: 0,
            unknownICAOs: []
        )
        let knownFeeQuote = AirportLandingFeeQuote(
            knownTotalEUR: 18,
            unknownICAOs: []
        )
        let unknownFeeQuote = AirportLandingFeeQuote(
            knownTotalEUR: 0,
            unknownICAOs: ["ZZZZ"]
        )

        XCTAssertEqual(
            AirportLandingFeeDisplay.text(
                for: freeVoucherQuote,
                isEnabled: false
            ),
            ""
        )
        XCTAssertEqual(
            AirportLandingFeeDisplay.text(
                for: knownFeeQuote,
                isEnabled: false
            ),
            ""
        )
        XCTAssertEqual(
            AirportLandingFeeDisplay.text(
                for: unknownFeeQuote,
                isEnabled: false
            ),
            ""
        )
        XCTAssertFalse(
            AirportLandingFeeDisplay.text(
                for: freeVoucherQuote,
                isEnabled: true
            ).isEmpty
        )
    }

    func testLandingFeeUsesMTOWBandAndNoiseProtection() throws {
        XCTAssertEqual(
            try XCTUnwrap(
                AirportLandingFeeCalculator.feeEUR(
                    profile: .edfz,
                    mtowKilograms: 750,
                    hasIncreasedNoiseProtection: true
                )
            ),
            10.90,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(
                AirportLandingFeeCalculator.feeEUR(
                    profile: .edfz,
                    mtowKilograms: 1_050,
                    hasIncreasedNoiseProtection: false
                )
            ),
            21.60,
            accuracy: 0.001
        )
    }

    func testLandingFeeQuoteCountsEveryLanding() throws {
        let quote = AirportLandingFeeCalculator.quote(
            for: ["EDFZ", "EDKA", "EDFZ"],
            mtowKilograms: 750,
            hasIncreasedNoiseProtection: true,
            profileProvider: { icao in
                icao == "EDKA" ? .edka : .edfz
            }
        )
        XCTAssertFalse(quote.hasUnknownFees)
        XCTAssertEqual(
            try XCTUnwrap(quote.totalEUR),
            10.90 + 9.00 + 10.90,
            accuracy: 0.001
        )
    }

    func testLandingFeeQuoteKeepsKnownSubtotalButMarksMissingFee() {
        let quote = AirportLandingFeeCalculator.quote(
            for: ["EDFZ", "ZZZZ"],
            mtowKilograms: 750,
            hasIncreasedNoiseProtection: true,
            profileProvider: { icao in
                icao == "EDFZ" ? .edfz : AirportLandingFeeProfile()
            }
        )
        XCTAssertNil(quote.totalEUR)
        XCTAssertEqual(quote.knownTotalEUR, 10.90, accuracy: 0.001)
        XCTAssertEqual(quote.unknownICAOs, ["ZZZZ"])
    }

    func testEnabledVoucherBookMakesEligibleLandingFree() throws {
        let landingDate = try XCTUnwrap(
            Calendar.current.date(
                from: DateComponents(
                    year: LandingVoucherBook.currentYear,
                    month: 8,
                    day: 10
                )
            )
        )
        let quote = AirportLandingFeeCalculator.quote(
            for: ["EDLA"],
            mtowKilograms: 750,
            hasIncreasedNoiseProtection: true,
            landingDate: landingDate,
            landingVoucherBookEnabled: true,
            voucherProvider: { icao, _ in icao == "EDLA" },
            profileProvider: { _ in AirportLandingFeeProfile() }
        )

        XCTAssertFalse(quote.hasUnknownFees)
        XCTAssertEqual(try XCTUnwrap(quote.totalEUR), 0, accuracy: 0.001)
    }

    func testVoucherDoesNotApplyWhenBookIsDisabled() throws {
        let quote = AirportLandingFeeCalculator.quote(
            for: ["EDLA"],
            mtowKilograms: 750,
            hasIncreasedNoiseProtection: true,
            landingDate: Date(),
            landingVoucherBookEnabled: false,
            voucherProvider: { _, _ in true },
            profileProvider: { _ in .edfz }
        )

        XCTAssertEqual(
            try XCTUnwrap(quote.totalEUR),
            10.90,
            accuracy: 0.001
        )
    }

    func testVoucherRequiresMatchingFlightYear() throws {
        let nextYearDate = try XCTUnwrap(
            Calendar.current.date(
                from: DateComponents(
                    year: LandingVoucherBook.currentYear + 1,
                    month: 1,
                    day: 2
                )
            )
        )

        XCTAssertFalse(LandingVoucherBook.includes("EDLA", on: nextYearDate))
    }

    func testPreferredRunwayUsesConfiguredReferenceRunwayForAnyAirport() {
        XCTAssertEqual(
            EDFZRunway.activeRunway(
                for: "LFMD",
                referenceRunway: "17/35",
                windFromDegrees: 180,
                speedKnots: 8
            ),
            "17"
        )
        XCTAssertEqual(
            EDFZRunway.activeRunway(
                for: "LOWK",
                referenceRunway: "10L/28R",
                windFromDegrees: 275,
                speedKnots: 8
            ),
            "28R"
        )
    }
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

    func testSuggestedRefuelUsesRemainingFuelAfterFirstLeg() {
        XCTAssertEqual(
            CharterMath.suggestedRefuelLiters(
                startingFuelLiters: 45,
                firstLegBlockFuelLiters: 30,
                firstLegRequiredFuelLiters: 45,
                secondLegRequiredFuelLiters: 50,
                remainingFirstLegFuelIsAvailable: true
            ),
            35,
            accuracy: 0.0001
        )
    }

    func testSuggestedRefuelAssumesFirstLegFuelIsGoneByDefault() {
        XCTAssertEqual(
            CharterMath.suggestedRefuelLiters(
                startingFuelLiters: 45,
                firstLegBlockFuelLiters: 30,
                firstLegRequiredFuelLiters: 45,
                secondLegRequiredFuelLiters: 50,
                remainingFirstLegFuelIsAvailable: false
            ),
            50,
            accuracy: 0.0001
        )
    }

    func testSuggestedRefuelCreditsFuelAboveFirstLegMinimum() {
        XCTAssertEqual(
            CharterMath.suggestedRefuelLiters(
                startingFuelLiters: 60,
                firstLegBlockFuelLiters: 30,
                firstLegRequiredFuelLiters: 45,
                secondLegRequiredFuelLiters: 50,
                remainingFirstLegFuelIsAvailable: false
            ),
            35,
            accuracy: 0.0001
        )
    }

    func testSuggestedRefuelRoundsDisplayedReturnRequirementUp() {
        let rawSuggestion = CharterMath.suggestedRefuelLiters(
            startingFuelLiters: 68,
            firstLegBlockFuelLiters: 52.3,
            firstLegRequiredFuelLiters: 68,
            secondLegRequiredFuelLiters: 64.2,
            remainingFirstLegFuelIsAvailable: false
        )
        XCTAssertEqual(ceil(rawSuggestion), 65)
    }

    func testRefueledRouteIsGreenWhenMinimumIsMet() {
        XCTAssertEqual(
            CharterMath.fuelStatus(
                totalRequiredFuelLiters: 132,
                usableFuelLiters: 100,
                startingFuelLiters: 68,
                estimatedFuelAtTripEndWithoutRefuelLiters: -49,
                refuelEnabled: true,
                refuelLiters: 65,
                minimumRequiredRefuelLiters: 65,
                estimatedFuelAtTripEndLiters: 15
            ),
            .sufficient
        )
    }

    func testRefueledRouteIsYellowAtTenPercentRemaining() {
        XCTAssertEqual(
            CharterMath.fuelStatus(
                totalRequiredFuelLiters: 132,
                usableFuelLiters: 100,
                startingFuelLiters: 68,
                estimatedFuelAtTripEndWithoutRefuelLiters: -49,
                refuelEnabled: true,
                refuelLiters: 65,
                minimumRequiredRefuelLiters: 65,
                estimatedFuelAtTripEndLiters: 10
            ),
            .warning
        )
    }

    func testRefueledRouteIsRedBelowMinimumRefuel() {
        XCTAssertEqual(
            CharterMath.fuelStatus(
                totalRequiredFuelLiters: 132,
                usableFuelLiters: 100,
                startingFuelLiters: 68,
                estimatedFuelAtTripEndWithoutRefuelLiters: -49,
                refuelEnabled: true,
                refuelLiters: 64,
                minimumRequiredRefuelLiters: 65,
                estimatedFuelAtTripEndLiters: 14
            ),
            .critical
        )
    }

    func testRouteWithoutRefuelIsGreenWhenStartingFuelCoversBothLegs() {
        XCTAssertEqual(
            CharterMath.fuelStatus(
                totalRequiredFuelLiters: 80,
                usableFuelLiters: 100,
                startingFuelLiters: 90,
                estimatedFuelAtTripEndWithoutRefuelLiters: 20,
                refuelEnabled: false,
                refuelLiters: 0,
                minimumRequiredRefuelLiters: 0,
                estimatedFuelAtTripEndLiters: 20
            ),
            .sufficient
        )
    }

    func testRouteWithoutRefuelIsYellowInLastTenPercent() {
        XCTAssertEqual(
            CharterMath.fuelStatus(
                totalRequiredFuelLiters: 90,
                usableFuelLiters: 100,
                startingFuelLiters: 95,
                estimatedFuelAtTripEndWithoutRefuelLiters: 10,
                refuelEnabled: false,
                refuelLiters: 0,
                minimumRequiredRefuelLiters: 0,
                estimatedFuelAtTripEndLiters: 10
            ),
            .warning
        )
    }

    func testRouteWithoutRefuelIsRedWhenStartingFuelDoesNotCoverTrip() {
        XCTAssertEqual(
            CharterMath.fuelStatus(
                totalRequiredFuelLiters: 90,
                usableFuelLiters: 100,
                startingFuelLiters: 60,
                estimatedFuelAtTripEndWithoutRefuelLiters: -15,
                refuelEnabled: false,
                refuelLiters: 0,
                minimumRequiredRefuelLiters: 0,
                estimatedFuelAtTripEndLiters: -15
            ),
            .critical
        )
    }

    func testRunwayComponentsShowCrosswindFromRight() throws {
        let components = try XCTUnwrap(
            EDFZRunway.windComponents(
                for: "EDKA",
                runway: "07",
                windFromDegrees: 160,
                speedKnots: 10,
                gustKnots: 17
            )
        )
        XCTAssertEqual(components.headwindKnots, 0, accuracy: 0.0001)
        XCTAssertEqual(components.crosswindKnots, 10, accuracy: 0.0001)
        XCTAssertEqual(
            try XCTUnwrap(components.gustCrosswindKnots),
            17,
            accuracy: 0.0001
        )
        XCTAssertTrue(components.crosswindComesFromRight)
    }

    func testRunwayComponentsShowCrosswindFromLeft() throws {
        let components = try XCTUnwrap(
            EDFZRunway.windComponents(
                for: "EDKA",
                runway: "07",
                windFromDegrees: 340,
                speedKnots: 10
            )
        )
        XCTAssertEqual(components.headwindKnots, 0, accuracy: 0.0001)
        XCTAssertEqual(components.crosswindKnots, 10, accuracy: 0.0001)
        XCTAssertFalse(components.crosswindComesFromRight)
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
