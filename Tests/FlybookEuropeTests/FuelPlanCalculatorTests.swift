import XCTest
@testable import FlybookEurope

final class FuelPlanCalculatorTests: XCTestCase {
    private let legs = [
        FuelPlanLeg(
            id: "A-C", originICAO: "A", destinationICAO: "C",
            flightMinutes: 30, consumptionLitersPerHour: 20
        ),
        FuelPlanLeg(
            id: "C-B", originICAO: "C", destinationICAO: "B",
            flightMinutes: 30, consumptionLitersPerHour: 20
        ),
        FuelPlanLeg(
            id: "B-A", originICAO: "B", destinationICAO: "A",
            flightMinutes: 30, consumptionLitersPerHour: 20
        )
    ]

    func testCalculatedLitersAreAlwaysRoundedUpToWholeLiters() {
        XCTAssertEqual(FuelPlanCalculator.roundedLitersForDisplay(39.2), 40)
        XCTAssertEqual(FuelPlanCalculator.roundedLitersForDisplay(39), 39)
        XCTAssertEqual(FuelPlanCalculator.roundedLitersForDisplay(0.2), 1)
        XCTAssertEqual(FuelPlanCalculator.roundedLitersForDisplay(-0.2), -1)
    }

    func testFuelAvailabilityDistinguishesNoUnknownAndKnown() {
        XCTAssertEqual(FuelPlanFuelAvailability("Nein"), .unavailable)
        XCTAssertEqual(FuelPlanFuelAvailability("?"), .unknown)
        XCTAssertEqual(FuelPlanFuelAvailability("Ja – nur PPR"), .available)
    }

    func testTransferIncludesRefuelAirportAndSelectedQuantity() {
        XCTAssertEqual(
            FuelPlanCalculator.transfer(
                legs: legs,
                refuelAfterLegIndex: 0,
                refuelLiters: 20
            ),
            FuelPlanTransfer(airportICAO: "C", refuelLiters: 20)
        )
        XCTAssertNil(
            FuelPlanCalculator.transfer(
                legs: legs,
                refuelAfterLegIndex: nil,
                refuelLiters: 20
            )
        )
    }

