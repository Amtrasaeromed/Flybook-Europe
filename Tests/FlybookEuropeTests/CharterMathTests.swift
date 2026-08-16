import XCTest
@testable import FlybookEurope

final class CharterMathTests: XCTestCase {
    func testActualFuelBurnDoesNotAddReserveFuel() {
        XCTAssertEqual(
            CharterMath.actualFuelBurnLiters(
                minutes: 90,
                consumptionLitersPerHour: 20
            ),
            30,
            accuracy: 0.001
        )
    }

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

    func testAncillaryAirportFeesAreIndependentFromLandingFeeSwitch() {
        XCTAssertEqual(
            CharterMath.combinedTotalCost(
                charterCostEUR: 500,
                landingFeesEUR: 25,
                includeLandingFees: false,
                ancillaryAirportFeesEUR: 34
            ),
            534
        )
        XCTAssertEqual(
            CharterMath.combinedTotalCost(
                charterCostEUR: 500,
                landingFeesEUR: 25,
                includeLandingFees: true,
                ancillaryAirportFeesEUR: 34
            ),
            559
        )
    }

    func testOvernightParkingCountsLocalCalendarNights() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Zurich"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let arrival = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 18, hour: 19
        )))
        let departure = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 20, hour: 8
        )))

        XCTAssertEqual(
            CharterMath.overnightCount(
                arrival: arrival,
                departure: departure,
                timeZone: timeZone
            ),
            2
        )
    }

    func testSchengenBoundaryUsesCountryNotEuropeanUnion() {
        let germany = AirportReference(
            icao: "EDFZ", name: "Mainz", latitude: 0, longitude: 0,
            elevationFeet: 0, timeZone: .current, country: "DE"
        )
        let switzerland = AirportReference(
            icao: "LSGN", name: "Neuchâtel", latitude: 0, longitude: 0,
            elevationFeet: 0, timeZone: .current, country: "CH"
        )
        let unitedKingdom = AirportReference(
            icao: "EGKB", name: "Biggin Hill", latitude: 0, longitude: 0,
            elevationFeet: 0, timeZone: .current, country: "GB"
        )

        XCTAssertFalse(
            SchengenArea.crossesBoundary(from: germany, to: switzerland)
        )
        XCTAssertTrue(
            SchengenArea.crossesBoundary(from: germany, to: unitedKingdom)
        )
        XCTAssertTrue(
            CustomsTerritory.crossesBoundary(
                from: germany,
                to: switzerland
            )
        )
    }

    func testCustomsControlAirportsFollowTheActualBoundarySegment() {
        let edfz = AirportReference(
            icao: "EDFZ", name: "Mainz", latitude: 0, longitude: 0,
            elevationFeet: 0, timeZone: .current, country: "DE"
        )
        let edtg = AirportReference(
            icao: "EDTG", name: "Bremgarten", latitude: 0, longitude: 0,
            elevationFeet: 0, timeZone: .current, country: "DE"
        )
        let lsgn = AirportReference(
            icao: "LSGN", name: "Neuchâtel", latitude: 0, longitude: 0,
            elevationFeet: 0, timeZone: .current, country: "CH"
        )

        let controls = CustomsFeeRules.controlAirports(
            routes: [[edfz, edtg, lsgn]]
        )

        XCTAssertEqual(controls.exits.map(\.icao), ["EDTG"])
        XCTAssertEqual(controls.entries.map(\.icao), ["LSGN"])
    }

    func testCustomsFeesSeparateEntryAndExitAtChargedAirport() {
        let germany = AirportReference(
            icao: "EDFZ", name: "Mainz", latitude: 0, longitude: 0,
            elevationFeet: 0, timeZone: .current, country: "DE"
        )
        let unitedKingdom = AirportReference(
            icao: "EGKB", name: "Biggin Hill", latitude: 0, longitude: 0,
            elevationFeet: 0, timeZone: .current, country: "GB"
        )
        let switzerland = AirportReference(
            icao: "LSGN", name: "Neuchâtel", latitude: 0, longitude: 0,
            elevationFeet: 0, timeZone: .current, country: "CH"
        )
        let france = AirportReference(
            icao: "LFST", name: "Strasbourg", latitude: 0, longitude: 0,
            elevationFeet: 0, timeZone: .current, country: "FR"
        )

        XCTAssertEqual(
            CustomsFeeRules.controls(
                at: "EGKB",
                routes: [
                    [germany, unitedKingdom],
                    [unitedKingdom, germany]
                ]
            ),
            CustomsControlCounts(entry: 1, exit: 1)
        )
        XCTAssertEqual(
            CustomsFeeRules.controls(
                at: "EGKB",
                routes: [[germany, unitedKingdom]]
            ),
            CustomsControlCounts(entry: 1, exit: 0)
        )
        XCTAssertEqual(
            CustomsFeeRules.controls(
                at: "LSGN",
                routes: [
                    [germany, switzerland],
                    [switzerland, germany]
                ]
            ),
            CustomsControlCounts(entry: 1, exit: 1)
        )
        XCTAssertFalse(
            CustomsTerritory.crossesBoundary(from: germany, to: france)
        )
    }

    func testNeuchatelFeesUseMTOWAndAncillaryRates() throws {
        let profile = AirportLandingFeeProfile.lsgn
        XCTAssertEqual(
            try XCTUnwrap(AirportLandingFeeCalculator.feeEUR(
                profile: profile,
                mtowKilograms: 1_100,
                hasIncreasedNoiseProtection: true,
                chfToEURRate: 1.05
            )),
            33,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(AirportLandingFeeCalculator.ancillaryFeeEUR(
                profile: profile,
                amountText: profile.overnightParkingPerNightEUR,
                count: 2,
                chfToEURRate: 1.05
            )),
            40,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(AirportLandingFeeCalculator.ancillaryFeeEUR(
                profile: profile,
                amountText: profile.customsClearancePerControlEUR,
                count: 2,
                chfToEURRate: 1.05
            )),
            32,
            accuracy: 0.001
        )
        XCTAssertNil(
            AirportLandingFeeCalculator.feeEUR(
                profile: profile,
                mtowKilograms: 1_100,
                hasIncreasedNoiseProtection: true
            )
        )
    }

    func testReichenbachFeesUseExactWeightLimitsAndWinterSurcharge() throws {
        let profile = AirportLandingFeeProfile.lsgr
        let rate = 1.05

        for (weight, expectedEUR) in [
            (999.0, 27.0),
            (1_000.0, 37.0),
            (2_249.0, 37.0),
            (2_250.0, 105.0)
        ] {
            XCTAssertEqual(
                try XCTUnwrap(AirportLandingFeeCalculator.feeEUR(
                    profile: profile,
                    mtowKilograms: weight,
                    hasIncreasedNoiseProtection: true,
                    chfToEURRate: rate
                )),
                expectedEUR,
                accuracy: 0.001
            )
        }

        XCTAssertEqual(
            try XCTUnwrap(AirportLandingFeeCalculator.ancillaryFeeEUR(
                profile: profile,
                amountText: profile.overnightParkingPerNightEUR,
                count: 2,
                chfToEURRate: rate
            )),
            22,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(AirportLandingFeeCalculator.ancillaryFeeEUR(
                profile: profile,
                amountText: profile.customsClearancePerControlEUR,
                count: 1,
                chfToEURRate: rate
            )),
            21,
            accuracy: 0.001
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Zurich"))
        let summer = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 18, hour: 12
        )))
        let winter = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 12, day: 1, hour: 12
        )))

        XCTAssertFalse(AirportLandingFeeCalculator.winterServiceSurchargeApplies(
            profile: profile,
            on: summer
        ))
        XCTAssertTrue(AirportLandingFeeCalculator.winterServiceSurchargeApplies(
            profile: profile,
            on: winter
        ))
        XCTAssertEqual(
            AirportLandingFeeCalculator.quote(
                for: ["LSGR"],
                mtowKilograms: 999,
                hasIncreasedNoiseProtection: true,
                landingDate: winter,
                chfToEURRate: rate,
                profileProvider: { _ in profile }
            ).totalEUR,
            48
        )
        XCTAssertEqual(
            AirportLandingFeeCalculator.quote(
                for: ["LSGR"],
                mtowKilograms: 999,
                hasIncreasedNoiseProtection: true,
                landingDate: winter,
                landingVoucherBookEnabled: true,
                chfToEURRate: rate,
                voucherProvider: { _, _ in true },
                profileProvider: { _ in profile }
            ).totalEUR,
            21
        )
    }

    func testECBParserInvertsEURBaseQuoteForCHFConversion() throws {
        let xml = """
        <gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01"
          xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
          <Cube><Cube time="2026-08-14"><Cube currency="CHF" rate="0.9250"/></Cube></Cube>
        </gesmes:Envelope>
        """
        let fetchedAt = Date(timeIntervalSince1970: 1_786_659_000)
        let quote = try XCTUnwrap(
            ECBExchangeRateParser.chfToEUR(
                from: Data(xml.utf8),
                fetchedAt: fetchedAt
            )
        )
        XCTAssertEqual(quote.referenceDate, "2026-08-14")
        XCTAssertEqual(quote.euroPerCHF, 1 / 0.9250, accuracy: 0.000_001)
        XCTAssertEqual(quote.fetchedAt, fetchedAt)
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
        let partialFeeQuote = AirportLandingFeeQuote(
            knownTotalEUR: 9,
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
        XCTAssertEqual(
            AirportLandingFeeDisplay.text(
                for: partialFeeQuote,
                isEnabled: true
            ),
            "9 € + ?"
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

    func testBremgartenTariffUsesWeekdayWeekendAndWeightBands() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(
            TimeZone(identifier: "Europe/Berlin")
        )
        let weekday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 17, hour: 12
        )))
        let weekend = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 16, hour: 12
        )))

        XCTAssertEqual(
            try XCTUnwrap(AirportLandingFeeCalculator.feeEUR(
                profile: .edtg,
                mtowKilograms: 750,
                hasIncreasedNoiseProtection: true,
                noiseLevelDBA: 65.1,
                landingDate: weekday
            )),
            16.78,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(AirportLandingFeeCalculator.feeEUR(
                profile: .edtg,
                mtowKilograms: 750,
                hasIncreasedNoiseProtection: true,
                noiseLevelDBA: 65.1,
                landingDate: weekend
            )),
            19.40,
            accuracy: 0.001
        )
        XCTAssertNil(AirportLandingFeeCalculator.feeEUR(
            profile: .edtg,
            mtowKilograms: 750,
            hasIncreasedNoiseProtection: true,
            noiseLevelDBA: nil,
            landingDate: weekday
        ))
        XCTAssertEqual(
            try XCTUnwrap(AirportLandingFeeCalculator.feeEUR(
                profile: .edtg,
                mtowKilograms: 750,
                hasIncreasedNoiseProtection: false,
                landingDate: weekday
            )),
            15.71,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(AirportLandingFeeCalculator.ancillaryFeeEUR(
                profile: .edtg,
                amountText: nil,
                weightBands: AirportLandingFeeProfile.edtg.overnightParkingBands,
                mtowKilograms: 750,
                count: 1
            )),
            12.73,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(AirportLandingFeeCalculator.ancillaryFeeEUR(
                profile: .edtg,
                amountText: AirportLandingFeeProfile.edtg.customsClearancePerControlEUR,
                count: 2
            )),
            20.24,
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

    func testSuggestedRefuelRoundsEveryFuelValueUpForSafety() {
        let suggestion = CharterMath.suggestedRefuelLiters(
            startingFuelLiters: 98,
            firstLegBlockFuelLiters: 55.2,
            firstLegRequiredFuelLiters: 65.7,
            secondLegRequiredFuelLiters: 69.2,
            remainingFirstLegFuelIsAvailable: true,
            safetyRoundingIncrementLiters: 1
        )
        XCTAssertEqual(suggestion, 28, accuracy: 0.0001)
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

    func testForeignEHALAddsPriceSurchargeAndNonReimbursedVAT() {
        let loss = CharterMath.refuelLoss(
            grossPricePerLiter: 3.00,
            homeReferencePerLiter: 2.59,
            liters: 26,
            destinationVATPercent: 21,
            isForeign: true
        )
        XCTAssertEqual(loss ?? -1, 24.197_190_082_6, accuracy: 0.0001)
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