    func testConfirmedPlanOnlyMatchesItsExactPlanningState() {
        let result = FuelPlanCalculator.calculate(
            legs: legs,
            reserveMinutes: 45,
            usableFuelLiters: 60,
            startingFuelLiters: 25,
            refuelAfterLegIndex: 0,
            refuelLiters: 20
        )
        let confirmation = FuelPlanConfirmation(
            aircraftName: "Aquila A211",
            reserveMinutes: 45,
            usableFuelLiters: 60,
            startingFuelLiters: 25,
            refuelAfterLegIndex: 0,
            refuelLiters: 20,
            airportNames: [:],
            result: result,
            confirmedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(
            confirmation.matches(
                legs: legs,
                reserveMinutes: 45,
                usableFuelLiters: 60,
                aircraftName: "Aquila A211",
                startingFuelLiters: 25,
                charterRefuelLiters: 20,
                charterRefuelAirportICAO: "C"
            )
        )
        XCTAssertFalse(
            confirmation.matches(
                legs: legs,
                reserveMinutes: 30,
                usableFuelLiters: 60,
                aircraftName: "Aquila A211",
                startingFuelLiters: 25,
                charterRefuelLiters: 20,
                charterRefuelAirportICAO: "C"
            )
        )
    }

    func testRefuelAtCReusesArrivalReserveForTheReturnTrip() {
        let result = FuelPlanCalculator.calculate(
            legs: legs,
            reserveMinutes: 45,
            usableFuelLiters: 60,
            startingFuelLiters: 25,
            refuelAfterLegIndex: 0,
            refuelLiters: 20
        )

        XCTAssertEqual(result.finalReserveLiters, 15, accuracy: 0.001)
        XCTAssertEqual(result.minimumStartingFuelLiters, 25, accuracy: 0.001)
        XCTAssertEqual(result.minimumRefuelLiters, 20, accuracy: 0.001)
        XCTAssertEqual(result.rows.map(\.stageBurnLiters), [10, 10, 20])
        XCTAssertEqual(result.rows[1].minimumDepartureLiters, 35, accuracy: 0.001)
        XCTAssertEqual(result.rows[2].minimumDepartureLiters, 25, accuracy: 0.001)
        XCTAssertEqual(result.rows[2].plannedArrivalLiters, 15, accuracy: 0.001)
        XCTAssertFalse(result.hasWarning)
    }

    func testVisibleWholeLiterPlanIsConservativeAndArithmeticallyExact() {
        let fractionalLeg = FuelPlanLeg(
            id: "fractional",
            originICAO: "EDFZ",
            destinationICAO: "EDKA",
            flightMinutes: 64,
            consumptionLitersPerHour: 21.5
        )
        let result = FuelPlanCalculator.calculate(
            legs: [fractionalLeg],
            reserveMinutes: 45,
            usableFuelLiters: 98,
            startingFuelLiters: 40.9,
            refuelAfterLegIndex: nil,
            refuelLiters: 0
        )

        let row = try! XCTUnwrap(result.rows.first)
        XCTAssertEqual(row.plannedDepartureLiters, 40)
        XCTAssertEqual(row.leg.burnLiters, 22.933_333, accuracy: 0.001)
        XCTAssertEqual(row.stageBurnLiters, 23)
        XCTAssertEqual(row.plannedArrivalLiters, 17)
        XCTAssertEqual(
            row.plannedDepartureLiters - row.stageBurnLiters,
            row.plannedArrivalLiters
        )
        XCTAssertEqual(
            row.minimumDepartureLiters - row.minimumArrivalLiters,
            row.stageBurnLiters
        )
    }

    func testRefuelAtBRequiresEnoughStartingFuelToReachBWithReserve() {
        let result = FuelPlanCalculator.calculate(
            legs: legs,
            reserveMinutes: 45,
            usableFuelLiters: 60,
            startingFuelLiters: 35,
            refuelAfterLegIndex: 1,
            refuelLiters: 10
        )

        XCTAssertEqual(result.minimumStartingFuelLiters, 35, accuracy: 0.001)
        XCTAssertEqual(result.minimumRefuelLiters, 10, accuracy: 0.001)
        XCTAssertEqual(result.rows.map(\.stageBurnLiters), [10, 20, 10])
        XCTAssertEqual(result.rows[1].minimumArrivalLiters, 15, accuracy: 0.001)
        XCTAssertEqual(result.rows[2].plannedArrivalLiters, 15, accuracy: 0.001)
        XCTAssertFalse(result.hasWarning)
    }

    func testTwoRefuelingStopsCreateThreeIndependentReserveStages() {
        let repeatedAirportLegs = [
            FuelPlanLeg(id: "A-C-1", originICAO: "A", destinationICAO: "C", flightMinutes: 30, consumptionLitersPerHour: 20),
            FuelPlanLeg(id: "C-B", originICAO: "C", destinationICAO: "B", flightMinutes: 30, consumptionLitersPerHour: 20),
            FuelPlanLeg(id: "B-C", originICAO: "B", destinationICAO: "C", flightMinutes: 30, consumptionLitersPerHour: 20),
            FuelPlanLeg(id: "C-A", originICAO: "C", destinationICAO: "A", flightMinutes: 30, consumptionLitersPerHour: 20)
        ]
        let result = FuelPlanCalculator.calculate(
            legs: repeatedAirportLegs,
            reserveMinutes: 45,
            usableFuelLiters: 60,
            startingFuelLiters: 25,
            refuelsByLegIndex: [0: 20, 2: 10]
        )

        XCTAssertEqual(result.minimumRefuelLitersByLegIndex[0], 20)
        XCTAssertEqual(result.minimumRefuelLitersByLegIndex[2], 10)
        XCTAssertEqual(result.rows.map(\.stageBurnLiters), [10, 10, 20, 10])
        XCTAssertEqual(result.rows.map(\.refuelAfterArrivalLiters), [20, 0, 10, 0])
        XCTAssertEqual(result.rows.last?.plannedArrivalLiters, 15)
        XCTAssertFalse(result.hasWarning)

        let candidates = FuelPlanCalculator.refuelCandidateIndices(
            legs: repeatedAirportLegs
        )
        XCTAssertEqual(candidates, [0, 1, 2])
        XCTAssertEqual(
            candidates.map { repeatedAirportLegs[$0].destinationICAO },
            ["C", "B", "C"]
        )
    }

    func testTooSmallTankAndManualShortfallsAreWarnings() {
        let result = FuelPlanCalculator.calculate(
            legs: legs,
            reserveMinutes: 45,
            usableFuelLiters: 30,
            startingFuelLiters: 20,
            refuelAfterLegIndex: 1,
            refuelLiters: 5
        )

        XCTAssertTrue(result.hasCapacityViolation)
        XCTAssertTrue(result.hasStartingFuelShortfall)
        XCTAssertTrue(result.hasRefuelShortfall)
        XCTAssertTrue(result.hasFinalReserveShortfall)
        XCTAssertTrue(result.hasFuelExhaustion)
        XCTAssertLessThan(result.rows.last?.plannedArrivalLiters ?? 0, 0)
        XCTAssertTrue(result.hasWarning)
    }

    func testWithoutRefuelEverythingIsCalculatedBackFromFinalReserve() {
        let result = FuelPlanCalculator.calculate(
            legs: legs,
            reserveMinutes: 45,
            usableFuelLiters: 60,
            startingFuelLiters: 45,
            refuelAfterLegIndex: nil,
            refuelLiters: 0
        )

        XCTAssertEqual(result.minimumStartingFuelLiters, 45, accuracy: 0.001)
        XCTAssertEqual(result.rows.map(\.stageBurnLiters), [10, 20, 30])
        XCTAssertEqual(result.rows.map(\.minimumDepartureLiters), [45, 35, 25])
        XCTAssertEqual(result.rows.map(\.minimumArrivalLiters), [35, 25, 15])
        XCTAssertFalse(result.hasWarning)
    }

    func testActualStateInitiallyFollowsTheConservativePlan() {
        let plan = FuelPlanCalculator.calculate(
            legs: legs,
            reserveMinutes: 45,
            usableFuelLiters: 60,
            startingFuelLiters: 25,
            refuelsByLegIndex: [0: 20]
        )
        let actual = FuelActualCalculator.calculate(
            plan: plan,
            actualStartingFuelLiters: 25,
            actualArrivalOverridesByLegIndex: [:],
            refuelAfterLegIndices: [0]
        )

        XCTAssertEqual(actual.rows.map(\.actualArrivalLiters), [15, 25, 15])
        XCTAssertEqual(
            actual.rows.map(\.requiredRefuelAfterArrivalLiters),
            [20, 0, 0]
        )
        XCTAssertEqual(actual.finalFuelLiters, 15)
        XCTAssertFalse(actual.hasWarning)
    }

    func testExtraActualStartFuelReducesTheLaterRequiredUplift() {
        let plan = FuelPlanCalculator.calculate(
            legs: legs,
            reserveMinutes: 45,
            usableFuelLiters: 60,
            startingFuelLiters: 25,
            refuelsByLegIndex: [0: 20]
        )
        let actual = FuelActualCalculator.calculate(
            plan: plan,
            actualStartingFuelLiters: 35,
            actualArrivalOverridesByLegIndex: [:],
            refuelAfterLegIndices: [0]
        )

        XCTAssertEqual(actual.rows[0].actualArrivalLiters, 25)
        XCTAssertEqual(actual.rows[0].requiredRefuelAfterArrivalLiters, 10)
        XCTAssertEqual(actual.finalFuelLiters, 15)
    }

    func testMeasuredArrivalRecalculatesUpliftAndAllFollowingLegs() {
        let plan = FuelPlanCalculator.calculate(
            legs: legs,
            reserveMinutes: 45,
            usableFuelLiters: 60,
            startingFuelLiters: 25,
            refuelsByLegIndex: [0: 20]
        )
        let actual = FuelActualCalculator.calculate(
            plan: plan,
            actualStartingFuelLiters: 25,
            actualArrivalOverridesByLegIndex: [0: 22],
            refuelAfterLegIndices: [0]
        )

        XCTAssertTrue(actual.rows[0].arrivalWasMeasured)
        XCTAssertEqual(actual.rows[0].requiredRefuelAfterArrivalLiters, 13)
        XCTAssertEqual(actual.rows[1].actualDepartureLiters, 35)
        XCTAssertEqual(actual.finalFuelLiters, 15)
    }

    func testActualStateWarnsWhenFinalReserveIsMissed() {
        let plan = FuelPlanCalculator.calculate(
            legs: legs,
            reserveMinutes: 45,
            usableFuelLiters: 60,
            startingFuelLiters: 45,
            refuelsByLegIndex: [:]
        )
        let actual = FuelActualCalculator.calculate(
            plan: plan,
            actualStartingFuelLiters: 35,
            actualArrivalOverridesByLegIndex: [:],
            refuelAfterLegIndices: []
        )

        XCTAssertEqual(actual.finalFuelLiters, 5)
        XCTAssertTrue(actual.hasFinalReserveShortfall)
        XCTAssertTrue(actual.hasWarning)
    }
}
